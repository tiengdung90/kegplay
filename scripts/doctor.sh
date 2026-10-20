#!/bin/bash
# App gọi để khám các game đã cài (scripts/doctor.pl); in kết quả dạng TAB, xem đầu doctor.pl. Chỉ đọc, không sửa gì.
#   ./scripts/doctor.sh [--net]
set -uo pipefail
source "$(dirname "$0")/env.sh"
export KEGPLAY_DDRAW_APPIDS
# game đã được đặt dùng trình biên dịch shader của chính nó (dấu do apply_game_fixes ghi)
KEGPLAY_D3DC_FIXES="$(ls "$WINEPREFIX"/.kegplay_d3dc_* 2>/dev/null | sed 's#.*_##' | tr '\n' ' ')"; export KEGPLAY_D3DC_FIXES
[ "${1:-}" = "--log" ] && exec perl "$KEGPLAY_ROOT/scripts/doctor.pl" "$@" 2>/dev/null   # --log <file> [offset]
exec perl "$KEGPLAY_ROOT/scripts/doctor.pl" "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamapps" "$@" 2>/dev/null
