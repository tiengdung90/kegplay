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
[ -f "$DMG" ] && [ -f "$ZIP" ] || { echo "ERROR: Missing $DMG or $ZIP. Run ./tools/build-all.sh first."; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "ERROR: Uncommitted changes. Commit and push before releasing."; exit 1; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main 2>/dev/null)" ] || { echo "ERROR: Local HEAD differs from origin/main. Push before releasing."; exit 1; }

TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
[ -n "$TOKEN" ] || { echo "ERROR: Could not retrieve GitHub credentials. Check whether git push works."; exit 1; }
api() { curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

if api "https://api.github.com/repos/$REPO/releases/tags/$TAG" | grep -q '"upload_url"'; then
  echo "ERROR: Release $TAG already exists. Bump VERSION for a new release."; exit 1
fi
NOTES="${1:-kegPlay $VER}"
BODY="$(TAG="$TAG" VER="$VER" NOTES="$NOTES" perl -MJSON::PP -e 'print JSON::PP->new->encode({tag_name=>$ENV{TAG},target_commitish=>"main",name=>"kegPlay $ENV{VER}",body=>$ENV{NOTES}})')"
RESP="$(api -X POST "https://api.github.com/repos/$REPO/releases" -d "$BODY")"
ID="$(printf '%s' "$RESP" | perl -MJSON::PP -e 'local $/; my $j = eval { JSON::PP->new->decode(<STDIN>) }; print $j->{id} // ""')"
[ -n "$ID" ] || { echo "ERROR: GitHub did not create the release:"; printf '%s\n' "$RESP" | head -5; exit 1; }
echo "==> Created release $TAG"

upload() {  # <file> <tên hiện trên GitHub> <loại>
  code="$(api -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: $3" --data-binary "@$1" \
    "https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=$2")"
  [ "$code" = "201" ] && echo "    + $2" || { echo "ERROR: Upload of $2 failed (HTTP $code)"; exit 1; }
}
upload "$DMG" "Kegplay.dmg" application/x-apple-diskimage
upload "$DMG" "Kegplay-$VER.dmg" application/x-apple-diskimage
upload "$ZIP" "Kegplay-$VER.zip" application/zip
echo "==> https://github.com/$REPO/releases/tag/$TAG"
echo "    Website download link: https://github.com/$REPO/releases/latest/download/Kegplay.dmg"
