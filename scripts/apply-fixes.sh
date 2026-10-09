#!/bin/bash
# App kegPlay gọi khi thấy một game VỪA TẢI XONG trong lúc Steam đang mở:  ./scripts/apply-fixes.sh <appid>
# run-steam.sh chỉ sửa các game đã có sẵn lúc mở Steam; không có bước này thì người dùng mới tải game cổ xong,
# bấm Play ngay trong Steam sẽ gặp lỗi hiển thị ở lần đầu. Game không nằm trong danh sách cần sửa → không làm gì.
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine
appid="${1:?Dùng: $0 <appid>}"
case "$appid" in *[!0-9]*) die "AppID phải là số: $appid";; esac
apply_game_fixes "$appid"
