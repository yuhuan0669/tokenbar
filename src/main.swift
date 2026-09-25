import AppKit
import WebKit

class CodexBarAppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var webView: WKWebView!
    var refreshTimer: Timer?
    var isScanning: Bool = false

    let scannerPath: String = {
        // Look in bundle Resources first, then fallback to relative dir
        if let path = Bundle.main.path(forResource: "scanner", ofType: "py") {
            return path
        }
        let localPath = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("scanner.py")
        if FileManager.default.fileExists(atPath: localPath) {
            return localPath
        }
        return Bundle.main.bundlePath + "/Contents/Resources/scanner.py"
    }()

    let dataFilePath: String = NSString(string: "~/.codex/codexbar_data.json").expandingTildeInPath

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        loadCachedData()
        startPeriodicRefresh()

        // Initial scan
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.executeScanner()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = " 🎚️ 31%"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 540)
        popover.behavior = .transient
        popover.animates = true

        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: "refresh")
        contentController.add(self, name: "openPath")
        contentController.add(self, name: "quit")
        config.userContentController = contentController

        // Allow reading local assets
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let viewController = NSViewController()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 360, height: 540), configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent background for native popover look
        webView.navigationDelegate = self

        viewController.view = webView
        popover.contentViewController = viewController

        loadHTML()
    }

    private func loadHTML() {
        var htmlURL: URL?
        if let bundleURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "ui") {
            htmlURL = bundleURL
        } else if let bundleURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            htmlURL = bundleURL
        } else {
            let localPath = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("ui/index.html")
            if FileManager.default.fileExists(atPath: localPath) {
                htmlURL = URL(fileURLWithPath: localPath)
            }
        }

        if let url = htmlURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    var lastScanDate = Date(timeIntervalSince1970: 0)

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Push latest data into webview before showing
            loadCachedData()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()

            // Auto-refresh in background if older than 30 seconds
            if Date().timeIntervalSince(lastScanDate) > 30.0 {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.executeScanner()
                }
            }
        }
    }

    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.executeScanner()
            }
        }
    }

    func executeScanner() {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        lastScanDate = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scannerPath]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let jsonString = String(data: data, encoding: .utf8), !jsonString.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.applyJSONData(jsonString)
                }
            }
        } catch {
            print("Failed to run scanner: \(error)")
        }
    }

    private func loadCachedData() {
        guard FileManager.default.fileExists(atPath: dataFilePath),
              let content = try? String(contentsOfFile: dataFilePath, encoding: .utf8) else {
            return
        }
        applyJSONData(content)
    }

    private func applyJSONData(_ jsonString: String) {
        // Parse basic status for menu bar title
        if let jsonData = jsonString.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let limits = obj["limits"] as? [String: Any],
           let weekly = limits["weekly"] as? [String: Any],
           let leftPct = weekly["left_percent"] as? Int {
            let resetText = weekly["reset_text"] as? String ?? ""
            let shortReset = resetText.replacingOccurrences(of: "Resets in ", with: "")
            statusItem.button?.title = " 🎚️ \(leftPct)%"
            statusItem.button?.toolTip = "Codex: \(leftPct)% left (Resets in \(shortReset))"
        }

        // Escape JSON for injection into JavaScript
        let escaped = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let js = "if (typeof applyData === 'function') { applyData(JSON.parse(`\(escaped)`)); }"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadCachedData()
    }

    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "refresh":
            loadCachedData()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.executeScanner()
            }
        case "openPath":
            if let path = message.body as? String {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
        case "quit":
            NSApplication.shared.terminate(nil)
        default:
            break
        }
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = CodexBarAppDelegate()
app.delegate = delegate
app.run()
