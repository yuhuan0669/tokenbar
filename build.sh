#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$DIR/build"
APP_NAME="TokenBar"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DEST_DIR="$HOME/Applications"

echo "=== Building TokenBar for macOS 13 (Ventura) ==="

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/bin"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/ui"

echo "1. Compiling native Swift binary..."
swiftc -target x86_64-apple-macosx13.0 -O "$DIR/src/main.swift" -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "2. Copying resources..."
cp "$DIR/ui/index.html" "$APP_BUNDLE/Contents/Resources/ui/index.html"
cp "$DIR/scanner.py" "$APP_BUNDLE/Contents/Resources/scanner.py"
chmod +x "$APP_BUNDLE/Contents/Resources/scanner.py"

# Copy icon from resources
if [ -f "$DIR/resources/AppIcon.icns" ]; then
    cp "$DIR/resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "3. Creating Info.plist..."
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TokenBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.tokenbar.ventura</string>
    <key>CFBundleName</key>
    <string>TokenBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "4. Deploying to $DEST_DIR..."
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/CodexBar.app"
rm -rf "$DEST_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$DEST_DIR/"

echo "=== Build Complete! Installed to $DEST_DIR/$APP_NAME.app ==="
