#!/bin/bash
# Mở thẳng 1 game Steam theo AppID (app kegPlay gọi khi bấm "Chơi"):  ./scripts/launch-game.sh <appid>
# Steam chưa chạy → mở Steam kèm -applaunch. Steam đang chạy → gọi steam.exe -applaunch, Steam chuyển lệnh
# cho phiên đang chạy. Steam vẫn phải chạy ngầm (game cần nó để kiểm bản quyền).
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine
appid="${1:?Dùng: $0 <appid>}"
case "$appid" in *[!0-9]*) die "AppID phải là số: $appid";; esac
[ -f "$STEAM_EXE_UNIX" ] || die "Chưa cài Steam."
apply_game_fixes "$appid"

if bottle_running && WINEDEBUG=-all wine tasklist 2>/dev/null | grep -qi '^steam\.exe'; then
  echo "==> Steam đang chạy — yêu cầu mở game $appid"
  "${WINE_NOHUP[@]}" wine "$STEAM_EXE_UNIX" -applaunch "$appid" >>"$LOG_DIR/launch-game.log" 2>&1 &
else
  STEAM_ARGS="-applaunch $appid" "$KEGPLAY_ROOT/scripts/run-steam.sh"
fi
