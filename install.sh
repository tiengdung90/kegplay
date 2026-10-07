#!/bin/bash
# Kegplay — cài đặt lần đầu. Dán vào Terminal:   bash ~/Downloads/Kegplay/install.sh
# Tải Wine (~190 MB), tạo "bottle" Windows, bật vượt chặn Steam Store, cài Steam bản Windows, chọn DXMT.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]:-$0}")"

echo ""
echo "  ┌──────────────────────────────────────────────┐"
echo "  │  KEGPLAY $(cat VERSION 2>/dev/null) — chơi game Windows trên Mac  │"
echo "  └──────────────────────────────────────────────┘"
echo ""

# File tải từ mạng bị macOS gắn cờ "quarantine" → bấm đúp .command sẽ bị chặn. Gỡ cờ cho thư mục này.
xattr -dr com.apple.quarantine . 2>/dev/null || true
chmod +x scripts/*.sh scripts/*.pl ./*.command engines/dxmt/build-winemac.sh 2>/dev/null || true

./scripts/setup.sh
./scripts/install-steam.sh
./scripts/use-engine.sh dxmt

echo ""
echo "  🎉 CÀI XONG. Từ giờ, trong thư mục Kegplay:"
echo "     • Bấm đúp  'Mở Steam - DXMT.command'   để mở Steam (đề xuất)"
echo "     • Bấm đúp  'Mở Steam - DXVK.command'   nếu game lỗi với DXMT"
echo "     • Bấm đúp  'Tắt Steam.command'         để tắt hẳn Steam + game"
echo ""
echo "  Lần đầu mở, Steam tự cập nhật vài trăm MB (2–5 phút) rồi hiện màn hình đăng nhập."
[ -f "$(dirname "$0")/README.md" ] && echo "  Xem thêm: README.md"
echo ""
