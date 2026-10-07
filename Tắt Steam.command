#!/bin/bash
# Bấm đúp để tắt hẳn Steam Windows + mọi game trong bottle (dùng khi treo/đen màn hình, hoặc trước khi đổi công nghệ).
cd "$(dirname "$0")"
./scripts/stop.sh
sleep 1
osascript -e 'tell application "Terminal" to close (every window whose name contains "Tắt Steam")' >/dev/null 2>&1 &
exit 0
