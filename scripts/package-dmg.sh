#!/bin/bash
set -e

# 路径一律基于脚本所在目录的上一级（项目根），不依赖调用方的 cwd
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ORIG_PWD=$(pwd)
cd "$ROOT"

APP_NAME="eSwitch"
APP_BUNDLE="build/${APP_NAME}.app"

# 版本号：从最新 git tag 自动获取（格式 v1.5 → 1.5）
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
if [ -z "$VERSION" ]; then
    # 回退：从 Info.plist 读取
    if [ -n "${1:-}" ]; then
        case "$1" in
            /*) APP_BUNDLE="$1" ;;
            *)  APP_BUNDLE="$ORIG_PWD/$1" ;;
        esac
    fi
    if [ -n "$APP_BUNDLE" ] && [ -d "$APP_BUNDLE" ]; then
        VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo "1.0")
    else
        echo "!! 未找到 git tag，使用默认版本 1.0"
        VERSION="1.0"
    fi
fi

# 若指定了 app bundle 路径则用之（默认 build/eSwitch.app，通常由 ./scripts/build.sh 产出）
if [ -n "${1:-}" ]; then
    case "$1" in
        /*) APP_BUNDLE="$1" ;;
        *)  APP_BUNDLE="$ORIG_PWD/$1" ;;
    esac
fi

if [ ! -d "$APP_BUNDLE" ]; then
    echo "!! 未找到 $APP_BUNDLE，请先运行 ./scripts/build.sh 构建"
    exit 1
fi

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
