#!/bin/bash
# Dựng ntdll.so + wineserver của Wine 11.18 có msync → engines/msync/lib/ (scripts/graphics.sh chép vào runtime DXMT).
#
# Vì sao: Wine Gcenx 11.18 không có msync. msync (Mach semaphore, tác giả Marc-Aurel Zent / CodeWeavers) cho các
# nguyên hàm đồng bộ của Windows chạy ngay trong tiến trình game thay vì hỏi wineserver mỗi lần. Đo 2026-10-20
# (tools/diag/syncbench.c): event ×3,1, mutex ×11,7, semaphore ×8,6; wineserver lúc chơi Bannerlord ~16% → ~4% CPU.
# Nguồn: 5 file trong engines/msync/src/ lấy nguyên từ mã nguồn CrossOver 26.3 (LGPL, media.codeweavers.com,
# crossover-sources-26.3.0.tar.gz, sha256 ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872);
# port-msync.py nối chúng vào khung inproc_sync có sẵn của Wine 11.18 (CrossOver dựa trên Wine 11.0).
# Cần: cây Wine đã configure của engines/dxmt/build-winemac.sh (chạy nó trước), python3, Rosetta. ~1 phút.
# BẪY: ntdll.so và wineserver đổi giao thức (962 → 963) → luôn thay CẢ HAI cùng lúc, không bao giờ lẻ một file.
set -euo pipefail
source "$(dirname "$0")/../../scripts/env.sh"
HERE="$ENGINES_DIR/msync"
BASE="$ENGINES_DIR/dxmt/build/wine-$WINE_VERSION"
TREE="$ENGINES_DIR/dxmt/build/wine-$WINE_VERSION-msync"
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"

[ -f "$BASE/Makefile" ] || die "Chưa có cây Wine đã configure — chạy engines/dxmt/build-winemac.sh trước."
[ -d "$TREE" ] || { echo "==> Nhân cây mã Wine (APFS)"; cp -cR "$BASE" "$TREE"; }
python3 "$HERE/port-msync.py" "$HERE/src" "$TREE"
(cd "$TREE" && perl tools/make_requests >/dev/null)
echo "==> make ntdll.so + wineserver"
(cd "$TREE" && arch -x86_64 /bin/bash -c 'make -j8 server/wineserver dlls/ntdll/ntdll.so') > "$LOG_DIR/msync-make.log" 2>&1 \
  || die "build lỗi — xem $LOG_DIR/msync-make.log"
[ "$(nm "$TREE/server/wineserver" | grep -c msync_init)" -gt 0 ] || die "wineserver không có msync"   # grep -q + pipefail = SIGPIPE
mkdir -p "$HERE/lib"
cp "$TREE/dlls/ntdll/ntdll.so" "$TREE/server/wineserver" "$HERE/lib/"
echo "$WINE_FLAVOR-$WINE_VERSION" > "$HERE/lib/msync.wine"     # chỉ khớp đúng bản Wine này
echo "==> $HERE/lib/{ntdll.so,wineserver}"
