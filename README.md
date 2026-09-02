# @thaiannguyen-05/opencode-rules

Global coding rules for TypeScript & NestJS. Plugin for opencode.

## Cài Plugin

```bash
opencode plugin @thaiannguyen-05/opencode-rules
```

hoặc:

```bash
cd ~/.config/opencode
npm install @thaiannguyen-05/opencode-rules
```

Thêm vào `opencode.json`:

```json
{
  "plugins": ["@thaiannguyen-05/opencode-rules"]
}
```

## Cài Skill

```bash
npx @thaiannguyen-05/skills-cli add improve-codenase-systems
```

hoặc:

```bash
cp -r skills/improve-codenase-systems ~/.agents/skills/
```

## Sử dụng

### Rules

Nói "follow the rule of andev" trong prompt.

### Skill

Nói "scan codebase" hoặc "improve codebase" trong prompt.

## Rules

Xem `RULES.md` — covers TypeScript, NestJS, validation, error handling, database, security, API design, testing, and code style.

## Skills

| Skill | Description |
|-------|-------------|
| `improve-codenase-systems` | Scan codebase for architecture issues |
