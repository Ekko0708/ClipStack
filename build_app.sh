#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

chmod +x "$ROOT/Resources/build_icns.sh" 2>/dev/null || true
"$ROOT/Resources/build_icns.sh"

swift build -c release

APP="$ROOT/build/ClipStack.app"
BIN=$(swift build -c release --show-bin-path)/ClipStack

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/ClipStack"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

chmod +x "$APP/Contents/MacOS/ClipStack"

# ad-hoc 签名（--sign -）：无 Apple 开发者账号时也能给 bundle 一个有效签名，
# 可避免部分系统上「已损坏，无法打开」误报；公开发布仍需 Developer ID + 公证。
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP"
else
  echo "提示: 未找到 codesign，请安装 Xcode 命令行工具后再打包分发。" >&2
fi

# 避免项目 build/ 下的 .app 被 Spotlight 索引，与「应用程序」里已安装的一份同时出现在聚焦里
touch "$ROOT/build/.metadata_never_index" 2>/dev/null || true

echo "Built: $APP"
echo ""
echo "若界面没有变化：请先菜单栏 ClipStack → 退出，再打开上面路径的 .app。"
