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
├── ci.yml           # 3 jobs async song song (frontmatter/registry/pack) trên mỗi push/PR
└── publish.yml      # nút Run workflow: tự bump version + publish lên npm
```

## Đóng góp

1. Sửa/thêm skill trong `skills/`, mỗi skill phải có `SKILL.md` với frontmatter `name:` + `description:`.
2. Khai báo skill mới vào `skills/registry.json`.
3. Chạy `npm run validate` trước khi push.
4. **Không sửa version bằng tay** — version do workflow publish tự tăng (xem dưới).

