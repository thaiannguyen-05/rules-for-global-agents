#!/usr/bin/env bash
set -euo pipefail

# Bump version an toàn: validate skills -> bump package.json (+ sync
# registry.json) -> kiểm tra version chưa tồn tại trên npm -> push tag.
#
#   bash scripts/release.sh patch [--push]   # 1.0.0 -> 1.0.1
#   bash scripts/release.sh minor [--push]   # 1.0.0 -> 1.1.0
#   bash scripts/release.sh major [--push]   # 1.0.0 -> 2.0.0
#   bash scripts/release.sh 1.2.3 [--push]   # version cụ thể
#
# Mặc định CÓ push (commit + tag) lên origin để kích hoạt workflow publish.
# Dùng --no-push để chỉ bump local.

BUMP="${1:-patch}"
PUSH=true
for arg in "$@"; do
  [ "$arg" = "--no-push" ] && PUSH=false
  [ "$arg" = "--push" ] && PUSH=true
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

# npm version với version cụ thể mà <= hiện tại sẽ tự fail; kiểm tra lại cho chắc
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

FILES_TO_COMMIT="package.json skills/registry.json"
[ -f package-lock.json ] && FILES_TO_COMMIT="$FILES_TO_COMMIT package-lock.json"
# shellcheck disable=SC2086
git add $FILES_TO_COMMIT
git commit -m "chore(release): v$NEW_VERSION" > /dev/null
git tag "v$NEW_VERSION"
echo "  committed + tagged v$NEW_VERSION"

if [ "$PUSH" = true ]; then
  git push --follow-tags
  echo "Đã push v$NEW_VERSION. Workflow 'Publish to npm' sẽ publish lên npm."
  echo "Theo dõi tại: $(git remote get-url origin | sed 's/git@github.com:/https:\/\/github.com\//;s/\.git$//')/actions"
else
  echo "Xong local (chưa push). Khi sẵn sàng:"
  echo "  git push --follow-tags"
fi
