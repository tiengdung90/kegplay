#!/bin/bash
# Tắt hết tiến trình Windows trong bottle (dùng khi Steam/game treo).
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine
echo "==> Tắt mọi tiến trình trong bottle '$BOTTLE'"
wineserver -k || true
unblock_stop
