#!/bin/bash
set -e

APP_NAME="CubeTab"
BUILD_DIR=".build/arm64-apple-macosx/release"
APP_BUNDLE="build/${APP_NAME}.app"

echo "=== CubeTab Build Script ==="
echo ""

# Step 1: Build with Swift Package Manager
echo "[1/3] Building with Swift Package Manager..."
swift build -c release

# Step 2: Create .app bundle structure
echo "[2/3] Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy the icon
if [ -f "Sources/CubeTab/Resources/CubeTab.icns" ]; then
    cp "Sources/CubeTab/Resources/CubeTab.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy Assets.xcassets (for Xcode compatibility, optional)
if [ -d "Sources/CubeTab/Resources/Assets.xcassets" ]; then
    cp -r "Sources/CubeTab/Resources/Assets.xcassets" "$APP_BUNDLE/Contents/Resources/"
fi

# Step 3: Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>CubeTab</string>
	<key>CFBundleDisplayName</key>
	<string>CubeTab</string>
	<key>CFBundleIdentifier</key>
	<string>com.cubetab</string>
	<key>CFBundleShortVersionString</key>
	<string>1.3</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleExecutable</key>
	<string>CubeTab</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 CubeTab</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF

echo ""
echo "=== Build Complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run: open \"$APP_BUNDLE\""
echo "To install: sudo cp -R \"$APP_BUNDLE\" /Applications/"
