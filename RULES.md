# Rules for TypeScript & NestJS

## TypeScript

- Use `strict: true` in `tsconfig.json`
- No `any` type — use `unknown` and narrow with type guards
- Use `interface` for object shapes, `type` for unions/intersections
- Prefer `readonly` for immutable data
- Avoid type assertions (`as`) — use type guards or `satisfies` instead
- Use `!` non-null assertion only when value is guaranteed (add comment why)
- Export types from barrel files (`index.ts`)

## NestJS

- Use CLI to generate: `nest g module`, `nest g controller`, `nest g service`
- One module per feature (e.g., `users/`, `auth/`, `orders/`)
- Controllers handle HTTP — no business logic in controllers
- Services handle business logic — no HTTP concerns in services
- Use `@nestjs/swagger` decorators on DTOs and controllers
- Inject dependencies via constructor — never instantiate manually
- Use `@InjectRepository()` for TypeORM/Prisma repositories
- Use guards for auth (`@UseGuards`), interceptors for logging/transformation
- Use `ConfigModule` for environment variables — no `process.env` in code
- Use `@nestjs/schedule` for cron jobs — no `setInterval`

## Types

- Every module must have a `types.ts` file for module-specific types
- Export all types from `types.ts` — import from there in other files
- Use `type.ts` for: enums, interfaces, type aliases, return types
- Do NOT put types in `dto/` — DTOs are for validation, types are for contracts
- Import pattern: `import { UserRole } from './types'`
- Put constants in `types.ts`: event names, URLs, status codes, config values
- Use `enum` for constants — no hardcoded strings in business logic

```typescript
// types.ts
export enum EventName {
  CREATED = 'user.created',
  UPDATED = 'user.updated',
  DELETED = 'user.deleted',
}

export enum ApiUrl {
  BASE = '/api/v1',
  USERS = '/api/v1/users',
}

export interface User { id: string; name: string; }
```

## Validation

- Handle ALL validation before controller and service
- Use global `ValidationPipe` in `main.ts` — reject invalid requests early
- Use `class-validator` decorators on DTOs
- Use `class-transformer` with `ValidationPipe` globally
- Validate nested objects with `@ValidateNested()`
- Use `@IsString()`, `@IsNumber()`, `@IsEmail()`, `@IsOptional()` etc.
- Controllers and services receive only valid data — no validation logic inside
- Use `WhitelistStrategy` + `ForbidNonWhitelisted` to reject unknown fields
- Use `TransformPipe` to auto-transform payloads to DTO instances

```typescript
// main.ts
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  }),
);
```

## Error Handling

- Handle errors with exceptions — use custom `AppException` classes
- Create `src/error/` directory with exception classes and global filter
- `errorCode` = uppercase snake_case (e.g., `RESOURCE_NOT_FOUND`)
- Always return consistent JSON: `{ statusCode, timestamp, path, message, errorCode?, details? }`
- Log unhandled (non-HttpException) errors with logger
- Create helper files for domain-specific error scenarios

```typescript
// app.exception.ts
export class AppException extends HttpException {
  constructor(
    message: string,
    statusCode: HttpStatus,
    public readonly errorCode?: string,
    public readonly details?: unknown,
  ) {
    super({ message, errorCode, details, timestamp: new Date().toISOString() }, statusCode);
  }
}

export class ResourceNotFoundException extends AppException {
  constructor(resourceType: string, identifier: string | number) {
    super(`${resourceType} with identifier ${identifier} not found`, HttpStatus.NOT_FOUND, 'RESOURCE_NOT_FOUND');
  }
}
```

```typescript
// main.ts
app.useGlobalFilters(new GlobalExceptionFilter(logger));
```

## Database

