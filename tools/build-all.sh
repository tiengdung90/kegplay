#!/bin/bash
# Một lệnh dựng lại TẤT CẢ sau khi sửa bất cứ gì:   ./tools/build-all.sh [--install]
#   1. thư viện DNS dự phòng (chỉ khi mã nguồn mới hơn bản dựng sẵn)
#   2. tăng số build trong file BUILD (hiện trong app: "bản 0.1.0 (build N)")
#   3. bảng dịch → gói zip cộng đồng → Kegplay.app → .dmg        (tools/build-app.sh)
#   4. --install: thay /Applications/kegPlay.app bằng bản vừa dựng rồi mở lại (dữ liệu người dùng giữ nguyên)
# Đổi số phiên bản phát hành (0.1.0 → 0.2.0): sửa file VERSION bằng tay. Chi tiết: docs/PLAN.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f prebuilt/dnsfallback.dylib ] || [ src/dnsfallback/dnsfallback.c -nt prebuilt/dnsfallback.dylib ]; then
  ./tools/build-dnsfallback.sh
fi

N=$(( $(cat BUILD 2>/dev/null || echo 0) + 1 ))
echo "$N" > BUILD
echo "==> kegPlay $(cat VERSION) (build $N)"

./tools/build-app.sh

if [ "${1:-}" = "--install" ]; then
  pkill -if '/Applications/kegplay.app/Contents/MacOS/Kegplay' 2>/dev/null || true
  sleep 1
  rm -rf /Applications/kegPlay.app /Applications/Kegplay.app
  cp -R dist/kegPlay.app /Applications/
  open /Applications/kegPlay.app
  echo "==> Đã cài /Applications/kegPlay.app (build $N) và mở lại"
fi
