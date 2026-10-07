#!/bin/bash
# Dựng Kegplay.app + file .dmg:   ./tools/build-app.sh   →  dist/Kegplay.app, dist/Kegplay-<version>.dmg
# Cần: Swift (Command Line Tools là đủ, không bắt buộc Xcode). App chưa ký với Apple (ad-hoc) → người dùng
# mở lần đầu bằng chuột phải › Open. Mã script được chép từ đúng danh sách của gói phát hành (make-release.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VER="$(cat VERSION)"
APP="$ROOT/dist/Kegplay.app"
DMG="$ROOT/dist/Kegplay-$VER.dmg"

echo "==> Biên dịch (swift build -c release)"
( cd app && swift build -c release 2>&1 | grep -E "error|Build complete" ) || { echo "LỖI biên dịch"; exit 1; }
BIN="$ROOT/app/.build/release/Kegplay"
[ -x "$BIN" ] || { echo "LỖI: không thấy $BIN"; exit 1; }

echo "==> Gói mã script (dùng make-release.sh để cùng danh sách file + cùng bước tự kiểm)"
"$ROOT/tools/make-release.sh" >/dev/null
TMP="$(mktemp -d)"
unzip -q "$ROOT/dist/Kegplay-$VER.zip" -d "$TMP"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kegplay"
cp "$ROOT/app/Kegplay.icns" "$APP/Contents/Resources/Kegplay.icns"
# đa ngôn ngữ: sinh lại từ bảng dịch rồi chép các <mã>.lproj vào app
python3 "$ROOT/tools/make-localizations.py" >/dev/null || { echo "LỖI: bảng dịch thiếu/lệch (chạy tools/make-localizations.py để xem)"; exit 1; }
cp -R "$ROOT/app/Localization/"*.lproj "$APP/Contents/Resources/"
LPROJS="$(cd "$ROOT/app/Localization" && for d in *.lproj; do printf "<string>%s</string>" "${d%.lproj}"; done)"
mv "$TMP/Kegplay" "$APP/Contents/Resources/kegplay"
# trong app không cần các nút .command và install.sh (giao diện làm thay)
rm -f "$APP/Contents/Resources/kegplay/"*.command "$APP/Contents/Resources/kegplay/install.sh"
# số build (tools/build-all.sh tăng dần) — app hiện cạnh số phiên bản để biết đang chạy bản dựng nào
BUILD_NO="$(cat "$ROOT/BUILD" 2>/dev/null || echo 0)"
echo "$BUILD_NO" > "$APP/Contents/Resources/kegplay/BUILD"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Kegplay</string>
  <key>CFBundleDisplayName</key><string>Kegplay</string>
  <key>CFBundleIdentifier</key><string>com.kegplay.app</string>
  <key>CFBundleExecutable</key><string>Kegplay</string>
  <key>CFBundleIconFile</key><string>Kegplay</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>$LPROJS</array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VER</string>
  <key>CFBundleVersion</key><string>$BUILD_NO</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Kegplay contributors. Wine, DXMT, DXVK, SpoofDPI thuộc tác giả tương ứng.</string>
</dict>
</plist>
PLIST

# ký ad-hoc cả gói (bắt buộc tối thiểu trên Apple Silicon; KHÔNG thay được chữ ký Developer ID + notarize)
codesign --force --deep --sign - "$APP" 2>/dev/null
codesign --verify --deep "$APP" && echo "==> $APP (ký ad-hoc ✓, $(du -sh "$APP" | cut -f1))"

echo "==> Tạo DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Kegplay $VER" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "==> $DMG ($(du -h "$DMG" | cut -f1))"
