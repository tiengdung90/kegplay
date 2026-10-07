#!/bin/bash
# Tạo bản phát hành trên GitHub cho phiên bản trong file VERSION, kèm file tải:
#     ./tools/publish-release.sh ["ghi chú thay đổi"]
# Đẩy lên:  Kegplay.dmg (tên CỐ ĐỊNH — nút tải trên kegplay.com trỏ vào .../releases/latest/download/Kegplay.dmg)
#           Kegplay-<VERSION>.dmg, Kegplay-<VERSION>.zip (bản script)
# Tag = v<VERSION>: app so tag này với VERSION của nó để báo "đã có bản mới".
# Dùng đúng thông tin đăng nhập GitHub mà `git push` đang dùng (Keychain); không in token ra màn hình.
# Trước đó phải: sửa VERSION → ./tools/build-all.sh → git commit + push.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REPO="tiengdung90/kegplay"
VER="$(cat VERSION)"; TAG="v$VER"
DMG="dist/Kegplay-$VER.dmg"; ZIP="dist/Kegplay-$VER.zip"
[ -f "$DMG" ] && [ -f "$ZIP" ] || { echo "LỖI: thiếu $DMG hoặc $ZIP — chạy ./tools/build-all.sh trước"; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "LỖI: còn thay đổi chưa commit — commit + push trước khi phát hành"; exit 1; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main 2>/dev/null)" ] || { echo "LỖI: chưa push — chạy git push trước"; exit 1; }

TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
[ -n "$TOKEN" ] || { echo "LỖI: không lấy được thông tin đăng nhập GitHub (git push có chạy được không?)"; exit 1; }
api() { curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

if api "https://api.github.com/repos/$REPO/releases/tags/$TAG" | grep -q '"upload_url"'; then
  echo "LỖI: bản phát hành $TAG đã có. Muốn ra bản mới thì tăng số trong VERSION."; exit 1
fi
NOTES="${1:-kegPlay $VER}"
BODY="$(TAG="$TAG" VER="$VER" NOTES="$NOTES" perl -MJSON::PP -e 'print JSON::PP->new->encode({tag_name=>$ENV{TAG},target_commitish=>"main",name=>"kegPlay $ENV{VER}",body=>$ENV{NOTES}})')"
RESP="$(api -X POST "https://api.github.com/repos/$REPO/releases" -d "$BODY")"
ID="$(printf '%s' "$RESP" | perl -MJSON::PP -e 'local $/; my $j = eval { JSON::PP->new->decode(<STDIN>) }; print $j->{id} // ""')"
[ -n "$ID" ] || { echo "LỖI: GitHub không tạo bản phát hành:"; printf '%s\n' "$RESP" | head -5; exit 1; }
echo "==> Đã tạo bản phát hành $TAG"

upload() {  # <file> <tên hiện trên GitHub> <loại>
  code="$(api -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: $3" --data-binary "@$1" \
    "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=$2")"
  [ "$code" = "201" ] && echo "    + $2" || { echo "LỖI: tải $2 lên thất bại (mã $code)"; exit 1; }
}
upload "$DMG" "Kegplay.dmg" application/x-apple-diskimage
upload "$DMG" "Kegplay-$VER.dmg" application/x-apple-diskimage
upload "$ZIP" "Kegplay-$VER.zip" application/zip
echo "==> https://github.com/$REPO/releases/tag/$TAG"
echo "    Nút tải trên web: https://github.com/$REPO/releases/latest/download/Kegplay.dmg"
