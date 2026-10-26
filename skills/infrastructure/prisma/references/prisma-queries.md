# Prisma Queries & Operations

Samples assume the global singleton `prisma` (see `SKILL.md` Setup) — never `new PrismaClient()` per call.

## CLI

| Command | Use |
|---|---|
| `prisma generate` | Regenerate Prisma Client |
| `prisma migrate dev` | Create and apply migrations in dev |
| `prisma migrate deploy` | Apply migrations in production/CI |
| `prisma db push` | Push schema straight to DB, no migration (prototypes only) |
| `prisma db pull` | Introspect an existing DB into the schema |
| `prisma studio` | Open the GUI |

## CRUD

```typescript
// Create
await prisma.user.create({ data: { email: 'a@b.com', name: 'An' } });

// Read
await prisma.user.findUnique({ where: { email: 'a@b.com' } });
await prisma.user.findMany({
  where: { name: { contains: 'An' } },
  orderBy: { id: 'desc' },
  take: 10,
});

// Update / Delete
await prisma.user.update({ where: { id: 'user_01' }, data: { name: 'Bình' } });
await prisma.user.delete({ where: { id: 'user_01' } });

// Relations — narrow, never blanket include
await prisma.user.findMany({
  select: { id: true, name: true, posts: { select: { id: true, title: true } } },
});

// Transaction (independent writes)
await prisma.$transaction([
  prisma.user.create({ data: { email: 'x@y.com', name: 'X' } }),
  prisma.post.create({ data: { title: 'Hi', authorId: 'user_01' } }),
]);
```

## Optimization

### 1. Select only what you need (`select` / `omit`)

- Same rule as `SKILL.md` Queries — full example there.
- Never blanket `include` — it pulls every column of the related table.

### 2. Avoid N+1 queries

```typescript
// Wrong (N+1)
const users = await prisma.user.findMany();
for (const u of users) {
  u.posts = await prisma.post.findMany({ where: { authorId: u.id } });
}

// Right — one round trip, narrowed
const users = await prisma.user.findMany({
  select: { id: true, name: true, posts: { select: { id: true, title: true } } },
});
```

- `relationLoadStrategy: 'join'` lets Prisma use one JOIN instead of separate queries — check preview/GA status for your Prisma version.
- Simultaneous `findUnique` calls in the same tick are auto-batched (dataloader) — useful for GraphQL resolvers.

### 3. Index the right columns

```prisma
model Post {
  // ...
  @@index([authorId])                 // FK
  @@index([published, createdAt])     // composite for filter + sort
  @@unique([authorId, slug])

  @@map("posts")
}
```

- Index columns used in `where`, `orderBy`, joins — column order matters in composite indexes.
- Never over-index — indexes slow down writes.

### 4. Paginate efficiently

- Offset (`skip` + `take`) slows down as `skip` grows — the DB still scans skipped rows.
- Cursor pagination is stable and fast for large datasets:

```typescript
await prisma.post.findMany({
  take: 20,
  skip: 1,
  cursor: { id: lastId },
  orderBy: { id: 'asc' },
});
```

### 5. Batch writes

- Never loop single-row writes — use batch operations:

```typescript
await prisma.user.createMany({ data: users, skipDuplicates: true });
await prisma.post.updateMany({ where: { authorId: 'user_01' }, data: { published: true } });
await prisma.post.deleteMany({ where: { published: false } });
```

### 6. Connection pooling

- Reuse the singleton everywhere — hot-reload dev and serverless must guard it, never create clients per invocation:

```typescript
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };
export const prisma = globalForPrisma.prisma ?? new PrismaClient();
if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;
```

- Size the pool via connection string: `?connection_limit=10&pool_timeout=20`.
- Serverless (Vercel, Lambda): use an external pooler (PgBouncer, Supabase pooler, Prisma Accelerate) — never exhaust direct connections.

### 7. Aggregate in the database

```typescript
await prisma.post.groupBy({ by: ['authorId'], _count: { _all: true } });
await prisma.order.aggregate({ _sum: { total: true }, where: { status: 'PAID' } });
await prisma.user.findMany({ include: { _count: { select: { posts: true } } } });
```

- Filter, sort, and count in the DB — never pull everything and `.filter()` in code.

### 8. Keep transactions lean

- `$transaction([...])` batch form for independent operations.
- Interactive form only when logic runs between steps — keep it short:

```typescript
await prisma.$transaction(
  async (tx) => {
    const acc = await tx.account.update({
      where: { id },
      data: { balance: { decrement: 100 } },
    });
    if (acc.balance < 0) throw new Error('Insufficient balance');
  },
  { timeout: 5000, maxWait: 2000 },
);
```

- No external API calls, no heavy work inside transactions — they hold connections and locks.

### 9. Raw queries for complex cases

- Window functions, CTEs, advanced full-text search: use raw queries.
- Always the tagged template form — never string-concatenate user input:

```typescript
const rows = await prisma.$queryRaw`
  SELECT author_id, COUNT(*) FROM "posts" WHERE published = true GROUP BY author_id
`;
```

- Never `$queryRawUnsafe` with user input — use TypedSQL for typed raw queries.

### 10. Measure before optimizing

```typescript
const prisma = new PrismaClient({ log: ['query', 'warn', 'error'] });
```

- Enable query logging in dev (on the singleton) to catch N+1 and redundant queries.
- Run `EXPLAIN ANALYZE` on generated SQL to confirm index usage.
- Trace per-query time with OpenTelemetry or Prisma `$extends`.

### 11. Cache

- Cache heavy-read, rarely-changed results with Redis or in-memory.
- Prisma Accelerate supports `cacheStrategy: { ttl: 60, swr: 120 }`.

### 12. Cold start / bundle

- Edge/serverless: consider driver adapters (Neon, PlanetScale, D1, ...) to cut size and startup latency — check your Prisma version.
- Generate only the needed binary targets on deploy (`binaryTargets`).

## Checklist

- One PrismaClient singleton
- Always `select`/`omit` on wide tables
- No queries in loops — use `include`, `in`, `createMany`
- Indexes on FKs and filter/sort columns
- Cursor pagination for large lists
- Short transactions
- Query logging in dev to catch N+1
- Pooler for serverless
- Raw SQL for complex queries (safe tagged-template form)
