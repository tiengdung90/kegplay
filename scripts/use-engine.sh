#!/bin/bash
# Chọn công nghệ đồ hoạ cho bottle trước khi mở Steam:  ./scripts/use-engine.sh dxmt|dxvk
# Đang đúng công nghệ → không làm gì. Khác → đổi (graphics.sh), nhưng CHỈ khi không có Steam/game đang chạy:
# không tự tắt để khỏi mất tiến trình chơi.
set -euo pipefail
source "$(dirname "$0")/env.sh"
want="${1:?Usage: $0 dxmt|dxvk}"
case "$want" in dxmt|dxvk) ;; *) die "Unknown graphics engine: $want (expected dxmt or dxvk)";; esac

cur="$(bottle_engine)"
if [ "$cur" = "$want" ] && { [ "$want" != dxmt ] || dxmt_runtime_fresh; }; then
  echo "==> Graphics engine: $want (already selected)"
  exit 0
fi
if user_exe_running; then
  if [ "$cur" = "$want" ]; then
    echo "==> Steam or a game is already using $want. The pending runtime update will apply after you quit and reopen Steam."
    exit 0
  fi
  echo "Steam or a game is using $cur. Double-click 'Close Steam.command', then reopen with $want."
  exit 1
fi
wait_wine_idle
if [ "$want" = dxmt ] && [ ! -f "$ENGINES_DIR/dxmt/lib/winemac.so" ]; then
  echo "==> Building the missing DXMT winemac.so (about one minute)"
  "$ENGINES_DIR/dxmt/build-winemac.sh"
fi
"$KEGPLAY_ROOT/scripts/graphics.sh" "$want"
