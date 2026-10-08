# Biến môi trường chung — các script khác `source` file này.
# Chọn bottle khác: BOTTLE=ten ./scripts/run-steam.sh

KEGPLAY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# KEGPLAY_ROOT = thư mục MÃ (scripts, engines, prebuilt) — có thể nằm trong Kegplay.app (chỉ đọc).
# KEGPLAY_DATA = thư mục DỮ LIỆU (Wine tải về, bottle, game, cache, log). Chạy script trực tiếp: trùng ROOT.
#   App đặt KEGPLAY_DATA="$HOME/Library/Application Support/Kegplay" để cập nhật app không mất game.
KEGPLAY_DATA="${KEGPLAY_DATA:-$KEGPLAY_ROOT}"
mkdir -p "$KEGPLAY_DATA"

WINE_VERSION="${WINE_VERSION:-11.18}"
WINE_FLAVOR="${WINE_FLAVOR:-devel}"            # devel = Wine gốc, khớp mã nguồn để build winemac.so cho DXMT
WINE_TARBALL="wine-${WINE_FLAVOR}-${WINE_VERSION}-osx64.tar.xz"
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_VERSION}/${WINE_TARBALL}"

# Hai runtime Wine (cùng version):
#   WINE_BASE = Wine gốc Gcenx, KHÔNG BAO GIỜ sửa — dùng cho DXVK, WineD3D, setup, build
#   WINE_DXMT = bản nhân APFS của WINE_BASE + DXMT + winemac.so cầu nối (graphics.sh dxmt dựng)
# Đổi công nghệ = trỏ runtime khác, không chép đè file vào Wine → không thể hỏng giữa chừng.
WINE_BASE="$KEGPLAY_DATA/runtime/wine-${WINE_FLAVOR}-${WINE_VERSION}"
WINE_DXMT="$KEGPLAY_DATA/runtime/wine-dxmt-${WINE_VERSION}"
ENGINES_DIR="$KEGPLAY_ROOT/engines"
DXMT_VER="${DXMT_VER:-v0.80}"
# Dấu của runtime DXMT = phiên bản DXMT + mã băm winemac.so đã cài; lệch dấu = runtime cũ, cần dựng lại
dxmt_stamp_want() { echo "$DXMT_VER $(shasum "$ENGINES_DIR/dxmt/lib/winemac.so" 2>/dev/null | cut -c1-16)"; }
dxmt_runtime_fresh() { [ -x "$WINE_DXMT/bin/wine" ] && [ "$(cat "$WINE_DXMT/.kegplay-dxmt" 2>/dev/null)" = "$(dxmt_stamp_want)" ]; }

BOTTLE="${BOTTLE:-steam}"
export WINEPREFIX="$KEGPLAY_DATA/bottles/$BOTTLE"

# Công nghệ đồ hoạ của bottle ghi ở <bottle>/.kegplay_engine (dxmt|dxvk|wined3d) → chọn runtime tương ứng
bottle_engine() { cat "$WINEPREFIX/.kegplay_engine" 2>/dev/null || echo "?"; }
KEGPLAY_ENGINE="${KEGPLAY_ENGINE:-$(bottle_engine)}"
if [ "$KEGPLAY_ENGINE" = dxmt ] && [ -x "$WINE_DXMT/bin/wine" ]; then
  WINE_HOME="$WINE_DXMT"
else
  WINE_HOME="$WINE_BASE"
fi
WINE_BIN="$WINE_HOME/bin"
export PATH="$WINE_BIN:$PATH"

# msync (đồng bộ bằng Mach semaphore của CrossOver/Whisky): KIỂM 2026-09-29 — ntdll.so của Gcenx 11.18
# (cả Devel lẫn Staging) KHÔNG có msync/esync/fsync → biến này vô tác dụng, giữ để dùng nếu đổi sang Wine có msync.
export WINEMSYNC="${WINEMSYNC:-1}"
# Giảm log rác; debug thì chạy: WINEDEBUG=+err ./scripts/run.sh ...
export WINEDEBUG="${WINEDEBUG:--all}"

