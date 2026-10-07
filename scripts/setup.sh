#!/bin/bash
# Tải Wine (Gcenx build) vào runtime/ và tạo bottle.
set -euo pipefail
source "$(dirname "$0")/env.sh"

# Wine bản osx64 là x86_64 → cần Rosetta 2
if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  die "Chưa có Rosetta 2. Chạy: softwareupdate --install-rosetta --agree-to-license"
fi

if [ ! -x "$WINE_BASE/bin/wine" ]; then
  mkdir -p "$KEGPLAY_DATA/cache" "$WINE_BASE"
  if [ ! -f "$KEGPLAY_DATA/cache/$WINE_TARBALL" ]; then
    echo "==> Tải $WINE_TARBALL"
    curl -fL --progress-bar -o "$KEGPLAY_DATA/cache/$WINE_TARBALL.part" "$WINE_URL"
    mv "$KEGPLAY_DATA/cache/$WINE_TARBALL.part" "$KEGPLAY_DATA/cache/$WINE_TARBALL"
  fi
  echo "==> Giải nén Wine"
  tmp="$(mktemp -d)"
  tar -xJf "$KEGPLAY_DATA/cache/$WINE_TARBALL" -C "$tmp"
  # Lấy thư mục wine/ bên trong "Wine Staging.app/Contents/Resources/"
  src="$(find "$tmp" -maxdepth 4 -type d -path '*/Contents/Resources/wine' | head -1)"
  [ -n "$src" ] || die "Không thấy thư mục wine trong gói"
  cp -R "$src/." "$WINE_BASE/"
  rm -rf "$tmp"
  # Bỏ cờ quarantine để Gatekeeper không chặn từng dylib
  xattr -dr com.apple.quarantine "$WINE_BASE" 2>/dev/null || true
fi
echo "==> Wine: $("$WINE_BASE/bin/wine" --version)"

if [ ! -f "$WINEPREFIX/system.reg" ]; then
  echo "==> Tạo bottle '$BOTTLE' tại $WINEPREFIX (lần đầu mất ~1 phút)"
  mkdir -p "$WINEPREFIX"
  wineboot --init >"$LOG_DIR/setup-$BOTTLE.log" 2>&1
  wineserver -w
  # Khai báo Windows 10 cho game/Steam
  wine reg add 'HKCU\Software\Wine' /v Version /d win10 /f >>"$LOG_DIR/setup-$BOTTLE.log" 2>&1
  wineserver -w
fi
echo "==> Xong. Bottle: $WINEPREFIX"
echo "    Tiếp theo: ./scripts/install-steam.sh"

# Vượt chặn Steam Store: bật mặc định (nhà mạng VN chặn store.steampowered.com). Kegplay tự tải SpoofDPI vào
# runtime/ và chỉ áp cho bottle này — không đổi proxy của máy. Ở nơi không bị chặn: KEGPLAY_UNBLOCK=0 ./scripts/setup.sh
# (hoặc tắt sau bằng ./scripts/proxy.sh off).
if [ "${KEGPLAY_UNBLOCK:-1}" = "1" ]; then
  "$KEGPLAY_ROOT/scripts/proxy.sh" on
fi
