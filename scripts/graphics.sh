#!/bin/bash
# Chọn lớp đồ hoạ DirectX cho bottle (thường gọi qua scripts/use-engine.sh).
#   ./scripts/graphics.sh dxmt      D3D10/11 → DXMT → Metal (thẳng, không qua Vulkan)
#   ./scripts/graphics.sh dxvk      D3D10/11 → DXVK-macOS 1.10.3 → Vulkan → MoltenVK → Metal
#   ./scripts/graphics.sh wined3d   mặc định của Wine (chỉ đủ cho DX9 trở xuống trên Mac)
#   ./scripts/graphics.sh status
# Đo 2026-09-28/29 (M2 Pro, d3d11bench): WineD3D KHÔNG tạo nổi device D3D11 (OpenGL macOS kẹt 4.1);
# DXVK FL 11_0; DXMT FL 11_1 (cần winemac.so build riêng — engines/dxmt/build-winemac.sh).
#
# Hai runtime (xem env.sh): DXMT bản "builtin" phải nằm TRONG Wine (thay d3d11/dxgi/d3d10core builtin, KHÔNG
# override native,builtin) → cài vào bản nhân APFS WINE_DXMT; WINE_BASE giữ nguyên gốc cho DXVK/WineD3D
# (DXVK dùng dxgi gốc của Wine). Công nghệ của bottle ghi ở <bottle>/.kegplay_engine → env.sh chọn runtime.
set -euo pipefail
source "$(dirname "$0")/env.sh"
need_wine

DXVK_DIR="$KEGPLAY_DATA/runtime/dist/dxvk"         # DXVK tải về (dữ liệu, không nằm trong mã)
DXVK_TAR="$KEGPLAY_DATA/cache/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz"
DXVK_URL="https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz"
DXMT_DIR="$KEGPLAY_DATA/runtime/dist/dxmt/$DXMT_VER"
DXMT_TAR="$KEGPLAY_DATA/cache/dxmt-$DXMT_VER-builtin.tar.gz"
DXMT_URL="https://github.com/3Shain/dxmt/releases/download/$DXMT_VER/dxmt-$DXMT_VER-builtin.tar.gz"
WINEMAC_DXMT="$ENGINES_DIR/dxmt/lib/winemac.so"     # từ engines/dxmt/build-winemac.sh
DXMT_STAMP="$WINE_DXMT/.kegplay-dxmt"                # DXMT_VER + mã băm winemac.so đã cài
SYS64="$WINEPREFIX/drive_c/windows/system32"
SYS32="$WINEPREFIX/drive_c/windows/syswow64"
REG='HKCU\Software\Wine'

reg_set() { wine reg add "$1" /v "$2" /t "$3" /d "$4" /f >/dev/null 2>&1; }
reg_del() { wine reg delete "$1" /v "$2" /f >/dev/null 2>&1 || true; }

use_runtime() {      # $1 = thư mục runtime; mọi lệnh wine sau đó chạy bằng runtime này
  WINE_HOME="$1"; WINE_BIN="$1/bin"; export PATH="$WINE_BIN:$PATH"
}

build_dxmt_runtime() {  # WINE_DXMT = bản nhân APFS của WINE_BASE + DXMT; dựng lại khi DXMT/winemac đổi
  local want lib
  want="$(dxmt_stamp_want)"
  if dxmt_runtime_fresh; then return 0; fi
  echo "==> Dựng runtime DXMT (bản nhân APFS của Wine gốc, gần như không tốn chỗ)"
  rm -rf "$WINE_DXMT"
  cp -cR "$WINE_BASE" "$WINE_DXMT"
  lib="$WINE_DXMT/lib/wine"
  for d in d3d11 dxgi d3d10core winemetal; do
    cp "$DXMT_DIR/x86_64-windows/$d.dll" "$lib/x86_64-windows/"
    cp "$DXMT_DIR/i386-windows/$d.dll" "$lib/i386-windows/"
  done
  cp "$DXMT_DIR/x86_64-unix/winemetal.so" "$lib/x86_64-unix/"
  cp "$WINEMAC_DXMT" "$lib/x86_64-unix/winemac.so"
  echo "$want" > "$DXMT_STAMP"
}

clear_bottle_d3d() { # gỡ dấu vết DXVK/DXMT trong registry bottle
  for d in d3d11 d3d10core dxgi; do reg_del "$REG\\DllOverrides" "$d"; done
  reg_del "$REG\\Direct3D" VideoPciVendorID
  reg_del "$REG\\Direct3D" VideoPciDeviceID
  reg_del "$REG\\Direct3D" VideoMemorySize
}