# DNS dự phòng: DNS một số nhà mạng VN trả "không tồn tại" cho cmp*.steamserver.net (máy chủ đăng nhập Steam)
# → không đăng nhập được, mã QR không hiện. Steam Windows tự phân giải tên, KHÔNG đi qua PAC/proxy, và Wine
# không đọc file hosts → chen getaddrinfo: chỉ khi DNS máy báo không có tên mới hỏi lại 1.1.1.1 / 8.8.8.8.
# Mã: src/dnsfallback/. Tắt: KEGPLAY_DNS_FALLBACK=0
KEGPLAY_DNS_LIB="$KEGPLAY_ROOT/prebuilt/dnsfallback.dylib"
if [ "${KEGPLAY_DNS_FALLBACK:-1}" != "0" ] && [ -f "$KEGPLAY_DNS_LIB" ]; then
  export DYLD_INSERT_LIBRARIES="$KEGPLAY_DNS_LIB${DYLD_INSERT_LIBRARIES:+:$DYLD_INSERT_LIBRARIES}"
fi
# BẪY: nohup là file hệ thống được SIP bảo vệ → macOS xoá mọi biến DYLD_* khi chạy nó, Steam sẽ mất DNS dự phòng.
# Chạy nền Wine thì dùng:  "${WINE_NOHUP[@]}" wine ...   (env đặt lại biến SAU nohup)
WINE_NOHUP=(nohup /usr/bin/env "DYLD_INSERT_LIBRARIES=${DYLD_INSERT_LIBRARIES:-}")
# MoltenVK in 1 cảnh báo "VkDescriptorPool exhausted" MỖI KHUNG HÌNH khi chơi game DXVK
# → log Steam phình 5 GB/giờ (đã gặp với Kingdom Come). 1 = chỉ lỗi.
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}"
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-warn}"
# Cấu hình DXVK (async shader); DXVK là DLL Windows nên cần đường dẫn dạng Z:\...
if [ -f "$ENGINES_DIR/dxvk/dxvk.conf" ]; then
  export DXVK_CONFIG_FILE="Z:$(echo "$ENGINES_DIR/dxvk/dxvk.conf" | tr '/' '\\')"
fi

