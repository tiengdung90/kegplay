#!/bin/bash
# Kingdom Come: Deliverance — chuyển từ toàn màn hình độc quyền sang cửa sổ.
# Dưới Wine trên Mac, fullscreen độc quyền làm game mất/nhận focus liên tục (log: swapchain dựng
# lại 11 lần) → bàn phím (WASD) không vào game. Chạy khi game ĐÃ TẮT (game ghi đè file lúc thoát).
set -euo pipefail
source "$(dirname "$0")/env.sh"

ATTR="$WINEPREFIX/drive_c/users/$USER/Saved Games/kingdomcome/profiles/default/attributes.xml"
[ -f "$ATTR" ] || die "$ATTR is missing. Launch the game once first."
if pgrep -f KingdomCome.exe >/dev/null; then die "The game is running. Quit it and try again."; fi

cp "$ATTR" "$ATTR.bak"
sed -i '' 's|<Attr name="res_fs" value="1" />|<Attr name="res_fs" value="0" />|' "$ATTR"
grep -q '<Attr name="res_fs" value="0" />' "$ATTR" && echo "==> KCD: switched to windowed mode (backup: attributes.xml.bak)"
