#!/bin/bash
# Sửa game DirectDraw cũ (Red Alert 2, Tiberian Sun…) báo "Unable to set the video mode", chớp hoặc đen:
#     ./scripts/fix-ddraw-game.sh <appid>            cài cnc-ddraw vào thư mục game
#     ./scripts/fix-ddraw-game.sh <appid> --undo     trả file gốc của game (và không tự cài lại nữa)
#     ./scripts/fix-ddraw-game.sh <appid> --auto     như cài, nhưng im lặng nếu đã cài hoặc người dùng đã hoàn tác
# Người dùng KHÔNG phải gọi script này: run-steam.sh và launch-game.sh gọi --auto cho các game đã biết
# (KEGPLAY_DDRAW_APPIDS trong env.sh). Bản thường và --undo là cho người phát triển thử game mới.
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
OPTOUT="$WINEPREFIX/.kegplay_noddraw_$appid"      # người dùng đã bấm Hoàn tác → đừng tự cài lại
mode="${2:-}"
if [ "$mode" = "--auto" ]; then
  [ -f "$OPTOUT" ] && exit 0
  # đã cài rồi (Steam chưa ghi đè) → bỏ qua phần cài, nhưng VẪN chạy bước 4: file .INI của game có thể chỉ xuất hiện
  # sau lần chạy đầu tiên, khi đó mới đặt được độ phân giải
  cmp -s "$GAME/ddraw.dll" "$CNC_DIR/ddraw.dll" 2>/dev/null && installed=1
fi
installed="${installed:-}"

exes() { ls "$GAME" | grep -i '\.exe$' || true; }

if [ "$mode" = "--undo" ]; then
  [ -d "$BACKUP" ] || die "Không có bản sao lưu ở $BACKUP"
  rm -f "$GAME/ddraw.dll" "$GAME/ddraw.ini"
  cp "$BACKUP"/* "$GAME/" 2>/dev/null || true
  exes | while read -r exe; do
    wine reg delete "HKCU\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides" /v ddraw /f >/dev/null 2>&1 || true
  done
: > "$OPTOUT"
  echo "==> Đã trả file gốc cho '$dir'."
  exit 0
fi

if [ -z "$installed" ]; then
rm -f "$OPTOUT"
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
  # Riêng Yuri (gamemd.exe): menu LUÔN là 800x600 và game cộng vị trí cửa sổ trên màn hình vào vị trí các ô con
  # (nút, ô chọn Win32), nên chỉ khớp khi cửa sổ nằm sát góc trên trái. Chạy cửa sổ không viền ở (0,0), không
  # phóng to, không đổi chế độ màn hình Mac: menu là cửa sổ 800x600, vào trận cửa sổ nở kín màn hình, thoát thì co lại.
  # Còn lệch: macOS đẩy cửa sổ xuống dưới thanh menu (34 điểm) nên hàng ô chọn ở Skirmish thấp hơn 34 điểm, vẫn bấm được.
  # Đã thử và HỎNG (đo bằng tools/diag winprobe): boxing (hình giữa, nút ở góc); nonexclusive toàn màn hình (thoát trận
  # màn hình về 960x600 mà cửa sổ vẫn 1728 → hình bự, không bấm được); không viền kín màn hình + fixchilds=1 (thoát trận bị phóng to).
  s{(\[gamemd\]\r?\n)(.*?)(?=\r?\n\r?\n|\r?\n;|\r?\n\[)}{
     my ($h, $b) = ($1, $2); my $nl = $h =~ /\r\n/ ? "\r\n" : "\n";
     my @kv = (nonexclusive=>"true", maintas=>"false", boxing=>"false", fullscreen=>"false", windowed=>"true", fixchilds=>0,
               border=>"false", posX=>0, posY=>0, center_window=>0);
     while (my ($k, $v) = splice(@kv, 0, 2)) { $b =~ s/^\Q$k\E=.*$/$k=$v/m or $b .= "$nl$k=$v" }
     $h . $b }se;
' "$CNC_DIR/ddraw.ini" > "$GAME/ddraw.ini"

# 3. bảo Wine dùng ddraw.dll trong thư mục game cho các file chạy của game này
exes | while read -r exe; do
  wine reg add "HKCU\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides" /v ddraw /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1
done
overlay_off
fi

# 4. riêng Red Alert 2 / Yuri's Revenge (2 file cấu hình riêng: RA2.INI và RA2MD.INI):
#    - cho phép độ phân giải cao, tắt bộ đệm phụ;
#    - đặt độ phân giải game = màn hình Mac, để người dùng khỏi phải tự chọn trong Options. Lý do: menu của game là
#      nút Win32 con, chỉ nằm đúng chỗ khi KHÔNG phóng to; ở cỡ bằng màn hình thì menu nằm giữa, vào trận kín màn hình.
#      Ở cỡ nhỏ (vd 1024x768) bản Yuri còn mất luôn ô chọn độ phân giải trong Options.
#      Chỉ đổi khi game đang ở các cỡ mặc định/nhỏ hoặc LỚN HƠN màn hình — người dùng đã tự chọn cỡ vừa màn hình thì giữ nguyên.
if [ "$appid" = "2229850" ]; then
  screen="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var f=$.NSScreen.mainScreen.frame; Math.round(f.size.width)+"x"+Math.round(f.size.height)' 2>/dev/null || true)"
  sw="${screen%x*}"; sh="${screen#*x}"
  case "$sw$sh" in ''|*[!0-9]*) sw=""; sh="";; esac
  for ini in RA2.INI RA2MD.INI; do
    [ -f "$GAME/$ini" ] || continue
    KP_W="$sw" KP_H="$sh" perl -0pi -e '
      for my $kv (["AllowHiResModes","yes"],["VideoBackBuffer","no"]) {
        my ($k,$v) = @$kv;
        s/^\Q$k\E=.*$/$k=$v/mi or s/^(\[Video\][^\n]*\n)/$1$k=$v\r\n/mi;
      }
      if ($ENV{KP_W} && $ENV{KP_H}) {
        my ($cur) = /^ScreenWidth=(\d+)/mi;
        my ($curh) = /^ScreenHeight=(\d+)/mi;
        # cỡ lớn hơn màn hình (game liệt kê cả các chế độ Retina, vd 2992x1934) thì cửa sổ tràn ra ngoài, chỉ thấy một góc
        if (!defined $cur || $cur <= 1024 || $cur > $ENV{KP_W} || ($curh // 0) > $ENV{KP_H}) {
          for my $kv (["ScreenWidth",$ENV{KP_W}],["ScreenHeight",$ENV{KP_H}]) {
            my ($k,$v) = @$kv;
            s/^\Q$k\E=.*$/$k=$v/mi or s/^(\[Video\][^\n]*\n)/$1$k=$v\r\n/mi;
          }
        }
      }' "$GAME/$ini"
  done
fi

[ -n "$installed" ] && exit 0
echo "==> Đã cài cnc-ddraw cho '$dir'. Mở game từ Steam."
echo "    Trả về như cũ: $0 $appid --undo"
