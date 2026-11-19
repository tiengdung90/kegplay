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
[ -f prebuilt/cefwrap.exe ] || { echo "ERROR: Missing prebuilt/cefwrap.exe"; exit 1; }
[ src/cefwrap/cefwrap.c -nt prebuilt/cefwrap.exe ] && { echo "ERROR: cefwrap.c is newer than the prebuilt executable. Rebuild prebuilt/cefwrap.exe."; exit 1; }
[ -f prebuilt/dnsfallback.dylib ] || { echo "ERROR: Missing prebuilt/dnsfallback.dylib. Run tools/build-dnsfallback.sh."; exit 1; }
[ src/dnsfallback/dnsfallback.c -nt prebuilt/dnsfallback.dylib ] && { echo "ERROR: dnsfallback.c is newer than the prebuilt library. Run tools/build-dnsfallback.sh."; exit 1; }
[ -f engines/dxmt/lib/winemac.so ] && [ -f engines/dxmt/lib/winemac.so.wine ] || { echo "ERROR: Missing winemac.so or its .wine file in engines/dxmt/lib. Run engines/dxmt/build-winemac.sh."; exit 1; }
nm -gU engines/dxmt/lib/winemac.so | grep -q " _macdrv_functions$" || { echo "ERROR: winemac.so does not export macdrv_functions"; exit 1; }
for f in engines/msync/port-msync.py engines/msync/src/*/*; do [ "$f" -nt engines/msync/lib/ntdll.so ] && { echo "ERROR: $f is newer than the msync build. Run engines/msync/build-msync.sh."; exit 1; }; done
for f in engines/dxmt/bridge/*; do [ "$f" -nt engines/dxmt/lib/winemac.so ] && { echo "ERROR: $f is newer than winemac.so. Rebuild the driver."; exit 1; }; done

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
mkdir -p "$STAGE/engines/msync/lib"
cp -R engines/msync/src engines/msync/build-msync.sh engines/msync/port-msync.py "$STAGE/engines/msync/"
cp engines/msync/lib/ntdll.so engines/msync/lib/wineserver engines/msync/lib/msync.wine "$STAGE/engines/msync/lib/"
find "$STAGE" -name '.DS_Store' -delete
chmod +x "$STAGE"/install.sh "$STAGE"/*.command "$STAGE"/scripts/*.sh "$STAGE"/scripts/*.pl "$STAGE"/engines/dxmt/build-winemac.sh

# --- tự kiểm trước khi nén ---
fail=0
for bad in bottles runtime cache logs dist archive; do [ -e "$STAGE/$bad" ] && { echo "ERROR: Package contains $bad/"; fail=1; }; done
# thông tin riêng của máy/tài khoản người đóng gói
me="$(id -un)"
if grep -rIl -e "/Users/$me" -e "$me" "$STAGE" >/dev/null 2>&1; then
  echo "ERROR: The following files contain the username or home path for '$me':"; grep -rIl -e "/Users/$me" -e "$me" "$STAGE" | sed "s|$STAGE/|   |"; fail=1
fi
[ $fail = 0 ] || { echo "==> Packaging stopped."; exit 1; }

ZIP="$OUT/Kegplay-$VER.zip"
rm -f "$ZIP"
( cd "$(dirname "$STAGE")" && zip -q -r -X "$ZIP" Kegplay )
rm -rf "$(dirname "$STAGE")"
echo "==> $ZIP  ($(du -h "$ZIP" | cut -f1), $(unzip -l "$ZIP" | tail -1 | awk '{print $2}') files)"
