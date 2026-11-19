#!/bin/bash
# Build winemac.so của Wine (cùng version với runtime) có thêm cầu nối DXMT (engines/dxmt/bridge/).
# Kết quả: engines/dxmt/lib/winemac.so — scripts/graphics.sh dxmt sẽ chép vào runtime.
#
# Vì sao: DXMT dlsym "macdrv_functions" (bảng hàm kiểu CrossOver); Wine gốc ẩn symbol + đổi layout
# macdrv_win_data. Cầu nối xuất đúng 1 symbol, trả struct đúng layout DXMT. Chi tiết: docs/RESEARCH.md §3 (tài liệu nội bộ).
# Cần: Homebrew bison + flex (bison macOS 2.3 quá cũ), mingw-w64, Rosetta. Build ~1 phút (M2 Pro).
set -euo pipefail
source "$(dirname "$0")/../../scripts/env.sh"
HERE="$ENGINES_DIR/dxmt"

[ "$WINE_FLAVOR" = "devel" ] || die "This build requires Wine devel and its matching upstream source. Current flavor: $WINE_FLAVOR"
SRC_TAR="$KEGPLAY_DATA/cache/wine-$WINE_VERSION.tar.xz"
BUILD="$HERE/build/wine-$WINE_VERSION"
OUT="$HERE/lib/winemac.so"
MAC="$BUILD/dlls/winemac.drv"
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"

command -v x86_64-w64-mingw32-gcc >/dev/null || die "mingw-w64 is missing. Run: brew install mingw-w64"
[ -x /opt/homebrew/opt/bison/bin/bison ] || die "A newer bison is required. Run: brew install bison flex"

if [ ! -d "$BUILD" ]; then
  [ -f "$SRC_TAR" ] || curl -fL --progress-bar -o "$SRC_TAR" \
    "https://dl.winehq.org/wine/source/${WINE_VERSION%%.*}.x/wine-$WINE_VERSION.tar.xz"
  mkdir -p "$HERE/build" && tar -xJf "$SRC_TAR" -C "$HERE/build"
fi

# chép cầu nối + thêm vào SOURCES (idempotent)
cp "$HERE/bridge/dxmt_export.c" "$HERE/bridge/dxmt_view.m" "$MAC/"
grep -q dxmt_export "$MAC/Makefile.in" || \
  sed -i '' 's/^\tdisplay\.c \\$/\tdisplay.c \\\n\tdxmt_export.c \\\n\tdxmt_view.m \\/' "$MAC/Makefile.in"

# 3 bản vá OpenGL của Kegplay (giải thích trong bridge/patch-opengl.pl)
perl "$HERE/bridge/patch-opengl.pl" "$MAC/opengl.c" || die "Could not patch opengl.c. Has the Wine source changed?"

cd "$BUILD"
if [ ! -f Makefile ]; then
  echo "==> configure (x86_64 qua Rosetta)"
  arch -x86_64 /bin/bash -c './configure --enable-archs=x86_64 --disable-tests --without-x --without-freetype \
    --without-gnutls --without-gstreamer --without-sdl --without-usb --without-v4l2 --without-pcap --without-cups \
    --without-sane --without-gphoto --without-krb5 --without-netapi --without-pulse --without-oss --without-dbus \
    --without-capi --without-wayland --without-inotify --without-udev \
    CC="clang -arch x86_64" OBJC="clang -arch x86_64"' > "$LOG_DIR/wine-configure.log" 2>&1
else
  arch -x86_64 /bin/bash -c './config.status' >/dev/null 2>&1
fi
echo "==> make winemac.so"
arch -x86_64 /bin/bash -c 'make -j8 dlls/winemac.drv/winemac.so' > "$LOG_DIR/wine-make.log" 2>&1 \
  || die "Build failed. See $LOG_DIR/wine-make.log"
nm -gU "$MAC/winemac.so" | grep -q " _macdrv_functions$" || die "winemac.so does not export macdrv_functions"
mkdir -p "$(dirname "$OUT")" && cp "$MAC/winemac.so" "$OUT"
echo "$WINE_FLAVOR-$WINE_VERSION" > "$OUT.wine"      # winemac.so chỉ khớp đúng bản Wine này
echo "==> $OUT (exports macdrv_functions ✓)"
# runtime DXMT (bản nhân) đang chứa winemac.so cũ → xoá để lần bật DXMT sau tự dựng lại với bản mới
if [ -d "$WINE_DXMT" ]; then
  user_exe_running && die "Steam or a game is running. Quit it and retry to update the DXMT runtime."
  wait_wine_idle; rm -rf "$WINE_DXMT"
  echo "==> Removed the old DXMT runtime. Open 'Open Steam - DXMT' or run use-engine.sh dxmt to rebuild it."
fi
