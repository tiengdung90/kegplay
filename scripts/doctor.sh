#!/bin/bash
# App gọi để khám các game đã cài (scripts/doctor.pl); in kết quả dạng TAB, xem đầu doctor.pl. Chỉ đọc, không sửa gì.
#   ./scripts/doctor.sh [--net]
set -uo pipefail
source "$(dirname "$0")/env.sh"
export KEGPLAY_DDRAW_APPIDS KEGPLAY_D3DC_FIXES
exec perl "$KEGPLAY_ROOT/scripts/doctor.pl" "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamapps" "$@" 2>/dev/null
