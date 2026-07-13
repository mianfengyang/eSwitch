#!/bin/bash

echo "构建 CubeTab.app..."

# 清理旧构建
rm -rf build/CubeTab.app

# 创建 app bundle 结构
mkdir -p build/CubeTab.app/Contents/{MacOS,Resources}

# Release 构建
echo "编译 Release 版本..."
swift build -c release 2>&1

# 复制可执行文件
cp .build/release/CubeTab build/CubeTab.app/Contents/MacOS/

# 复制 Info.plist
cp Sources/CubeTab/Resources/Info.plist build/CubeTab.app/Contents/ 2>/dev/null || cat > build/CubeTab.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>CubeTab</string>
    <key>CFBundleIconFile</key>
    <string>CubeTab.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.cubetab.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CubeTab</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 复制图标
cp Sources/CubeTab/Resources/CubeTab.icns build/CubeTab.app/Contents/Resources/ 2>/dev/null || echo "图标文件不存在"

echo "✅ 构建完成: build/CubeTab.app"
echo "运行: open build/CubeTab.app"
