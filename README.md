# opencode-andev-rules

Global coding rules for TypeScript & NestJS + AI agent skills.

[![CI](https://github.com/thaiannguyen-05/rules-for-global-agents/actions/workflows/ci.yml/badge.svg)](https://github.com/thaiannguyen-05/rules-for-global-agents/actions/workflows/ci.yml)
[![npm](https://img.shields.io/npm/v/opencode-andev-rules)](https://www.npmjs.com/package/opencode-andev-rules)

## Cài đặt

### Cách 1 — npm (khuyên dùng)

```bash
npm install opencode-andev-rules
# skills nằm ở node_modules/opencode-andev-rules/skills/
```

### Cách 2 — copy thủ công

```bash
cp -r skills/enhance/improve-codenase-systems ~/.agents/skills/
cp -r skills/backend/nestJS ~/.agents/skills/
cp -r skills/infrastructure/prisma ~/.agents/skills/
```

## Skills

| Skill | Đường dẫn | Dùng khi |
|-------|-----------|----------|
| `improve-codenase-systems` | `skills/enhance/improve-codenase-systems/` | Muốn scan codebase tìm vấn đề kiến trúc — nói "scan codebase" hoặc "improve codebase" trong prompt |
| `nestjs` | `skills/backend/nestJS/` | Viết/review code NestJS — module structure, Fastify, zod validation, DI |
| `prisma` | `skills/infrastructure/prisma/` | Viết/review Prisma — client singleton, queries, transactions, migrations |

Chi tiết từng skill xem file `SKILL.md` trong thư mục tương ứng. Danh mục đầy đủ: `skills/registry.json`.

## Cấu trúc repo

```
skills/
├── backend/nestJS/                    # rules NestJS
│   ├── SKILL.md
│   └── references/nestjs-module.md
├── infrastructure/prisma/             # rules Prisma
│   ├── SKILL.md
│   └── references/
├── enhance/improve-codenase-systems/   # skill scan kiến trúc
│   ├── SKILL.md
│   ├── HTML-REPORT.md
│   ├── meta.json
│   └── agents/openai.yaml
└── registry.json                      # danh mục skills (version top-level sync với package.json)
scripts/
├── validate.sh      # kiểm tra frontmatter SKILL.md + registry + npm pack --dry-run
├── check-version.sh # kiểm tra version chưa tồn tại trên npm
└── release.sh       # bump version an toàn (xem dưới)
.github/workflows/
├── ci.yml           # validate + version-guard trên mỗi push/PR
└── publish.yml      # publish lên npm khi push tag v*.*.* hoặc tạo Release
```

## Đóng góp

1. Sửa/thêm skill trong `skills/`, mỗi skill phải có `SKILL.md` với frontmatter `name:` + `description:`.
2. Khai báo skill mới vào `skills/registry.json`.
3. Chạy `npm run validate` trước khi push.
4. **Bắt buộc bump version** nếu PR đụng tới `skills/` (CI `version-guard` sẽ fail nếu quên) — dùng `bash scripts/release.sh patch|minor|major`.

## Release lên npm

> npm **từ chối publish đè version cũ** — mọi lần release đều phải bump version trước.

```bash
bash scripts/release.sh patch   # fix skill, sửa doc      (1.0.0 -> 1.0.1)
bash scripts/release.sh minor   # thêm skill mới          (1.0.0 -> 1.1.0)
bash scripts/release.sh major   # đổi cấu trúc, breaking  (1.0.0 -> 2.0.0)
bash scripts/release.sh 1.2.3   # version cụ thể
```

Script tự: validate skills → bump `package.json` + sync `skills/registry.json`
→ kiểm tra version chưa có trên npm → commit + tag `vX.Y.Z` → `push --follow-tags`.
Workflow "Publish to npm" chạy khi push tag `v*.*.*` hoặc khi tạo GitHub Release,
kiểm tra lại (tag khớp `package.json`, version chưa tồn tại, pack dry-run) rồi publish.

Kiểm tra: https://www.npmjs.com/package/opencode-andev-rules

### Setup npm auth 1 lần duy nhất (chọn 1 trong 2)

**Cách A — NPM_TOKEN (nhanh nhất):**
1. npmjs.com → Access Tokens → Generate New Token → **Automation**
2. GitHub repo → Settings → Secrets → Actions → New secret `NPM_TOKEN` = token vừa tạo

**Cách B — Trusted Publishing (không cần token):**
1. npmjs.com → package `opencode-andev-rules` → Settings → Trusted Publisher → GitHub Actions → nhập `thaiannguyen-05/rules-for-global-agents` + workflow `publish.yml`
2. Xóa secret `NPM_TOKEN` (workflow tự fallback sang OIDC, Node 22 đã đủ npm ≥ 11.5.1)
