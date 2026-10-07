#!/bin/bash
# Bấm đúp trong Finder: mở Steam bản Windows với công nghệ đồ hoạ DXVK.
cd "$(dirname "$0")"
[ -x runtime/wine-devel-*/bin/wine ] 2>/dev/null || ./scripts/setup.sh
./scripts/install-steam.sh
if ./scripts/use-engine.sh dxvk; then
  ./scripts/run-steam.sh
  sleep 6
else
  sleep 12
fi
osascript -e 'tell application "Terminal" to close (every window whose name contains "Open Steam - DXVK")' >/dev/null 2>&1 &
exit 0
