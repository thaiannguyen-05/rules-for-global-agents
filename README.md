# @thaiannguyen-05/opencode-rules

On-demand rule injection plugin for [opencode](https://opencode.ai). Say **"follow the rule of andev"** in your prompt to load rules from your GitHub repo.

## Install

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
2. Fetches `RULES.md` from `https://raw.githubusercontent.com/thaiannguyen-05/rules-for-global-agents/main/RULES.md`
3. Injects rules into the system prompt for that response
4. Caches the fetch — no re-fetch on every turn

## Configuration

The GitHub repo URL is hardcoded. To change it, edit `plugin.js`:

```js
const RULES_URL = 'https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/RULES.md';
```

## Requirements

- opencode >= 1.15.0
- A `RULES.md` file in your GitHub repo
