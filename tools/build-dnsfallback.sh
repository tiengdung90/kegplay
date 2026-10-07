#!/bin/bash
# Dựng prebuilt/dnsfallback.dylib từ src/dnsfallback/dnsfallback.c (cần clang của Command Line Tools).
# Universal: x86_64 cho Wine (chạy qua Rosetta), arm64 để các lệnh native trong script không báo lỗi nạp.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
clang -arch x86_64 -arch arm64 -mmacosx-version-min=11.0 -O2 -Wall -dynamiclib \
  -o "$ROOT/prebuilt/dnsfallback.dylib" "$ROOT/src/dnsfallback/dnsfallback.c" -lresolv
codesign --force --sign - "$ROOT/prebuilt/dnsfallback.dylib" 2>/dev/null
echo "==> prebuilt/dnsfallback.dylib ($(lipo -archs "$ROOT/prebuilt/dnsfallback.dylib"))"
