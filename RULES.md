# Rules for TypeScript & NestJS

## TypeScript

- Use `strict: true` in `tsconfig.json`
- No `any` type — use `unknown` and narrow with type guards
- Use `interface` for object shapes, `type` for unions/intersections
- Prefer `readonly` for immutable data
- Use `as const` for literal types
- Avoid type assertions (`as`) — use type guards or `satisfies` instead
- Use `!` non-null assertion only when value is guaranteed (add comment why)
- Export types from barrel files (`index.ts`)

## NestJS

- Use CLI to generate: `nest g module`, `nest g controller`, `nest g service`
- One module per feature (e.g., `users/`, `auth/`, `orders/`)
- Controllers handle HTTP — no business logic in controllers
- Services handle business logic — no HTTP concerns in services
- Use DTOs with `class-validator` for request validation
- Use `@nestjs/swagger` decorators on DTOs and controllers
- Inject dependencies via constructor — never instantiate manually
- Use `@InjectRepository()` for TypeORM/Prisma repositories
- Use guards for auth (`@UseGuards`), interceptors for logging/transformation
- Handle errors with exceptions (`NotFoundException`, `BadRequestException`, etc.)
- Use custom exception classes extending `AppException` (see Error Handling below)
- Use `ConfigModule` for environment variables — no `process.env` in code
- Use `@nestjs/schedule` for cron jobs — no `setInterval`

## Validation

- Use `class-validator` decorators on DTOs
- Use `class-transformer` with `ValidationPipe` globally
- Validate nested objects with `@ValidateNested()`
- Use `@IsString()`, `@IsNumber()`, `@IsEmail()`, `@IsOptional()` etc.

## Database

- Use Prisma or TypeORM — pick one, don't mix
- Keep migrations in `prisma/migrations` or `src/migrations`
- Use repositories or Prisma client for data access
- Never write raw SQL unless performance-critical (add comment why)

## Testing

- Use Jest (built into NestJS)
- Unit tests: `*.spec.ts` next to source files
- E2E tests: `test/*.e2e-spec.ts`
- Mock dependencies with `@nestjs/testing` `Test.createTestingModule()`
- Test controllers and services separately
- Use `supertest` for HTTP assertions in e2e

## Types

- Every module must have a `types.ts` file for module-specific types
- Export all types from `types.ts` — import from there in other files
- Use `type.ts` for: enums, interfaces, type aliases, return types
- Do NOT put types in `dto/` — DTOs are for validation, types are for contracts
- Import pattern: `import { UserRole } from './types'`

## File Structure

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
├── modules/
│   └── [feature]/
│       ├── [feature].module.ts
│       ├── [feature].controller.ts
│       ├── [feature].service.ts
│       ├── types.ts              ← types, enums, interfaces
│       ├── dto/
│       └── entities/
```

## Code Style

- Use Prettier for formatting
- Use ESLint with `@typescript-eslint` rules
- One export per file — no barrel exports in middle of file
- Sort imports: node builtins → external → internal → relative
- Use `path aliases` (`@/`) for clean imports
- Prefer `async/await` over `.then()` chains
- Use `enum` sparingly — prefer `as const` objects for lookup tables

## Error Handling

Create `src/error/` directory with:

### app.exception.ts — Base + Specific Exceptions

```typescript
import { HttpException, HttpStatus } from '@nestjs/common';

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

- Extend `AppException` for domain-specific errors
- Each exception gets: `message`, `statusCode`, `errorCode`, optional `details`
- `errorCode` = uppercase snake_case (e.g., `RESOURCE_NOT_FOUND`, `FILE_VALIDATION_FAILED`)

### global.exception.ts — Global Exception Filter

```typescript
@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    // Extract status, message, errorCode from HttpException
    // Log unhandled exceptions
    // Return: { statusCode, timestamp, path, message, errorCode?, details? }
  }
}
```

- Register in `main.ts`: `app.useGlobalFilters(new GlobalExceptionFilter(logger))`
- Always return consistent JSON shape: `{ statusCode, timestamp, path, message, errorCode?, details? }`

### storage-error.helper.ts — Helper Functions

```typescript
export function throwStorageError(error: unknown, context: string): never {
  const message = error instanceof Error ? error.message : context;
  throw new StorageUnavailableException(context, message);
}

export function isNotFoundError(error: unknown): boolean {
  return error instanceof Error && 'code' in error && (error.code === 'NotFound' || error.code === 'NoSuchKey');
}
```

- Use helper functions for repetitive error scenarios
- `throwStorageError` wraps storage errors with context
- `isNotFoundError` checks error codes without throwing
