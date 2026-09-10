#!/bin/bash
set -e

APP_NAME="eSwitch"
BUILD_DIR=".build/arm64-apple-macosx/release"
APP_BUNDLE="build/${APP_NAME}.app"
ENTITLEMENTS="eSwitch/eSwitch.entitlements"

# 签名身份：优先用环境变量 CODESIGN_IDENTITY 覆盖；否则取钥匙串里第一个 Apple Development 证书。
# 固定身份 + 固定 bundle ID（com.mfyang.eswitch）是 TCC 跨更新保留权限的关键：
# 每次更新签名身份/Bundle ID 不变 → 辅助功能、屏幕录制授权不会被重置。
IDENTITY="${CODESIGN_IDENTITY:-Apple Development: 181500944@qq.com (7W38YLCSFV)}"
BUNDLE_ID="com.mfyang.eswitch"

# 若指定的身份不在钥匙串，回退到第一个可用的 Apple Development 证书
if ! security find-identity -v -p codesigning | grep -qF "(${IDENTITY#* (}"; then
    FIRST=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
    if [ -n "$FIRST" ]; then
        echo "!! 指定身份不存在，回退到: $FIRST"
        IDENTITY="$FIRST"
    fi
fi

echo "=== eSwitch Build Script ==="
echo ""
echo "签名身份: $IDENTITY"
echo "Bundle ID: $BUNDLE_ID"
echo ""

# Step 1: Build with Swift Package Manager
echo "[1/4] Building with Swift Package Manager..."
swift build -c release

# Step 2: Create .app bundle structure
echo "[2/4] Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy the icon
if [ -f "eSwitch/Resources/eSwitch.icns" ]; then
    cp "eSwitch/Resources/eSwitch.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy Assets.xcassets (for Xcode compatibility, optional)
if [ -d "eSwitch/Resources/Assets.xcassets" ]; then
    cp -r "eSwitch/Resources/Assets.xcassets" "$APP_BUNDLE/Contents/Resources/"
fi

# Step 3: Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "Apple Inc." "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>eSwitch</string>
	<key>CFBundleDisplayName</key>
	<string>eSwitch</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleShortVersionString</key>
	<string>1.4</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleExecutable</key>
	<string>eSwitch</string>
	<key>CFBundleIconFile</key>
	<string>eSwitch</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 eSwitch</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF

# Step 4: Code sign (固定身份 + 固定 bundle ID，TCC 权限跨更新保留的关键)
echo "[4/4] Code signing..."
codesign --force --deep --options runtime \
    --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"
codesign --verify --verbose=2 "$APP_BUNDLE" 2>&1 | grep -v "valid on disk" || true
echo "签名完成: $APP_BUNDLE"
echo ""
echo "=== Build Complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""

# Refresh Finder icon cache (mtime bump)
echo "Refreshing icon cache..."
touch "$APP_BUNDLE"
/System/bin/killall -KILL Dock 2>/dev/null || true
echo "Icon cache refreshed."
echo ""
echo "To run: open \"$APP_BUNDLE\""
echo "To install: sudo cp -R \"$APP_BUNDLE\" /Applications/"