- Use Prisma or TypeORM — pick one, don't mix
- Keep migrations in `prisma/migrations` or `src/migrations`
- Use repositories or Prisma client for data access
- Never write raw SQL unless performance-critical (add comment why)
- Use `select` when only a subset of fields is required — don't over-fetch
- Avoid N+1 queries — use `include` or joins, not loops
- Run independent queries in parallel — don't `await` sequentially
- Use `findFirst` only when `findUnique` is possible
- Paginate `findMany` — never return unbounded results
- Use cursor pagination for large datasets, offset for small
- Always `orderBy` deterministic fields for pagination
- Handle Prisma errors — never leak raw Prisma errors to API responses
- Use transactions for multi-step operations — no partial writes
- Keep transaction scope small — no external calls inside transactions
- Race conditions on read-modify-write — use transactions or locks
- Add unique constraints for data that must be unique
- Soft-delete: always filter `deletedAt` in queries
- Avoid `include` for large relation collections — paginate or select

## Testing

- Use Jest (built into NestJS)
- Unit tests: `*.spec.ts` next to source files
- E2E tests: `test/*.e2e-spec.ts`
- Mock dependencies with `@nestjs/testing` `Test.createTestingModule()`
- Test controllers and services separately
- Use `supertest` for HTTP assertions in e2e

## Async & Concurrency

- Run independent async operations in parallel — don't `await` sequentially
- Always handle promise rejections — no fire-and-forget without error handling
- Add timeout for external service calls
- Use idempotency keys for retryable operations
- Retry with limits and exponential backoff
- Never retry non-idempotent operations unsafely
- Race conditions: use transactions or locks for read-modify-write

## Security

- Never hardcode secrets or credentials — use `ConfigModule`
- Never expose sensitive data in API responses
- Validate and sanitize all user input
- Prevent IDOR — check resource ownership
- Use parameterized queries — no raw SQL concatenation
- Validate file uploads: size, type, content
- Never trust client-provided file metadata
- Secure CORS configuration — no wildcard in production
- Rate limit sensitive endpoints (login, register, password reset)
- Never log sensitive data (passwords, tokens, PII)
- Use guards for auth — no manual auth checks in controllers

## API Design

- Consistent REST naming: plural nouns, HTTP verbs for actions
- Consistent error response format: `{ statusCode, message, errorCode }`
- Paginate all list endpoints — no unbounded responses
- Filter and limit query parameters
- Version API when making breaking changes
- Use appropriate HTTP status codes (201 for create, 204 for delete)
- Never expose internal implementation details in responses

## Observability

- Use structured logging (nestjs-pino)
- Never log sensitive data
- Propagate request/correlation IDs
- Add health check endpoints for critical dependencies
- Handle graceful shutdown — clean up connections
- Clean up timers, listeners, subscriptions
- Handle background job failures

## File Structure

```
andev-skill-agent/
├── .git/
├── package.json        # @thaiannguyen-05/opencode-rules
├── plugin.js           # trigger detection + GitHub fetch
├── README.md           # usage docs
└── RULES.md            # this file — rules for agents
```

### NestJS Project Structure

```
src/
├── app.module.ts
├── main.ts
├── config/
│   └── configuration.ts
├── common/
│   ├── guards/
│   ├── interceptors/
│   ├── pipes/
│   └── decorators/
├── error/
│   ├── app.exception.ts
│   ├── global.exception.ts
│   └── [domain]-error.helper.ts
├── modules/
│   ├── users/
│   │   ├── users.module.ts
│   │   ├── users.controller.ts
│   │   ├── users.service.ts
│   │   ├── types.ts
│   │   ├── dto/
│   │   └── entities/
│   ├── auth/
│   │   ├── auth.module.ts
│   │   ├── auth.controller.ts
│   │   ├── auth.service.ts
│   │   ├── types.ts
│   │   ├── dto/
│   │   └── entities/
│   └── orders/
│       ├── orders.module.ts
│       ├── orders.controller.ts
│       ├── orders.service.ts
│       ├── types.ts
│       ├── dto/
│       └── entities/
```

## Code Style

- Use Prettier for formatting
- Use ESLint with `@typescript-eslint` rules
- Max 300 lines per file — split if超过
- One export per file — no barrel exports in middle of file
- Sort imports: node builtins → external → internal → relative
- Use `path aliases` (`@/`) for clean imports
- Prefer `async/await` over `.then()` chains
- Use `enum` for constants — no hardcoded strings

```json
// .eslintrc
{
  "rules": {
    "max-lines": ["error", { "max": 300, "skipBlankLines": true, "skipComments": true }]
  }
}
```
