#!/usr/bin/env bash
set -euo pipefail

# Validate every SKILL.md has frontmatter with name + description,
# and every registry.json path/files entry exists on disk.
fail=0

echo "==> Checking SKILL.md frontmatter"
while IFS= read -r f; do
  # first block between --- lines must contain name: and description:
  head -20 "$f" | grep -qE '^name:' || { echo "::error file=$f::missing 'name:' in frontmatter"; fail=1; }
  head -20 "$f" | grep -qE '^description:' || { echo "::error file=$f::missing 'description:' in frontmatter"; fail=1; }
  echo "  OK $f"
done < <(find skills -name 'SKILL.md' | sort)

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

echo "==> npm pack --dry-run"
npm pack --dry-run

if [ "$fail" -ne 0 ]; then
  echo "validation failed"
  exit 1
fi
echo "All checks passed."
