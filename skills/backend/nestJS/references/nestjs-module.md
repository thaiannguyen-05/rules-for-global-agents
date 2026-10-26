# NestJS Module Structure Rules

## Layout

- Follow this tree exactly — no extra nesting, no renamed folders.
- `src/common/` holds shared code only — never feature-specific code.
- `src/module/` holds `infrastructures/` + one folder per feature.

```
src/
├── common/
│   ├── guards/
│   ├── interceptor/
│   ├── decorator/
│   ├── exception/
│   ├── middleware/
│   └── type.ts
└── module/
    ├── infrastructures/
    │   ├── TypeOrm/
    │   └── message/
    └── {features}/
        ├── dto/
        ├── guards/
        ├── type.ts
        ├── index.ts
        ├── {features}.service.ts
        ├── {features}.controller.ts
        └── {features}.module.ts
```

## common/type.ts (shared)

- Put only cross-feature types in `src/common/type.ts` — enums, interfaces, aliases used by 2+ features.
- Never put feature-private types in `src/common/type.ts` — they belong in `module/{features}/type.ts`.
- Never import from `module/{features}/type.ts` into `src/common/type.ts` — `common` never depends on `module/`.
- Use `enum` for shared constants — no hardcoded strings in business logic.

## Global setup (lives in `../SKILL.md`)

- `common/interceptor`, `common/decorator`, `common/exception`, `common/middleware`, and `module/infrastructures/` rules are global — see `../SKILL.md`, not here.

## module/{features}

- One folder per feature (e.g., `users/`, `auth/`, `orders/`) — self-contained slice.
- Never place feature code outside its folder — except shared code in `src/common/` and adapters in `infrastructures/`.
- Never import deep paths across features (e.g., `../orders/type`) — import via the feature barrel (see `index.ts` below).

### dto/

- DTOs are zod schemas only — define `z.object(...)` in `dto/`, export the schema + `z.infer` type, no business logic.
- Do NOT use `class-validator` decorators or `class-transformer` — zod replaces both (parsing + coercion via `z.coerce`).
- Do NOT put shared types or constants in `dto/` — shared types belong in `type.ts`, constants in `enum`; derive DTO types via `z.infer`.
- Validate nested objects with nested schemas — call `.strict()` to reject unknown fields.

```typescript
// module/users/dto/create-user.dto.ts
import { z } from 'zod';

export const CreateUserSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
  address: AddressSchema,
}).strict();

export type CreateUserDto = z.infer<typeof CreateUserSchema>;
```

### guards/

- Put feature-specific guards here — guards used by one feature only.
- Promote to `src/common/guards/` the moment a second feature needs it.
- Same guard rules as global (`../SKILL.md`): access decisions only, applied via `@UseGuards()`.

### type.ts + index.ts (private + barrel)

- `module/{features}/type.ts` holds feature-private types — enums, interfaces, return types for this feature only.
- Every feature must re-export its private types from its own `index.ts` barrel.
- External features import via the barrel — never via a deep `type.ts` path.
- Internal files import from `./type` — avoid self-importing through `./index` to prevent cycles.

```typescript
// module/users/type.ts
export enum UserRole { ADMIN = 'admin', USER = 'user' }
export interface User { id: string; name: string; }
```

```typescript
// module/users/index.ts
export * from './type';
export * from './users.service';
export * from './users.module';
```

### {features}.service.ts

- Services hold business logic only — no HTTP, no req/res, no raw adapter imports.
- Inject dependencies via constructor — never instantiate manually.
- Run independent async work in parallel — never `await` sequentially when parallel is possible.
- Use transactions for multi-step writes — no partial writes, keep scope small, no external calls inside.

```typescript
// module/users/users.service.ts
import { Injectable } from '@nestjs/common';
import type { CreateUserDto } from './dto/create-user.dto';
import type { User } from './type';

@Injectable()
export class UsersService {
  async create(dto: CreateUserDto): Promise<User> {
    /* business logic only — persistence arrives via DI after the tech decision */
    void dto;
    throw new Error('not implemented');
  }

  async getById(id: string): Promise<User> {
    /* ... */
    void id;
    throw new Error('not implemented');
  }
}
```

### {features}.controller.ts

- Controllers handle HTTP only — routing, status codes, delegation to the service.
- No business logic, no DB access, no adapter imports in controllers.
- Controllers and services receive only valid data — all validation happens in `dto/` schemas + global `ZodValidationPipe` before them.

```typescript
// module/users/users.controller.ts
import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import type { CreateUserDto } from './dto/create-user.dto';
import { UsersService } from './users.service';

@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Post()
  create(@Body() dto: CreateUserDto) {
    return this.users.create(dto);
  }

  @Get(':id')
  getById(@Param('id') id: string) {
    return this.users.getById(id);
  }
}
```

### {features}.module.ts

- Modules wire only — `imports`, `providers`, `controllers`, `exports`, no logic.
- Register feature providers here; export what other features need via the barrel.
- Import direction is one-way — the sample below depends on users, never the reverse.

```typescript
// module/users/users.module.ts
import { Module } from '@nestjs/common';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
```

```typescript
// module/orders/orders.module.ts — depends on users, never the reverse
import { Module } from '@nestjs/common';
import { UsersModule } from '../users';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';

@Module({
  imports: [UsersModule],
  controllers: [OrdersController],
  providers: [OrdersService],
})
export class OrdersModule {}
```

### Cross-module imports (no circular DI)

- Keep the import graph one-way — if A imports B, B never imports A.
- Code needed by both sides moves to a third module (or `src/common/`) that both import.
- Import the dependency's barrel (`../users`), never reach into its internals.
- `forwardRef` only as last resort — wrap both module imports and both injections, and comment why the cycle cannot be broken.

```typescript
// module/orders/orders.service.ts — consumes the exported provider, no cycle
import { Injectable } from '@nestjs/common';
import { UsersService } from '../users';

@Injectable()
export class OrdersService {
  constructor(private readonly users: UsersService) {}

  async create(userId: string) {
    const user = await this.users.getById(userId);
    /* ... */
  }
}

// last resort only — avoid if possible:
// @Module({ imports: [forwardRef(() => BModule)] }) on BOTH modules, and
// constructor(@Inject(forwardRef(() => BService)) ...) on BOTH sides, with a comment why.
```
