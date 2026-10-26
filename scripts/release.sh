#!/usr/bin/env bash
set -euo pipefail

# Publish từ máy local, KHÔNG cần sửa package.json bằng tay.
# (Cách chính vẫn là nút Actions -> "Publish to npm" -> Run workflow,
#  script này chỉ dành cho ai muốn chạy local — yêu cầu đã `npm login`.)
#
#   bash scripts/release.sh patch   # 1.0.0 -> 1.0.1 (fix skill, sửa doc)
#   bash scripts/release.sh minor   # 1.0.0 -> 1.1.0 (thêm skill mới)
#   bash scripts/release.sh major   # 1.0.0 -> 2.0.0 (đổi cấu trúc, breaking)
#   bash scripts/release.sh 1.2.3   # version cụ thể
#
# Thêm --no-push để chỉ bump + publish local mà chưa push tag.

BUMP="${1:-patch}"
PUSH=true
for arg in "$@"; do
  [ "$arg" = "--no-push" ] && PUSH=false
done
case "$BUMP" in --push|--no-push) BUMP="patch";; esac

if [ -n "$(git status --porcelain)" ]; then
  echo "::error::Working tree bẩn. Commit hoặc stash hết rồi chạy lại."
  exit 1
fi

BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  echo "Cảnh báo: đang ở nhánh '$BRANCH' (không phải main). Tiếp tục sau 5s... (Ctrl+C để hủy)"
  sleep 5
fi

echo "==> Validate skills"
bash scripts/validate.sh > /dev/null
echo "  validate OK"

OLD_VERSION=$(node -p "require('./package.json').version")
echo "==> Bump version: $OLD_VERSION -> ($BUMP)"
npm version "$BUMP" --no-git-tag-version > /dev/null
NEW_VERSION=$(node -p "require('./package.json').version")

if [ "$NEW_VERSION" = "$OLD_VERSION" ]; then
  echo "::error::Version không đổi ($OLD_VERSION). Kiểm tra lại tham số bump."
  exit 1
fi

# Sync version top-level của registry.json theo package.json
node -e "
const fs = require('fs');
const p = 'skills/registry.json';
const reg = JSON.parse(fs.readFileSync(p, 'utf8'));
reg.version = '$NEW_VERSION';
fs.writeFileSync(p, JSON.stringify(reg, null, 2) + '\n');
"
echo "  synced skills/registry.json version -> $NEW_VERSION"

echo "==> Kiểm tra version chưa tồn tại trên npm"
bash scripts/check-version.sh

echo "==> Publish $NEW_VERSION lên npm (dùng npm auth local)"
npm publish --provenance --access public

git add package.json skills/registry.json
[ -f package-lock.json ] && git add package-lock.json
git commit -m "chore(release): v$NEW_VERSION" > /dev/null
git tag "v$NEW_VERSION"
echo "  committed + tagged v$NEW_VERSION"

if [ "$PUSH" = true ]; then
  git push --follow-tags
  echo "Xong: đã publish $NEW_VERSION và push tag."
else
  echo "Publish xong local (chưa push). Khi sẵn sàng:"
  echo "  git push --follow-tags"
fi
