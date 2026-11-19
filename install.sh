#!/bin/bash
# kegPlay — cài đặt lần đầu. Dán vào Terminal:   bash ~/Downloads/Kegplay/install.sh
# Tải Wine (~190 MB), tạo "bottle" Windows, bật vượt chặn Steam Store, cài Steam bản Windows, chọn DXMT.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]:-$0}")"

echo ""
echo "  ┌──────────────────────────────────────────────┐"
echo "  │  KEGPLAY $(cat VERSION 2>/dev/null) — play Windows games on Mac  │"
echo "  └──────────────────────────────────────────────┘"
echo ""

# File tải từ mạng bị macOS gắn cờ "quarantine" → bấm đúp .command sẽ bị chặn. Gỡ cờ cho thư mục này.
xattr -dr com.apple.quarantine . 2>/dev/null || true
chmod +x scripts/*.sh scripts/*.pl ./*.command engines/dxmt/build-winemac.sh 2>/dev/null || true

./scripts/setup.sh
./scripts/install-steam.sh
./scripts/use-engine.sh dxmt

echo ""
echo "  🎉 Setup complete. In the kegPlay folder:"
echo "     • Double-click 'Open Steam - DXMT.command' to open Steam (recommended)."
echo "     • Double-click 'Open Steam - DXVK.command' if a game has trouble with DXMT."
echo "     • Double-click 'Close Steam.command' to quit Steam and its games."
echo ""
echo "  On first launch, Steam downloads a few hundred MB (2–5 minutes), then shows the sign-in screen."
[ -f "$(dirname "$0")/README.md" ] && echo "  See also: README.md"
echo ""
