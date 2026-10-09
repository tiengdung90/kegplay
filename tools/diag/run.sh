#!/bin/bash
# Công cụ chẩn đoán cho người phát triển (không đóng gói cho người dùng). Cần mingw-w64 (brew install mingw-w64).
#   tools/diag/run.sh enumwin ["chuỗi trong tiêu đề"]          liệt kê cửa sổ + cửa sổ con của game ngay lúc này
#   tools/diag/run.sh winprobe "<tiêu đề>" "<chữ nút>" [giây]   ghi số liệu mỗi giây trong lúc người dùng thao tác
#   tools/diag/run.sh trace <thư mục game> <exe> <kênh> [giây]   chạy exe với WINEDEBUG=<kênh>, in đường dẫn file log
#   swift tools/diag/macwindows.swift                           cửa sổ Wine + chế độ màn hình phía macOS
# Dữ liệu: đặt KEGPLAY_DATA trỏ tới thư mục dữ liệu của app (mặc định ~/Library/Application Support/Kegplay).
# LƯU Ý: game toàn màn hình bị thu nhỏ khi người dùng chuyển cửa sổ → số đo lúc đó vô nghĩa; dùng winprobe.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export KEGPLAY_DATA="${KEGPLAY_DATA:-$HOME/Library/Application Support/Kegplay}"
source "$HERE/../../scripts/env.sh"
need_wine
OUT="$KEGPLAY_DATA/cache/diag"; mkdir -p "$OUT"
build() { # <tên>
  local exe="$OUT/$1.exe"
  if [ ! -f "$exe" ] || [ "$HERE/$1.c" -nt "$exe" ]; then
    command -v x86_64-w64-mingw32-gcc >/dev/null || die "Thiếu mingw-w64: brew install mingw-w64"
    x86_64-w64-mingw32-gcc -O1 -o "$exe" "$HERE/$1.c" -luser32
  fi
  cp "$exe" "$WINEPREFIX/drive_c/$1.exe"
}
cmd="${1:?Dùng: $0 enumwin|winprobe|trace …}"; shift
case "$cmd" in
  enumwin)  build enumwin;  wine 'C:\enumwin.exe' "$@" 2>/dev/null | tr -d '\r' ;;
  winprobe) build winprobe; wine 'C:\winprobe.exe' "$@" >/dev/null 2>&1
            tr -d '\r' < "$WINEPREFIX/drive_c/winprobe.txt" ;;
  trace)    dir="${1:?thư mục game}"; exe="${2:?exe}"; ch="${3:?kênh, vd +ddraw,+wgl}"; secs="${4:-30}"
            log="$OUT/trace-$(date +%H%M%S).log"; cd "$dir"
            WINEDEBUG="$ch" wine "$exe" >"$log" 2>&1 & pid=$!
            sleep "$secs"; kill "$pid" 2>/dev/null || true
            echo "$log ($(wc -l < "$log") dòng)" ;;
  *) die "Lệnh không rõ: $cmd" ;;
esac
