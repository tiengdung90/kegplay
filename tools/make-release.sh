#!/bin/bash
# Đóng gói bản phát hành cộng đồng:  ./tools/make-release.sh   →  dist/Kegplay-<version>.zip
# CHỈ lấy script + mã nguồn + tài liệu + 2 file dựng sẵn. KHÔNG BAO GIỜ lấy bottles/ (tài khoản Steam + game),
# runtime/ cache/ logs/ (trình cài tự tải), engines/*/dist (tải lại), engines/dxmt/build (mã nguồn Wine).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VER="$(cat VERSION)"
OUT="$ROOT/dist"
STAGE="$(mktemp -d)/Kegplay"
mkdir -p "$STAGE" "$OUT"

# 2 file dựng sẵn phải có và khớp mã nguồn
[ -f prebuilt/cefwrap.exe ] || { echo "LỖI: thiếu prebuilt/cefwrap.exe"; exit 1; }
[ src/cefwrap/cefwrap.c -nt prebuilt/cefwrap.exe ] && { echo "LỖI: cefwrap.c mới hơn bản dựng sẵn — build lại prebuilt/cefwrap.exe"; exit 1; }
[ -f prebuilt/dnsfallback.dylib ] || { echo "LỖI: thiếu prebuilt/dnsfallback.dylib — chạy tools/build-dnsfallback.sh"; exit 1; }
[ src/dnsfallback/dnsfallback.c -nt prebuilt/dnsfallback.dylib ] && { echo "LỖI: dnsfallback.c mới hơn bản dựng sẵn — chạy tools/build-dnsfallback.sh"; exit 1; }
[ -f engines/dxmt/lib/winemac.so ] && [ -f engines/dxmt/lib/winemac.so.wine ] || { echo "LỖI: thiếu engines/dxmt/lib/winemac.so(.wine) — chạy engines/dxmt/build-winemac.sh"; exit 1; }
nm -gU engines/dxmt/lib/winemac.so | grep -q " _macdrv_functions$" || { echo "LỖI: winemac.so không xuất macdrv_functions"; exit 1; }
for f in engines/dxmt/bridge/*; do [ "$f" -nt engines/dxmt/lib/winemac.so ] && { echo "LỖI: $f mới hơn winemac.so — build lại"; exit 1; }; done

cp LICENSE THIRD-PARTY-NOTICES.txt VERSION install.sh "$STAGE/"
# tài liệu .md nằm trong docs/ và không lên GitHub → bản clone từ GitHub không có; có thì kèm vào gói
[ -f docs/README.md ] && cp docs/README.md "$STAGE/"
[ -f docs/CREDITS.md ] && cp docs/CREDITS.md "$STAGE/"
cp ./*.command "$STAGE/"
mkdir -p "$STAGE/scripts/pac" "$STAGE/src" "$STAGE/prebuilt" "$STAGE/docs" "$STAGE/engines/dxmt/lib" "$STAGE/engines/dxmt/bridge" "$STAGE/engines/dxvk"
cp scripts/*.sh scripts/*.pl scripts/*.js "$STAGE/scripts/"
cp scripts/pac/kegplay.pac "$STAGE/scripts/pac/"
cp -R src/cefwrap src/d3d11bench src/dnsfallback "$STAGE/src/"
rm -f "$STAGE"/src/d3d11bench/*.exe
cp prebuilt/cefwrap.exe "$STAGE/prebuilt/"
cp prebuilt/dnsfallback.dylib "$STAGE/prebuilt/"
for f in docs/*.md; do case "$(basename "$f")" in README.md|CREDITS.md|PLAN.md) ;; *) [ -f "$f" ] && cp "$f" "$STAGE/docs/";; esac; done
cp engines/dxmt/build-winemac.sh "$STAGE/engines/dxmt/"
cp engines/dxmt/bridge/* "$STAGE/engines/dxmt/bridge/"
cp engines/dxmt/lib/winemac.so engines/dxmt/lib/winemac.so.wine "$STAGE/engines/dxmt/lib/"
cp engines/dxvk/dxvk.conf "$STAGE/engines/dxvk/"
find "$STAGE" -name '.DS_Store' -delete
chmod +x "$STAGE"/install.sh "$STAGE"/*.command "$STAGE"/scripts/*.sh "$STAGE"/scripts/*.pl "$STAGE"/engines/dxmt/build-winemac.sh

# --- tự kiểm trước khi nén ---
fail=0
for bad in bottles runtime cache logs dist archive; do [ -e "$STAGE/$bad" ] && { echo "LỖI: gói chứa $bad/"; fail=1; }; done
# thông tin riêng của máy/tài khoản người đóng gói
me="$(id -un)"
if grep -rIl -e "/Users/$me" -e "$me" "$STAGE" >/dev/null 2>&1; then
  echo "LỖI: file sau chứa tên/đường dẫn người dùng '$me':"; grep -rIl -e "/Users/$me" -e "$me" "$STAGE" | sed "s|$STAGE/|   |"; fail=1
fi
[ $fail = 0 ] || { echo "==> DỪNG, không tạo gói."; exit 1; }

ZIP="$OUT/Kegplay-$VER.zip"
rm -f "$ZIP"
( cd "$(dirname "$STAGE")" && zip -q -r -X "$ZIP" Kegplay )
rm -rf "$(dirname "$STAGE")"
echo "==> $ZIP  ($(du -h "$ZIP" | cut -f1), $(unzip -l "$ZIP" | tail -1 | awk '{print $2}') file)"
