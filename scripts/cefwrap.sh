#!/bin/bash
# Build + cài wrapper steamwebhelper.exe (sửa màn hình đen của Steam). Xem src/cefwrap/cefwrap.c.
#   ./scripts/cefwrap.sh          build (nếu cần) + cài vào bottle
#   ./scripts/cefwrap.sh remove   trả bản gốc
# run-steam.sh gọi script này mỗi lần mở, vì Steam cập nhật sẽ ghi đè wrapper.
set -euo pipefail
source "$(dirname "$0")/env.sh"

SRC="$KEGPLAY_ROOT/src/cefwrap/cefwrap.c"
PRE="$KEGPLAY_ROOT/prebuilt/cefwrap.exe"      # bản dựng sẵn kèm gói phát hành (máy người dùng không có mingw)
BIN="$KEGPLAY_DATA/runtime/cefwrap.exe"       # bản tự build khi sửa mã nguồn
CEF_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64"
HELPER="$CEF_DIR/steamwebhelper.exe"
ORIG="$CEF_DIR/steamwebhelper_orig.exe"

if [ "${1:-}" = "remove" ]; then
  [ -f "$ORIG" ] && mv -f "$ORIG" "$HELPER" && echo "==> Đã trả steamwebhelper.exe gốc"
  exit 0
fi

# Ưu tiên bản dựng sẵn; chỉ build khi không có nó hoặc mã nguồn mới hơn (người phát triển sửa cefwrap.c)
if [ -f "$PRE" ] && ! [ "$SRC" -nt "$PRE" ]; then
  BIN="$PRE"
elif [ ! -f "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
  command -v x86_64-w64-mingw32-gcc >/dev/null || die "Thiếu prebuilt/cefwrap.exe và không có trình biên dịch (brew install mingw-w64)"
  x86_64-w64-mingw32-gcc -O2 -s -municode -mwindows -o "$BIN" "$SRC"
  echo "==> Đã build $BIN"
fi

[ -f "$HELPER" ] || { echo "Chưa có steamwebhelper.exe (Steam chưa cập nhật lần đầu) — bỏ qua"; exit 0; }

if cmp -s "$BIN" "$HELPER"; then
  exit 0                                    # wrapper đang đúng chỗ
fi
# steamwebhelper.exe khác wrapper hiện tại. Phân biệt bằng kích thước: wrapper ~20 KB, bản thật của Steam ~7 MB.
# Nếu là WRAPPER CŨ (bản build khác) thì chỉ thay, TUYỆT ĐỐI không cất làm _orig — nếu không wrapper sẽ gọi
# chính wrapper thành vòng lặp vô tận.
if [ "$(stat -f%z "$HELPER")" -gt 1000000 ]; then
  mv -f "$HELPER" "$ORIG"                   # bản thật (mới cài hoặc Steam vừa cập nhật) → cất làm _orig
elif [ ! -f "$ORIG" ]; then
  die "steamwebhelper.exe là wrapper nhưng thiếu steamwebhelper_orig.exe — chạy Steam › Verify hoặc cài lại Steam."
fi
cp "$BIN" "$HELPER"
echo "==> Đã cài wrapper CEF (--disable-gpu --single-process)"