# ---------- Vượt chặn Steam Store (nhà mạng VN chặn store.steampowered.com theo SNI) ----------
# kegPlay tự mang SpoofDPI (github.com/xvzc/SpoofDPI): tải bản dựng sẵn vào runtime/spoofdpi/, chạy ở cổng
# riêng khi mở Steam, tắt khi stop.sh. Nó cắt nhỏ gói TLS ClientHello để thiết bị chặn không đọc được tên miền.
# KHÔNG đụng proxy hệ thống của máy (auto-configure-network mặc định tắt); chỉ bottle Wine dùng, qua PAC.
KEGPLAY_DPI_VER="${KEGPLAY_DPI_VER:-1.5.3}"
KEGPLAY_DPI_PORT="${KEGPLAY_DPI_PORT:-18090}"
KEGPLAY_DPI_BIN="$KEGPLAY_DATA/runtime/spoofdpi/spoofdpi"
dpi_install() {
  [ -x "$KEGPLAY_DPI_BIN" ] && return 0
  local arch sha name url tgz
  case "$(uname -m)" in
    arm64) arch=darwin_arm64;  sha=4226058c15516f071e5d4495ab7bf6da14c6ead4a16c4c7bc96dd1a720aad295 ;;
    *)     arch=darwin_x86_64; sha=f8404fe1e40821589bfec24f261861c35f45d49241eafabd80c6536411857abd ;;
  esac
  name="spoofdpi_${KEGPLAY_DPI_VER}_${arch}.tar.gz"
  url="https://github.com/xvzc/SpoofDPI/releases/download/v${KEGPLAY_DPI_VER}/$name"
  tgz="$KEGPLAY_DATA/cache/$name"
  mkdir -p "$KEGPLAY_DATA/cache" "$KEGPLAY_DATA/runtime/spoofdpi"
  if [ ! -f "$tgz" ]; then
    echo "==> Tải SpoofDPI $KEGPLAY_DPI_VER ($arch)"
    curl -fL --progress-bar -o "$tgz.part" "$url" && mv "$tgz.part" "$tgz" || { echo "CẢNH BÁO: không tải được SpoofDPI"; return 1; }
  fi
  # mã băm chỉ ghim cho bản mặc định; đổi KEGPLAY_DPI_VER thì tự chịu trách nhiệm kiểm tra
  if [ "$KEGPLAY_DPI_VER" = "1.5.3" ] && [ "$(shasum -a 256 "$tgz" | cut -d' ' -f1)" != "$sha" ]; then
    echo "CẢNH BÁO: SpoofDPI tải về SAI mã băm — bỏ, không cài."; rm -f "$tgz"; return 1
  fi
  tar -xzf "$tgz" -C "$KEGPLAY_DATA/runtime/spoofdpi" && chmod +x "$KEGPLAY_DPI_BIN" \
    && xattr -dr com.apple.quarantine "$KEGPLAY_DATA/runtime/spoofdpi" 2>/dev/null
  [ -x "$KEGPLAY_DPI_BIN" ] || { echo "CẢNH BÁO: giải nén SpoofDPI không ra file chạy"; return 1; }
}
dpi_start() {
  nc -z 127.0.0.1 "$KEGPLAY_DPI_PORT" 2>/dev/null && return 0
  dpi_install || return 0
  # tham số đã kiểm chứng vượt được chặn (VN, 2026-09/10): cắt ClientHello mỗi 5 byte, DNS qua HTTPS
  nohup "$KEGPLAY_DPI_BIN" --no-tui --listen-addr "127.0.0.1:$KEGPLAY_DPI_PORT" \
    --dns-mode https --dns-https-url https://cloudflare-dns.com/dns-query \
    --https-split-mode chunk --https-chunk-size 5 --log-level warn \
    >"$KEGPLAY_DATA/logs/spoofdpi.log" 2>&1 &
  local _; for _ in 1 2 3 4 5 6 7 8; do nc -z 127.0.0.1 "$KEGPLAY_DPI_PORT" 2>/dev/null && return 0; sleep 0.5; done
  echo "CẢNH BÁO: SpoofDPI không lên ở cổng $KEGPLAY_DPI_PORT (xem logs/spoofdpi.log) — Store có thể không vào được."
}
# Tắt tiến trình có dòng lệnh CHỨA ĐÚNG chuỗi cho trước (so chuỗi cố định, không phải regex — đường dẫn có thể
# chứa dấu cách, ngoặc…). Chỉ tắt tiến trình của CHÍNH bản kegPlay này (theo đường dẫn dữ liệu), không đụng
# bản kegPlay khác đang chạy trên cùng máy/cùng cổng.
kill_own() {
  local pid
  for pid in $(ps -axo pid=,command= | grep -F -- "$1" | grep -v "grep -F" | awk '{print $1}'); do
    kill "$pid" 2>/dev/null || true
  done
}
dpi_stop() { kill_own "$KEGPLAY_DPI_BIN --no-tui"; }

# PAC: mẫu scripts/pac/kegplay.pac → runtime/pac/kegplay.pac (điền cổng SpoofDPI), phục vụ qua HTTP cho Wine
KEGPLAY_PAC_PORT="${KEGPLAY_PAC_PORT:-18082}"
KEGPLAY_PAC_URL="http://127.0.0.1:$KEGPLAY_PAC_PORT/kegplay.pac"
pac_server_stop() {
  kill_own "pacserver.pl $KEGPLAY_PAC_PORT $KEGPLAY_DATA/runtime/pac/kegplay.pac"
  kill_own "http.server $KEGPLAY_PAC_PORT --bind 127.0.0.1 --directory $KEGPLAY_DATA/runtime/pac"   # bản Python cũ
}
pac_server_start() {
  mkdir -p "$KEGPLAY_DATA/runtime/pac"
  sed "s/__DPI_PORT__/$KEGPLAY_DPI_PORT/" "$KEGPLAY_ROOT/scripts/pac/kegplay.pac" > "$KEGPLAY_DATA/runtime/pac/kegplay.pac"
  # đang chạy VÀ phục vụ đúng file vừa sinh → xong; chạy mà lệch (máy chủ cũ, thư mục khác) → bật lại
  if [ "$(curl -fs -m 2 "$KEGPLAY_PAC_URL" 2>/dev/null)" = "$(cat "$KEGPLAY_DATA/runtime/pac/kegplay.pac")" ]; then return 0; fi
  pac_server_stop; sleep 0.5
  nohup perl "$KEGPLAY_ROOT/scripts/pacserver.pl" "$KEGPLAY_PAC_PORT" "$KEGPLAY_DATA/runtime/pac/kegplay.pac" \
    >/dev/null 2>&1 &
  local _; for _ in 1 2 3 4 5 6; do curl -fs -m 1 -o /dev/null "$KEGPLAY_PAC_URL" && return 0; sleep 0.5; done
  echo "CẢNH BÁO: không bật được máy chủ PAC ở cổng $KEGPLAY_PAC_PORT — Store có thể không vào được."
}
# Bật/tắt cả bộ vượt chặn (SpoofDPI + máy chủ PAC)
unblock_start() { dpi_start; pac_server_start; }
unblock_stop()  { pac_server_stop; dpi_stop; }

