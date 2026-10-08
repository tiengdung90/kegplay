#!/bin/bash
# Sửa game DirectDraw cũ (Red Alert 2, Tiberian Sun…) báo "Unable to set the video mode", chớp hoặc đen:
#     ./scripts/fix-ddraw-game.sh <appid>            cài cnc-ddraw vào thư mục game
#     ./scripts/fix-ddraw-game.sh <appid> --undo     trả file gốc của game
#
# Vì sao: các game này xin 640x480/800x600 toàn màn hình, màn hình Mac không có chế độ đó, và DirectDraw của Wine
# trên Mac vẽ hỏng (chớp/đen). cnc-ddraw (github.com/FunkyFr3sh/cnc-ddraw, MIT) vẽ game vào một cửa sổ thường.
# Cấu hình đã thử chạy được: cửa sổ thường (không phóng to), OpenGL, KHÔNG dời nút con của menu (fixchilds=0) —
# bật phóng to hoặc để fixchilds mặc định thì menu lệch và chớp trắng. Trong game chọn độ phân giải bằng màn hình.
# Cần Steam Overlay tắt (overlay_off trong env.sh), không thì game văng lúc mở qua Steam.
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine
appid="${1:?Dùng: $0 <appid> [--undo]}"
case "$appid" in *[!0-9]*) die "AppID phải là số: $appid";; esac

CNC_VER="v7.1.0.0"
CNC_SHA="0b13ab89a64c9918189b1dadd449ef6ed3cb3b7b19cabd96d8adbd95505bb908"
CNC_DIR="$KEGPLAY_DATA/runtime/dist/cnc-ddraw/$CNC_VER"
APPS="$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamapps"
manifest="$APPS/appmanifest_$appid.acf"
[ -f "$manifest" ] || die "Chưa cài game có AppID $appid trong Steam của kegPlay."
dir="$(sed -n 's/^[[:space:]]*"installdir"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$manifest" | tr -d '\r' | head -1)"
GAME="$APPS/common/$dir"
[ -d "$GAME" ] || die "Không thấy thư mục game: $GAME"
BACKUP="$KEGPLAY_DATA/backups/ddraw-$appid"
user_exe_running && [ -n "$(WINEDEBUG=-all wine tasklist 2>/dev/null | tr -d '\r' | grep -i "$(ls "$GAME" | grep -i '\.exe$' | head -1)" || true)" ] \
  && die "Game đang chạy — thoát game rồi chạy lại."

exes() { ls "$GAME" | grep -i '\.exe$' || true; }

if [ "${2:-}" = "--undo" ]; then
  [ -d "$BACKUP" ] || die "Không có bản sao lưu ở $BACKUP"
  rm -f "$GAME/ddraw.dll" "$GAME/ddraw.ini"
  cp "$BACKUP"/* "$GAME/" 2>/dev/null || true
  exes | while read -r exe; do
    wine reg delete "HKCU\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides" /v ddraw /f >/dev/null 2>&1 || true
  done
  echo "==> Đã trả file gốc cho '$dir'."
  exit 0
fi

# 1. tải cnc-ddraw (ghim phiên bản + SHA-256)
if [ ! -f "$CNC_DIR/ddraw.dll" ]; then
  mkdir -p "$CNC_DIR"
  zip="$CNC_DIR/cnc-ddraw.zip"
  echo "==> Tải cnc-ddraw $CNC_VER"
  curl -fL --progress-bar -o "$zip" "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/$CNC_VER/cnc-ddraw.zip"
  got="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
  [ "$got" = "$CNC_SHA" ] || { rm -f "$zip"; die "File cnc-ddraw tải về không khớp mã kiểm (SHA-256) — dừng."; }
  unzip -q -o "$zip" -d "$CNC_DIR"
fi

# 2. sao lưu file gốc của game (1 lần), rồi chép cnc-ddraw vào
if [ ! -d "$BACKUP" ]; then
  mkdir -p "$BACKUP"
  for f in ddraw.dll ddraw.ini DDrawCompat.ini; do [ -f "$GAME/$f" ] && cp "$GAME/$f" "$BACKUP/"; done
fi
cp "$CNC_DIR/ddraw.dll" "$GAME/ddraw.dll"
cp -R "$CNC_DIR/Shaders" "$GAME/" 2>/dev/null || true
# cấu hình: chỉ sửa mục [ddraw] của file mẫu (các mục riêng từng game phía dưới giữ nguyên)
perl -0pe '
  my %set = (width=>0, height=>0, fullscreen=>"false", windowed=>"true", renderer=>"opengl",
             shader=>"Bilinear", fixchilds=>0, savesettings=>0);
  s{(\[ddraw\].*?)(?=\n\[)}{ my $s = $1; for my $k (keys %set) { $s =~ s/^\Q$k\E=.*$/$k=$set{$k}/m } $s }se;
' "$CNC_DIR/ddraw.ini" > "$GAME/ddraw.ini"

# 3. bảo Wine dùng ddraw.dll trong thư mục game cho các file chạy của game này
exes | while read -r exe; do
  wine reg add "HKCU\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides" /v ddraw /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1
done
overlay_off

# 4. riêng Red Alert 2 / Yuri: cho phép độ phân giải cao, tắt bộ đệm phụ
if [ "$appid" = "2229850" ]; then
  for ini in RA2.INI RA2MD.INI; do
    [ -f "$GAME/$ini" ] || continue
    perl -0pi -e '
      for my $kv (["AllowHiResModes","yes"],["VideoBackBuffer","no"]) {
        my ($k,$v) = @$kv;
        s/^\Q$k\E=.*$/$k=$v/mi or s/^(\[Video\][^\n]*\n)/$1$k=$v\r\n/mi;
      }' "$GAME/$ini"
  done
fi

echo "==> Đã cài cnc-ddraw cho '$dir'. Mở game từ Steam."
echo "    Trong Options của game, chọn độ phân giải bằng màn hình của bạn (vd 1728 x 1117)."
echo "    Trả về như cũ: $0 $appid --undo"
