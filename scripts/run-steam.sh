#!/bin/bash
# Mở Steam bản Windows trong bottle.
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine
overlay_off
apply_game_fixes
[ -f "$STEAM_EXE_UNIX" ] || die "Chưa cài Steam. Chạy ./scripts/install-steam.sh trước."

# Bottle đang dùng PAC riêng của kegPlay → bật máy chủ PAC trước khi Steam chạy
if [ -f "$WINEPREFIX/.kegplay_pac" ]; then unblock_start; fi

if bottle_running && WINEDEBUG=-all wine tasklist 2>/dev/null | grep -qi '^steam\.exe'; then
  echo "Steam Windows đang chạy rồi. Treo/đen màn hình thì: ./scripts/stop.sh rồi mở lại."
  exit 0
fi

# Mỗi tài khoản chỉ 1 phiên: Steam Mac đăng nhập sẽ đá Steam Windows ra ("Session Replaced"
# → NO CONNECTION, cài game báo "No internet connection") và Steam Windows không tự nối lại.
if pgrep -x steam_osx >/dev/null; then
  echo "CẢNH BÁO: Steam bản Mac đang chạy — sẽ tranh phiên đăng nhập với Steam Windows."
  echo "          Thoát Steam Mac (Cmd+Q) trước, hoặc tắt 'Run Steam when my computer starts'."
fi

# LẦN ĐẦU sau khi cài: SteamSetup chỉ đặt trình khởi động (Steam.exe); phần lõi (steamui.dll, CEF…) do Steam
# tự tải ở lần chạy đầu. Cờ -noverifyfiles làm Steam BỎ QUA bước tải đó → "Failed to load steamui.dll".
# → Chạy 1 lượt KHÔNG có -noverifyfiles cho Steam tự tải (nó hiện cửa sổ "Updating Steam…"), chờ tới khi
#   giao diện bắt đầu lên (steamwebhelper chạy), tắt, rồi mới cài wrapper và mở bình thường ở dưới.
STEAM_DIR="$(dirname "$STEAM_EXE_UNIX")"
HELPER_REAL="$STEAM_DIR/bin/cef/cef.win64/steamwebhelper.exe"
if [ ! -f "$STEAM_DIR/steamui.dll" ] || [ ! -f "$HELPER_REAL" ]; then
  echo "==> Lần đầu: Steam tải phần lõi (vài trăm MB) — chờ 2–5 phút, đừng tắt cửa sổ 'Updating Steam'."
  "${WINE_NOHUP[@]}" wine "$STEAM_EXE_UNIX" -cef-disable-gpu -cef-disable-sandbox >"$LOG_DIR/steam-bootstrap.log" 2>&1 &
  ok=0
  for i in $(seq 1 240); do                                   # tối đa 20 phút
    sleep 5
    if [ -f "$STEAM_DIR/steamui.dll" ] && [ -f "$HELPER_REAL" ] \
       && WINEDEBUG=-all wine tasklist 2>/dev/null | grep -qi '^steamwebhelper'; then ok=1; break; fi
    if ! bottle_running; then break; fi                       # Steam tự thoát (lỗi mạng / người dùng bấm Cancel)
    [ $((i % 3)) = 0 ] && echo "    Đang tải lõi Steam… $(du -sh "$STEAM_DIR" 2>/dev/null | cut -f1)"
  done
  wineserver -k 2>/dev/null || true
  wait_wine_idle
  if [ "$ok" != 1 ] && { [ ! -f "$STEAM_DIR/steamui.dll" ] || [ ! -f "$HELPER_REAL" ]; }; then
    die "Steam chưa tải xong phần lõi (mạng chậm/bị ngắt?). Bấm mở lại để tiếp tục. Log: $LOG_DIR/steam-bootstrap.log"
  fi
  echo "==> Steam đã tải xong phần lõi."
fi

# Màn hình đen: cờ -cef-* của Steam KHÔNG đủ → wrapper steamwebhelper.exe chèn
# --disable-gpu --single-process (xem src/cefwrap/cefwrap.c). Cài lại mỗi lần mở vì
# Steam cập nhật sẽ ghi đè; -noverifyfiles để Steam không tự khôi phục bản gốc.
if [ "${KEGPLAY_CEFWRAP:-1}" = "1" ]; then
  "$KEGPLAY_ROOT/scripts/cefwrap.sh"
fi
# Khoá singleton của Chromium sót lại từ lần tắt đột ngột sẽ chặn webhelper khởi động
find "$WINEPREFIX/drive_c/users" -path '*Steam/htmlcache*' -name 'Singleton*' -delete 2>/dev/null || true

# Thêm cờ riêng: STEAM_ARGS="-silent" ./scripts/run-steam.sh
STEAM_FLAGS=(-noverifyfiles -cef-disable-gpu -cef-disable-gpu-compositing -cef-disable-sandbox)

log="$LOG_DIR/steam-$(date +%Y%m%d-%H%M%S).log"
echo "==> Mở Steam (bottle '$BOTTLE'), log: $log"
# shellcheck disable=SC2086
"${WINE_NOHUP[@]}" wine "$STEAM_EXE_UNIX" "${STEAM_FLAGS[@]}" ${STEAM_ARGS:-} >"$log" 2>&1 &
echo "    PID wine: $!"
