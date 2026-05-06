#!/usr/bin/env bash
# 从 AppIcon-1024.png 生成 AppIcon.icns（需 Xcode 命令行自带的 sips / iconutil）
# 源图若非正方形，先按最短边居中裁切为正方形，避免 sips -z 把长宽比硬拉成正方形导致图标变形。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/AppIcon-1024.png"
OUT="$ROOT/AppIcon.icns"
SET="$ROOT/AppIcon.iconset"

if [[ ! -f "$SRC" ]]; then
  echo "缺少 $SRC，跳过后端 .icns 生成"
  exit 0
fi

rm -rf "$SET"
mkdir -p "$SET"

W=$(sips -g pixelWidth "$SRC" 2>/dev/null | awk '/pixelWidth/ {print $2}')
H=$(sips -g pixelHeight "$SRC" 2>/dev/null | awk '/pixelHeight/ {print $2}')
SQUARE=$(mktemp "${TMPDIR:-/tmp}/AppIcon-square.XXXXXX.png")
cleanup_sq() { rm -f "$SQUARE"; }
trap cleanup_sq EXIT

if [[ -z "${W:-}" || -z "${H:-}" ]]; then
  echo "无法读取 $SRC 尺寸，直接使用原图"
  cp "$SRC" "$SQUARE"
elif [[ "$W" == "$H" ]]; then
  cp "$SRC" "$SQUARE"
else
  SIDE=$W
  if (( H < W )); then SIDE=$H; fi
  sips -c "$SIDE" "$SIDE" "$SRC" --out "$SQUARE"
fi

SRC="$SQUARE"

sips -z 16 16     "$SRC" --out "$SET/icon_16x16.png"
sips -z 32 32     "$SRC" --out "$SET/icon_16x16@2x.png"
sips -z 32 32     "$SRC" --out "$SET/icon_32x32.png"
sips -z 64 64     "$SRC" --out "$SET/icon_32x32@2x.png"
sips -z 128 128   "$SRC" --out "$SET/icon_128x128.png"
sips -z 256 256   "$SRC" --out "$SET/icon_128x128@2x.png"
sips -z 256 256   "$SRC" --out "$SET/icon_256x256.png"
sips -z 512 512   "$SRC" --out "$SET/icon_256x256@2x.png"
sips -z 512 512   "$SRC" --out "$SET/icon_512x512.png"
sips -z 1024 1024 "$SRC" --out "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o "$OUT"
rm -rf "$SET"
trap - EXIT
rm -f "$SQUARE"
echo "已生成 $OUT"
