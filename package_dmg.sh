#!/usr/bin/env bash
# 生成分发 DMG：可读写的卷上设置背景图与图标位置，再压成 UDZO。
# 必须挂载到 /Volumes/卷名（不要用 -mountpoint 指到临时目录 + -nobrowse），
# 否则 Finder 往往不会把背景图和 .DS_Store 写进映像，用户打开 DMG 仍是白底默认窗口。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

./build_app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT/Resources/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$ROOT/Resources/Info.plist")
VOLNAME="ClipStack ${VERSION:-0}"

mkdir -p "$ROOT/dist"
DMG="$ROOT/dist/ClipStack-${VERSION}-b${BUILD}.dmg"
rm -f "$DMG"

RW=$(mktemp "${TMPDIR:-/tmp}/clipstack-rw.XXXXXX.dmg")
rm -f "$RW"

MNT=""
fail_cleanup() {
  if [[ -n "${MNT:-}" && -d "$MNT" ]]; then
    hdiutil detach "$MNT" -quiet -force 2>/dev/null || true
  fi
  rm -f "$RW"
}
trap fail_cleanup ERR

hdiutil create -size 220m -fs HFS+ -volname "$VOLNAME" "$RW"
# 默认挂到 /Volumes/<volname>，且不要用 -nobrowse（否则 Finder 常无法套用背景）
ATTACH_OUT=$(hdiutil attach "$RW" -readwrite -owners on)
MNT=$(printf '%s\n' "$ATTACH_OUT" | grep -E '/Volumes/.+' | grep -o '/Volumes/.*' | tail -1 | tr -d '\r')
if [[ -z "$MNT" || ! -d "$MNT" ]]; then
  echo "错误: 无法解析挂载点。hdiutil 输出：" >&2
  printf '%s\n' "$ATTACH_OUT" >&2
  exit 1
fi

DISK_TITLE=$(basename "$MNT")
export DISK_TITLE

mkdir -p "$MNT/.background"
BG_SRC="$ROOT/Resources/dmg_background.png"

# 小「浮窗」安装盘：图标区与 1536:1024 同比例，默认 480×320pt。
# Finder 图标视图的背景图在多数 macOS 版本上按「1 图像像素 ≈ 1 pt」铺满内容区（不按 @2x 自动缩放）。
# 若用 2× 像素（如 960×640）塞进 480×320pt 区域，只看得见图的左上角，表现为裁切/放大，与底图完全对不上。
TITLEBAR_PT=${CLIPSTACK_DMG_TITLEBAR:-52}
INNER_H=${CLIPSTACK_DMG_INNER_H:-320}
INNER_W=$(( INNER_H * 1536 / 1024 ))
OUTER_H=$((INNER_H + TITLEBAR_PT))
OUTER_W=$INNER_W
DMG_L=120
DMG_T=120
DMG_R=$((DMG_L + OUTER_W))
DMG_B=$((DMG_T + OUTER_H))

BG_OUT="$MNT/.background/background.png"
# 1 = 与窗口逻辑尺寸 1:1（推荐）。设为 2 可试 Retina（仍可能对不齐，仅调试用）。
CLIPSTACK_DMG_BG_SCALE=${CLIPSTACK_DMG_BG_SCALE:-1}
if [[ -f "$BG_SRC" ]]; then
  PH=$(( INNER_H * CLIPSTACK_DMG_BG_SCALE ))
  PW=$(( INNER_W * CLIPSTACK_DMG_BG_SCALE ))
  if ! sips -z "$PH" "$PW" "$BG_SRC" --out "$BG_OUT" >/dev/null 2>&1; then
    cp "$BG_SRC" "$BG_OUT"
  fi
else
  echo "警告: 缺少 $BG_SRC，DMG 窗口将无自定义背景"
fi

cp -R "$ROOT/build/ClipStack.app" "$MNT/"
ln -s /Applications "$MNT/应用程序"

# 图标约为图标区宽度的 26%～30%（浮窗下要够大才跟背景配）。
# position 坐标系为图标视图左上角原点、y 向下：较小 y 靠上；底图拖放区在下方，默认 y 放在偏下约 64%。
if [[ -n "${CLIPSTACK_DMG_ICON_SIZE:-}" ]]; then
  ICON_SZ="$CLIPSTACK_DMG_ICON_SIZE"
else
  ICON_SZ=$(( INNER_W * 28 / 100 ))
  [[ "$ICON_SZ" -lt 104 ]] && ICON_SZ=104
  [[ "$ICON_SZ" -gt 144 ]] && ICON_SZ=144
fi
APP_X=${CLIPSTACK_DMG_APP_X:-$((INNER_W * 21 / 100))}
APPS_X=${CLIPSTACK_DMG_APPS_X:-$((INNER_W * 76 / 100))}
ICON_Y=${CLIPSTACK_DMG_ICON_Y:-$((INNER_H * 64 / 100))}

export BG_POSIX="$BG_OUT"
export DMG_L DMG_T DMG_R DMG_B
export DMG_APP_X="$APP_X" DMG_APPS_X="$APPS_X" DMG_ICON_Y="$ICON_Y" DMG_ICON_SZ="$ICON_SZ"

# 用卷的 POSIX 路径设背景；DISK_TITLE 用实际挂载名（避免重名时变成 ClipStack x.x 2）
if /usr/bin/osascript <<'APPLESCRIPT'
set bgPath to (system attribute "BG_POSIX")
set diskTitle to (system attribute "DISK_TITLE")
if (length of bgPath) is 0 or (length of diskTitle) is 0 then error "BG_POSIX 或 DISK_TITLE 为空"
set bgFile to POSIX file bgPath as alias
set bL to (system attribute "DMG_L") as integer
set bT to (system attribute "DMG_T") as integer
set bR to (system attribute "DMG_R") as integer
set bB to (system attribute "DMG_B") as integer
set iAppX to (system attribute "DMG_APP_X") as integer
set iAppsX to (system attribute "DMG_APPS_X") as integer
set iY to (system attribute "DMG_ICON_Y") as integer
set iSz to (system attribute "DMG_ICON_SZ") as integer
tell application "Finder"
  activate
  delay 0.5
  tell disk diskTitle
    open
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      try
        set sidebar width to 0
      end try
      set the bounds to {bL, bT, bR, bB}
      set opts to the icon view options of it
      set arrangement of opts to not arranged
      set icon size of opts to iSz
      set background picture of opts to bgFile
      try
        set label position of opts to bottom
      end try
      try
        set position of item "ClipStack.app" to {iAppX, iY}
        set position of item "应用程序" to {iAppsX, iY}
      end try
    end tell
  end tell
  delay 1
  update disk diskTitle without registering applications
  delay 1
end tell
APPLESCRIPT
then
  :
else
  echo "提示: Finder 未能设置 DMG 背景（可无图形会话，或需在「系统设置 → 隐私与安全性 → 自动化」允许 终端/Cursor 控制 Finder）。可本机再执行一次 ./package_dmg.sh。DMG 仍可安装。" >&2
fi

sync
sleep 1
hdiutil detach "$MNT" -quiet || hdiutil detach "$MNT" -force -quiet

trap - ERR
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"
rm -f "$RW"

echo ""
echo "DMG: $DMG"
echo "打开后将 ClipStack 拖入「应用程序」即可。"
echo "（未签名；若被 Gatekeeper 拦截：右键 App → 打开，或在隐私与安全性中允许。）"
