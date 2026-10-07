#!/bin/bash
# Chọn công nghệ đồ hoạ cho bottle trước khi mở Steam:  ./scripts/use-engine.sh dxmt|dxvk
# Đang đúng công nghệ → không làm gì. Khác → đổi (graphics.sh), nhưng CHỈ khi không có Steam/game đang chạy:
# không tự tắt để khỏi mất tiến trình chơi.
set -euo pipefail
source "$(dirname "$0")/env.sh"
want="${1:?Dùng: $0 dxmt|dxvk}"
case "$want" in dxmt|dxvk) ;; *) die "Công nghệ không hợp lệ: $want (dxmt|dxvk)";; esac

cur="$(bottle_engine)"
if [ "$cur" = "$want" ] && { [ "$want" != dxmt ] || dxmt_runtime_fresh; }; then
  echo "==> Công nghệ đồ hoạ: $want (đang dùng sẵn)"
  exit 0
fi
if user_exe_running; then
  if [ "$cur" = "$want" ]; then
    echo "==> Steam/game đang chạy bằng $want rồi (có bản cập nhật runtime chờ áp dụng ở lần mở sau khi tắt Steam)."
    exit 0
  fi
  echo "Steam/game đang chạy bằng $cur. Bấm đúp 'Tắt Steam.command' rồi mở lại bằng $want."
  exit 1
fi
wait_wine_idle
if [ "$want" = dxmt ] && [ ! -f "$ENGINES_DIR/dxmt/lib/winemac.so" ]; then
  echo "==> Chưa có winemac.so cho DXMT — build (~1 phút)"
  "$ENGINES_DIR/dxmt/build-winemac.sh"
fi
"$KEGPLAY_ROOT/scripts/graphics.sh" "$want"
