---
name: prisma
description: Prisma ORM rules — client setup, queries, errors, transactions, migrations. Use when building or reviewing Prisma data access.
---

# Prisma Skill

## Setup

- One PrismaClient singleton for the whole app — never `new PrismaClient()` per request or per service.
- Provide it once (global module / DI) — services inject it, never instantiate it.
- Datasource URL from env only — never hardcode connection strings, never log them.
- Size the pool via `connection_limit`/`pool_timeout` — serverless or hot-reload dev must reuse the singleton or use an external pooler.

## Relations: FK/PK decision

- Always ask the user before modeling relations: database-enforced foreign keys vs Prisma-emulated relations (`relationMode = "prisma"`).
- Without DB-level FKs, Prisma can still join via `include` — but nothing enforces referential integrity in the database.
- With DB FKs: integrity enforced by the database; `onDelete` acts at the DB level; migrations carry the constraints.
- Without DB FKs: integrity must be enforced in application code (existence checks + transactions); no `onDelete` in the database; fits providers without FK support.
- Never assume one mode — the choice changes schema, migrations, and error handling; confirm it first.

## Queries

- Use `select` when only a subset of fields is required — don't over-fetch.
- Avoid N+1 queries — use `include` or joins, not loops.
- Avoid `include` for large relation collections — paginate or `select` instead.
- Prisma fetches all scalar columns by default — with wide tables or heavy columns (text, JSON), always narrow it down.
- Never blanket `include` — it pulls every column of the related table; nest `select` inside instead.

```typescript
// Good — narrow scalars, nested select for relations
await prisma.user.findMany({
  select: { id: true, name: true, posts: { select: { id: true, title: true } } },
});

// Or drop heavy fields (Prisma 6.2+)
await prisma.post.findMany({ omit: { content: true } });
```
- Use `findUnique` when the field is unique — `findFirst` only otherwise.
- Paginate `findMany` — never return unbounded results; cursor pagination for large datasets, offset for small.
- Always `orderBy` deterministic fields for pagination.
- Run independent queries in parallel — don't `await` sequentially.
- Never raw SQL unless performance-critical (comment why) — never concatenate values into queries, use parameterized inputs.

## Errors

- Map Prisma errors to domain exceptions in one place (`P2002` → conflict, `P2025` → not found, ...) — never leak raw Prisma errors to API responses.

## Transactions

- Multi-step writes go in `$transaction` — no partial writes.
- Keep transaction scope small — no external calls inside transactions.
- Race conditions on read-modify-write — use transactions or locks.

## Migrations

- Keep migrations in `prisma/migrations` and commit them — never edit an applied migration, create a new one instead.
- Deploy with `migrate deploy` — never `migrate dev` against prod.
- Review destructive changes (drop column/table, type narrowing) before applying — backfill via a data migration when rows exist.

## References

- Schema layout, models, indexes, relations, enums: `references/prisma-schema.md`.
- CLI, CRUD, optimization catalog: `references/prisma-queries.md`.
