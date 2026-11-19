#!/bin/bash
# Cài Steam bản Windows vào bottle.
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine
[ -f "$WINEPREFIX/system.reg" ] || die "Bottle '$BOTTLE' does not exist. Run ./scripts/setup.sh first."

if [ -f "$STEAM_EXE_UNIX" ]; then
  echo "Steam is already installed in bottle '$BOTTLE'."
  exit 0
fi

setup_exe="$KEGPLAY_DATA/cache/SteamSetup.exe"
if [ ! -f "$setup_exe" ]; then
  echo "==> Downloading SteamSetup.exe"
  curl -fL --progress-bar -o "$setup_exe.part" \
    https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe
  mv "$setup_exe.part" "$setup_exe"
fi

echo "==> Installing Steam in silent mode"
wine "$setup_exe" /S >"$LOG_DIR/install-steam.log" 2>&1 || true
wineserver -w

[ -f "$STEAM_EXE_UNIX" ] || die "Steam installation failed. See $LOG_DIR/install-steam.log"
echo "==> Steam is installed. Run ./scripts/run-steam.sh or double-click 'Open Steam - DXMT.command'."