sync_bottle_dlls() { # system32/syswow64 = bản builtin của runtime đang dùng (+ winemetal nếu có)
  local lib="$WINE_HOME/lib/wine"
  for d in d3d11 dxgi d3d10core; do
    cp "$lib/x86_64-windows/$d.dll" "$SYS64/"
    [ -d "$SYS32" ] && [ -f "$lib/i386-windows/$d.dll" ] && cp "$lib/i386-windows/$d.dll" "$SYS32/"
  done
  rm -f "$SYS64/winemetal.dll" "$SYS32/winemetal.dll"
  [ -f "$lib/x86_64-windows/winemetal.dll" ] && cp "$lib/x86_64-windows/winemetal.dll" "$SYS64/"
  [ -d "$SYS32" ] && [ -f "$lib/i386-windows/winemetal.dll" ] && cp "$lib/i386-windows/winemetal.dll" "$SYS32/"
  return 0
}

case "${1:-status}" in
  dxmt)
    [ -f "$WINEMAC_DXMT" ] || die "Chưa có winemac.so bản DXMT — chạy ./engines/dxmt/build-winemac.sh trước."
    # winemac.so (kèm sẵn trong gói) chỉ khớp ĐÚNG bản Wine nó được dựng cho
    built_for="$(cat "$WINEMAC_DXMT.wine" 2>/dev/null || echo "?")"
    [ "$built_for" = "$WINE_FLAVOR-$WINE_VERSION" ] || die "winemac.so dựng cho Wine '$built_for' nhưng runtime là '$WINE_FLAVOR-$WINE_VERSION' — chạy ./engines/dxmt/build-winemac.sh (cần: brew install bison flex mingw-w64) hoặc dùng DXVK."
    if [ ! -f "$DXMT_DIR/x86_64-windows/d3d11.dll" ]; then
      [ -f "$DXMT_TAR" ] || curl -fL --progress-bar -o "$DXMT_TAR" "$DXMT_URL"
      mkdir -p "$KEGPLAY_DATA/runtime/dist/dxmt" && tar -xzf "$DXMT_TAR" -C "$KEGPLAY_DATA/runtime/dist/dxmt"
    fi
    build_dxmt_runtime
    use_runtime "$WINE_DXMT"
    clear_bottle_d3d
    sync_bottle_dlls
    echo dxmt > "$WINEPREFIX/.kegplay_engine"
    echo "==> Bottle '$BOTTLE': DXMT $DXMT_VER bật (D3D10/11 → Metal)"
    ;;
  dxvk)
    use_runtime "$WINE_BASE"
    if [ ! -f "$DXVK_DIR/x64/d3d11.dll" ]; then
      [ -f "$DXVK_TAR" ] || curl -fL --progress-bar -o "$DXVK_TAR" "$DXVK_URL"
      mkdir -p "$DXVK_DIR" && tar -xzf "$DXVK_TAR" -C "$DXVK_DIR" --strip-components=1
    fi
    clear_bottle_d3d
    sync_bottle_dlls
    for d in d3d11 d3d10core; do
      cp "$DXVK_DIR/x64/$d.dll" "$SYS64/"
      [ -d "$SYS32" ] && cp "$DXVK_DIR/x32/$d.dll" "$SYS32/"
      reg_set "$REG\\DllOverrides" "$d" REG_SZ native,builtin
    done
    # dxgi của Wine mặc định báo "NVIDIA GeForce 6800" (2004) → game chê GPU yếu. Báo RX 6800 / 8 GB.
    reg_set "$REG\\Direct3D" VideoPciVendorID REG_DWORD 0x1002
    reg_set "$REG\\Direct3D" VideoPciDeviceID REG_DWORD 0x73bf
    reg_set "$REG\\Direct3D" VideoMemorySize REG_SZ 8192
    echo dxvk > "$WINEPREFIX/.kegplay_engine"
    echo "==> Bottle '$BOTTLE': DXVK bật (d3d11, d3d10core), GPU báo AMD RX 6800 / 8 GB"
    ;;
  wined3d)
    use_runtime "$WINE_BASE"
    clear_bottle_d3d
    sync_bottle_dlls
    echo wined3d > "$WINEPREFIX/.kegplay_engine"
    echo "==> Bottle '$BOTTLE': về WineD3D mặc định"
    ;;
  status)
    echo "Bottle '$BOTTLE': công nghệ $(bottle_engine) — runtime $(basename "$WINE_HOME")"
    wine reg query "$REG\\DllOverrides" 2>/dev/null | grep -iE "d3d|dxgi" || echo "Không override D3D"
    wine reg query "$REG\\Direct3D" 2>/dev/null | grep -iE "Video" || true
    ;;
  *) die "Dùng: $0 dxmt|dxvk|wined3d|status" ;;
esac
