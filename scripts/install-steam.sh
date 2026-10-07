#!/bin/bash
# Cài Steam bản Windows vào bottle.
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine
[ -f "$WINEPREFIX/system.reg" ] || die "Chưa có bottle '$BOTTLE'. Chạy ./scripts/setup.sh trước."

if [ -f "$STEAM_EXE_UNIX" ]; then
  echo "Steam đã cài trong bottle '$BOTTLE'."
  exit 0
fi

setup_exe="$KEGPLAY_DATA/cache/SteamSetup.exe"
if [ ! -f "$setup_exe" ]; then
  echo "==> Tải SteamSetup.exe"
  curl -fL --progress-bar -o "$setup_exe.part" \
    https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe
  mv "$setup_exe.part" "$setup_exe"
fi

echo "==> Cài Steam (chế độ im lặng)"
wine "$setup_exe" /S >"$LOG_DIR/install-steam.log" 2>&1 || true
wineserver -w

[ -f "$STEAM_EXE_UNIX" ] || die "Cài Steam thất bại, xem $LOG_DIR/install-steam.log"
echo "==> Đã cài Steam. Mở bằng: ./scripts/run-steam.sh  (hoặc bấm đúp 'Open Steam - DXMT.command')"
