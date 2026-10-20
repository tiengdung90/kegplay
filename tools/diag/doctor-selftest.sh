#!/bin/bash
# Tự kiểm scripts/doctor.pl bằng thư viện Steam giả: mỗi "game" là một exe nhỏ gọi đúng một API đồ hoạ.
#   tools/diag/doctor-selftest.sh      → in kết quả, trả mã 1 nếu có ca sai
# Cần mingw-w64 (chỉ người phát triển). Không đụng bottle thật.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
A="$T/steamapps"; mkdir -p "$A/common"
mk() { # <appid> <tên> <thư mục> <hàm gọi> <thư viện>
  mkdir -p "$A/common/$3"
  printf 'void %s(void);\nint main(void){ %s(); return 0; }\n' "$4" "$4" > "$T/m.c"
  x86_64-w64-mingw32-gcc -o "$A/common/$3/game.exe" "$T/m.c" -l"$5" 2>/dev/null
  printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"%s"\n}\n' "$1" "$2" "$3" > "$A/appmanifest_$1.acf"
}
mk 1 "DX12 game"    dx12  D3D12CreateDevice      d3d12
mk 2 "DX9 game"     dx9   Direct3DCreate9        d3d9
mk 3 "DDraw game"   ddraw DirectDrawCreate       ddraw
mk 4 "DX11 game"    dx11  D3D11CreateDevice      d3d11
mk 5 "Online game"  ac    D3D11CreateDevice      d3d11; mkdir -p "$A/common/ac/EasyAntiCheat"
mk 6 "Downloading"  dl    D3D11CreateDevice      d3d11; sed -i '' 's/"StateFlags"\t\t"4"/"StateFlags"\t\t"1026"/' "$A/appmanifest_6.acf"
got="$(KEGPLAY_DDRAW_APPIDS="" KEGPLAY_D3DC_FIXES="" perl "$HERE/scripts/doctor.pl" "$A" | cut -f1,3,4 | tr '\t' ' ')"
echo "$got"
want="1 bad dx12-only
2 warn dx9
3 warn ddraw-video-mode
4 ok dx11
5 warn anticheat
5 ok dx11"
[ "$got" = "$want" ] && echo "==> doctor: mọi ca đúng" || { echo "==> doctor: SAI, mong đợi:"; echo "$want"; exit 1; }
