#!/usr/bin/env bash
set -euo pipefail

# Fail nếu version hiện tại trong package.json đã tồn tại trên npm.
# Dùng trong workflow publish để báo lỗi rõ ràng thay vì để
# `npm publish` chết với lỗi 403/E403 khó hiểu.
# Ngoại lệ: package chưa từng publish (E404) => OK.

PKG_NAME=$(node -p "require('./package.json').name")
PKG_VERSION=$(node -p "require('./package.json').version")

if ! node -e "const v='$PKG_VERSION'; if(!/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/.test(v)){console.error('invalid semver: '+v);process.exit(1)}"; then
  echo "::error::package.json version '$PKG_VERSION' không phải semver hợp lệ."
  exit 1
fi

ERR_FILE=$(mktemp)
if npm view "$PKG_NAME@$PKG_VERSION" version > /dev/null 2>"$ERR_FILE"; then
  echo "::error::$PKG_NAME@$PKG_VERSION đã tồn tại trên npm. Hãy bump version (vd: bash scripts/release.sh patch) rồi tag lại."
  rm -f "$ERR_FILE"
  exit 1
fi

if grep -q "E404" "$ERR_FILE"; then
  echo "OK: $PKG_NAME@$PKG_VERSION chưa tồn tại trên npm, publish được."
else
  echo "npm view thất bại với lỗi lạ (không phải E404), không dám kết luận:"
  cat "$ERR_FILE"
  rm -f "$ERR_FILE"
  exit 1
fi
rm -f "$ERR_FILE"
