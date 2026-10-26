#!/usr/bin/env bash
set -euo pipefail

# Validate every SKILL.md has frontmatter with name + description,
# and every registry.json path/files entry exists on disk.
#
# Chạy full (sync, dùng local):  bash scripts/validate.sh
# Chạy lẻ (để CI chạy async song song):
#   bash scripts/validate.sh --only-frontmatter
#   bash scripts/validate.sh --only-registry
#   bash scripts/validate.sh --only-pack

ONLY="${1:-all}"
case "$ONLY" in
  all|--only-frontmatter|--only-registry|--only-pack) ;;
  *)
    echo "Usage: $0 [all|--only-frontmatter|--only-registry|--only-pack]" >&2
    exit 2
    ;;
esac

run_frontmatter=0
run_registry=0
run_pack=0
case "$ONLY" in
  all) run_frontmatter=1; run_registry=1; run_pack=1 ;;
  --only-frontmatter) run_frontmatter=1 ;;
  --only-registry) run_registry=1 ;;
  --only-pack) run_pack=1 ;;
esac

fail=0

if [ "$run_frontmatter" -eq 1 ]; then
echo "==> Checking SKILL.md frontmatter"
while IFS= read -r f; do
  # first block between --- lines must contain name: and description:
  head -20 "$f" | grep -qE '^name:' || { echo "::error file=$f::missing 'name:' in frontmatter"; fail=1; }
  head -20 "$f" | grep -qE '^description:' || { echo "::error file=$f::missing 'description:' in frontmatter"; fail=1; }
  echo "  OK $f"
done < <(find skills -name 'SKILL.md' | sort)
fi

if [ "$run_registry" -eq 1 ]; then
echo "==> Checking skills/registry.json entries"
node -e '
const fs = require("fs");
const path = require("path");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
const reg = JSON.parse(fs.readFileSync("skills/registry.json", "utf8"));
let bad = false;
if (reg.version !== pkg.version) {
  console.error(`::error::skills/registry.json version "${reg.version}" != package.json version "${pkg.version}". Chạy bash scripts/release.sh để sync.`);
  bad = true;
}
for (const s of reg.skills) {
  const base = s.path;
  if (!fs.existsSync(base)) { console.error(`::error::registry "${s.name}": path "${base}" does not exist`); bad = true; continue; }
  for (const f of (s.files || [])) {
    const p = path.join(base, f);
    if (!fs.existsSync(p)) { console.error(`::error::registry "${s.name}": file "${p}" does not exist`); bad = true; }
  }
}
if (bad) process.exit(1);
console.log(`  OK ${reg.skills.length} skill(s) in registry`);
'
fi

if [ "$run_pack" -eq 1 ]; then
echo "==> npm pack --dry-run"
npm pack --dry-run
fi

if [ "$fail" -ne 0 ]; then
  echo "validation failed"
  exit 1
fi
echo "All checks passed."
