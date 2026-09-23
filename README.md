# opencode-andev-rules

Global coding rules for TypeScript & NestJS. Plugin for opencode.

## Cài Plugin

```bash
npm install opencode-andev-rules
```

Thêm vào `opencode.json`:

```json
{
  "plugins": ["opencode-andev-rules"]
}
```

## Cài Skill

> `@thaiannguyen-05/skills-cli` chưa được publish lên npm (404), nên không dùng `npx` được.

Dùng cách copy trực tiếp:

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