LOG_DIR="$KEGPLAY_DATA/logs"
mkdir -p "$LOG_DIR"

STEAM_EXE_WIN='C:\Program Files (x86)\Steam\steam.exe'
STEAM_EXE_UNIX="$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe"

die() { echo "LỖI: $*" >&2; exit 1; }
# Steam Overlay (GameOverlayRenderer*.dll) bị Steam chèn vào mọi game. Dưới Wine nó hay phá: KCD mất phím di chuyển,
# Red Alert 2 + cnc-ddraw văng ngay lúc mở (2026-10-08). Chặn nạp 2 thư viện đó cho cả bottle; làm 1 lần, đánh dấu bằng file.
overlay_off() {
  [ -f "$WINEPREFIX/.kegplay_nooverlay" ] && return 0
  [ -d "$WINEPREFIX" ] || return 0
  for d in gameoverlayrenderer gameoverlayrenderer64; do
    wine reg add 'HKCU\Software\Wine\DllOverrides' /v "$d" /t REG_SZ /d "" /f >/dev/null 2>&1 || return 0
  done
  : > "$WINEPREFIX/.kegplay_nooverlay"
}

need_wine() { [ -x "$WINE_BASE/bin/wine" ] || die "Chưa có Wine. Chạy ./scripts/setup.sh trước."; }

# Wine của BOTTLE NÀY có đang chạy không (không xét bottle/bản kegPlay khác trên máy).
bottle_running() { [ -x "$WINE_BASE/bin/wineserver" ] && "$WINE_BASE/bin/wineserver" -k0 2>/dev/null; }
# Có chương trình Windows của NGƯỜI DÙNG (Steam, game…) đang chạy trong bottle này? Bỏ qua dịch vụ hệ thống
# của Wine (services/winedevice/plugplay… chạy kèm mọi lệnh wine rồi tắt theo wineserver).
user_exe_running() {
  bottle_running || return 1
  WINEDEBUG=-all wine tasklist 2>/dev/null | tr -d '\r' | awk 'NR>3 && NF {print tolower($1)}' \
    | grep -vqE '^(services|winedevice|plugplay|svchost|explorer|rpcss|lsass|start|tasklist|conhost|wineboot|winemenubuilder|system)(\.exe)?$'
}
# Chờ wineserver của bottle còn nán lại (~3 giây sau lệnh wine cuối) tự tắt; quá 6 giây thì tắt hẳn.
wait_wine_idle() {
  local _
  for _ in $(seq 1 12); do bottle_running || return 0; sleep 0.5; done
  wineserver -k 2>/dev/null || true
}

# Cho phép chuyển thư mục kegPlay đi đâu cũng được: mọi đường dẫn trong script đều tính từ
# KEGPLAY_ROOT; riêng registry của bottle có vài đường dẫn tuyệt đối do Wine ghi (font runtime)
# → nhớ gốc cũ trong <bottle>/.kegplay_root, thấy khác thì sửa (chỉ khi Wine đang tắt).
kegplay_relocate() {
  local marker="$WINEPREFIX/.kegplay_root" old
  [ -f "$WINEPREFIX/system.reg" ] || return 0
  if [ ! -f "$marker" ]; then echo "$KEGPLAY_DATA" > "$marker"; return 0; fi
  old="$(cat "$marker")"
  [ "$old" = "$KEGPLAY_DATA" ] && return 0
  if bottle_running; then
    echo "LƯU Ý: kegPlay đã bị chuyển chỗ nhưng Wine đang chạy — tắt hẳn (./scripts/stop.sh) rồi mở lại để tự sửa đường dẫn."
    return 0
  fi
  perl "$KEGPLAY_ROOT/scripts/relocate.pl" "$WINEPREFIX" "$old" "$KEGPLAY_DATA" \
    && echo "$KEGPLAY_DATA" > "$marker"
}
kegplay_relocate
