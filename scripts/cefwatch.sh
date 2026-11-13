#!/bin/bash
# Canh wrapper CEF trong lúc Steam chạy (run-steam.sh tự mở script này chạy nền).
#
# Vì sao: run-steam.sh cài wrapper steamwebhelper.exe TRƯỚC khi mở Steam. Nhưng Steam hay tự tải bản cập nhật
# ngay lúc khởi động (hoặc khi người dùng bấm "Restart Steam" để cập nhật), ghi đè wrapper bằng bản gốc của Valve
# rồi tự mở lại → giao diện chạy KHÔNG qua wrapper → cửa sổ đen (xem src/cefwrap/cefwrap.c).
#
# Script này, mỗi vài giây, khi bottle còn chạy:
#   1. steamwebhelper.exe bị thay bằng bản thật (>1 MB) và đã ghi xong → cefwrap.sh cài lại wrapper.
#   2. Có tiến trình "steamwebhelper.exe --type=…" (chỉ xuất hiện khi CEF chạy không qua wrapper; bản qua wrapper
#      chạy --single-process và tên là steamwebhelper_orig.exe) → tắt Steam và mở lại một lần.
# Tự thoát khi Steam/bottle tắt. Không tự mở lại quá 1 lần trong 5 phút (tránh vòng lặp nếu wrapper hỏng).
# Tắt hẳn tính năng: KEGPLAY_CEFWATCH=0.
set -uo pipefail
source "$(dirname "$0")/env.sh"

PIDFILE="$KEGPLAY_DATA/runtime/cefwatch.pid"
STAMP="$KEGPLAY_DATA/runtime/cefwatch.last-restart"
HELPER="$WINEPREFIX/drive_c/Program Files (x86)/Steam/bin/cef/cef.win64/steamwebhelper.exe"
mkdir -p "$KEGPLAY_DATA/runtime"
echo $$ > "$PIDFILE"
say() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
cleanup() { [ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$PIDFILE"; }
trap cleanup EXIT

# Tiến trình CEF chạy KHÔNG qua wrapper (của bottle này: dòng lệnh Windows có đường dẫn Steam)
# (mẫu viết \. để chính lệnh grep — cũng hiện trong ps — không tự khớp)
unwrapped_cef() { ps -axo command= 2>/dev/null | grep -q 'steamwebhelper\.exe --type='; }
helper_is_real() { [ -f "$HELPER" ] && [ "$(stat -f%z "$HELPER")" -gt 1000000 ]; }
# Steam ghi xong file chưa: thời điểm đổi (ctime) đã yên ≥ 10 giây
helper_settled() { [ $(( $(date +%s) - $(stat -f%c "$HELPER") )) -ge 10 ]; }

say "Bắt đầu canh wrapper CEF (pid $$)"
sleep 10                                          # chờ Steam kịp khởi động
while bottle_running; do
  if helper_is_real && helper_settled; then
    say "Steam đã ghi đè wrapper (vừa cập nhật) → cài lại"
    "$KEGPLAY_ROOT/scripts/cefwrap.sh" || say "cefwrap.sh lỗi"
  fi
  if unwrapped_cef && ! helper_is_real; then
    last="$(cat "$STAMP" 2>/dev/null || echo 0)"
    if [ $(( $(date +%s) - last )) -lt 300 ]; then
      say "Giao diện Steam vẫn chạy không qua wrapper sau lần mở lại trước — không mở lại nữa"
      exit 1
    fi
    date +%s > "$STAMP"
    say "Giao diện Steam đang chạy không qua wrapper (sẽ đen) → tắt Steam và mở lại"
    sleep 5                                       # để Steam ghi nốt cấu hình/đăng nhập sau khi cập nhật
    wineserver -k 2>/dev/null || true
    wait_wine_idle
    rm -f "$PIDFILE"
    exec "$KEGPLAY_ROOT/scripts/run-steam.sh"     # run-steam.sh mở một bản canh mới
  fi
  sleep 3
done
say "Steam đã tắt — thôi canh"
