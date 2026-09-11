#!/bin/bash
set -e

# 路径一律基于脚本自身所在目录（项目根），不依赖调用方的 cwd
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ORIG_PWD=$(pwd)
cd "$SCRIPT_DIR"

APP_NAME="eSwitch"
APP_BUNDLE="build/${APP_NAME}.app"

# 若指定了 app bundle 路径则用之（默认 build/eSwitch.app，通常由 ./build.sh 产出）
if [ -n "${1:-}" ]; then
    case "$1" in
        /*) APP_BUNDLE="$1" ;;
        *)  APP_BUNDLE="$ORIG_PWD/$1" ;;
    esac
fi

if [ ! -d "$APP_BUNDLE" ]; then
    echo "!! 未找到 $APP_BUNDLE，请先运行 ./build.sh 构建"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo "1.0")
DMG="$(pwd)/build/${APP_NAME}-arm_${VERSION}.dmg"
rm -f "$DMG"

echo "=== eSwitch DMG Packaging ==="
echo ""

# create-dmg 带图标布局；缺失时回退 hdiutil 无布局
if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 640 440 \
        --app-drop-link 400 185 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 170 190 \
        "$DMG" \
        "$APP_BUNDLE"
else
    echo "!! create-dmg 未安装，回退 hdiutil（无图标布局）"
    STAGE="build/dmg-stage"
    rm -rf "$STAGE" && mkdir -p "$STAGE"
    cp -R "$APP_BUNDLE" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    rm -rf "$STAGE"
fi

echo "DMG 打包完成: $DMG"
