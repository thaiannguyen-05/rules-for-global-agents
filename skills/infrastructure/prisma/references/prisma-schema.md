# Prisma Schema Structure Rules

## Layout

- Follow this tree exactly — schema, migrations, and seed stay under `prisma/`.
- Split the schema per domain under `prisma/schema/` — never one giant `schema.prisma`.

```
prisma/
├── schema/
│   ├── base.prisma
│   ├── user.prisma
│   └── order.prisma
├── seed.ts
└── migrations/
    └── 20240101000000_init/
        └── migration.sql
```

- `base.prisma` holds only `generator` + `datasource` — never models or enums in it.
- One file per domain (`user.prisma`, `order.prisma`, ...) holding its models + enums — never split one model across files.
- Cross-file relations reference the model by name — Prisma merges all files, no imports needed.
- One model per table — never two models over the same table.

## Models

- Model names PascalCase singular with `@@map` to the snake_case table (e.g., `model User ... @@map("users")`).
- Field names camelCase; map to snake_case columns with `@map` when the database uses snake_case.
- Every model has a primary key, `createdAt`, and `updatedAt` — never a model without a PK.
- Primary keys are `String @id @default(uuid())` — never auto-increment ints for IDs.
- Soft-delete with `deletedAt DateTime?` — always filter it in queries, never return soft-deleted rows by default.
- Put DB-level defaults in the schema (`@default`, `@updatedAt`) — never rely on application code for timestamps.

```prisma
model User {
  id        String    @id @default(uuid())
  email     String    @unique
  name      String
  role      Role      @default(USER)
  createdAt DateTime  @default(now())
  updatedAt DateTime  @updatedAt
  deletedAt DateTime?

  @@map("users")
}
```

## Enums

- Fixed sets (status, role) are Prisma enums — never free strings for status-like fields.
- Map enum values explicitly when the database stores different labels.

```prisma
enum Role {
  ADMIN
  USER
}
```

## Relations

- Confirm FK/PK mode first (decision gate in `SKILL.md`) — the rules below assume DB-enforced foreign keys.
- No-FK mode: skip DB constraints and `onDelete`, enforce integrity in code with existence checks + transactions.
- Name relations explicitly when two models link more than once — never leave ambiguous relations unnamed.
- Set `onDelete` deliberately per relation (`Cascade`, `Restrict`, `SetNull`) — never accept the default without thinking; dangerous cascades stay out.
- Use an explicit relation table for many-to-many that carries extra fields — never overload a pure join with payload columns.
- Index every foreign key — Prisma does not auto-index all relation columns on every provider.

```prisma
// WITH FK/PK — database enforces the relation
// schema/user.prisma
model User {
  id    String @id @default(uuid())
  email String @unique
  posts Post[]

  @@map("users")
}

// schema/post.prisma
model Post {
  id       String @id @default(uuid())
  title    String
  authorId String
  author   User   @relation(fields: [authorId], references: [id], onDelete: Cascade)

  @@index([authorId])
  @@map("posts")
}
```

```prisma
// WITHOUT FK/PK — Prisma emulates the relation, DB has no constraints
// schema/base.prisma
datasource db {
  provider     = "postgresql"
  url          = env("DATABASE_URL")
  relationMode = "prisma"
}

// schema/post.prisma
model Post {
  id       String @id @default(uuid())
  title    String
  authorId String // plain scalar — no FK constraint in the DB
  author   User   @relation(fields: [authorId], references: [id])

  @@index([authorId])
  @@map("posts")
}
// integrity (author must exist) enforced in code + transactions — see SKILL.md
```

## Indexes & Constraints

- Add `@@index` for frequently filtered/sorted fields and composite `@@index([a, b])` for common multi-field queries.
- Add `@@unique` / `@unique` for data that must be unique (email, slug) — enforce in the database, not only in code.
- Never duplicate or redundant indexes — one index per access pattern.
- Keep nullable/required aligned across schema, DTO validation, and application types — inconsistent nullability is a bug source.

## Migrations

- Name migrations after what they do (`add_user_role`, not `update`) — one logical change per migration.
- Schema changes that need existing rows rewritten ship with a data migration — never lose rows silently.
- Changing a field type or dropping a column requires a backfill/dual-write plan when the table has data.
- Never hand-edit `migration.sql` of an applied migration — revert with a new migration instead.
