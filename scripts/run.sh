#!/bin/bash
# Chạy 1 file .exe bất kỳ trong bottle.
#   ./scripts/run.sh "/đường/dẫn/mac/game.exe"
#   ./scripts/run.sh 'C:\Program Files (x86)\Steam\steamapps\common\Game\game.exe'
#   ./scripts/run.sh winecfg        (công cụ có sẵn của Wine: winecfg, regedit, taskmgr, explorer)
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine
[ $# -ge 1 ] || die "Cần tham số: đường dẫn .exe"

exe="$1"; shift
# Chạy từ thư mục của game — nhiều game tìm file dữ liệu theo thư mục hiện tại
if [ -f "$exe" ]; then cd "$(dirname "$exe")"; fi

log="$LOG_DIR/run-$(date +%Y%m%d-%H%M%S).log"
echo "==> Chạy $exe (bottle '$BOTTLE'), log: $log"
wine "$exe" "$@" >"$log" 2>&1
