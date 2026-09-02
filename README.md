# @thaiannguyen-05/opencode-rules

Global coding rules for all AI agents. Plugin for [opencode](https://opencode.ai) to auto-inject rules when you say **"follow the rule of andev"**.

## Rules

See `RULES.md` — covers TypeScript, NestJS, validation, error handling, testing, file structure, and code style.

## Install (opencode plugin)

```bash
cd ~/.config/opencode
npm install @thaiannguyen-05/opencode-rules
```

Add to `opencode.json`:

```json
{
  "plugins": ["@thaiannguyen-05/opencode-rules"]
}
```

## Usage

In any prompt, include one of these trigger phrases:

- `follow the rule of andev`
- `follow andev rules`
- `use andev rules`
- `apply andev rules`
- `andev rules`

Example:

```
Build a user module with CRUD endpoints, follow the rule of andev
```

## How it works

1. Plugin scans your prompt for trigger phrases
2. Fetches `RULES.md` from GitHub
3. Injects rules into the system prompt for that response
4. Caches the fetch — no re-fetch on every turn

## Other Agents

Copy `RULES.md` into any agent's context (Cursor Rules, Windsurf Rules, Cline, etc.) — the rules are agent-agnostic.
