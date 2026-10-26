---
name: nestjs
description: NestJS backend rules — Fastify platform, module structure, zod validation. Use when building or reviewing NestJS code.
---
# NestJS Architecture

## Purpose
Structure NestJS applications with module-based architecture — domain modules, shared modules, dynamic modules, monorepo projects, and provider scoping.

## Agent Protocol

### Trigger
User request includes: `NestJS module structure`, `NestJS architecture`, `NestJS project layout`, `NestJS DI`, `NestJS modules`, `NestJS monorepo`, `NestJS providers`.

### Input Context
- NestJS version (10+)
- Architecture style (modular, monorepo, microservices)
- Database (TypeORM, Prisma, MikroORM, Mongoose)
- Transport (HTTP, WebSocket, TCP, RabbitMQ)

### Output Artifact
Module structure, provider registration, module exports, monorepo layout, DI setup.

### Response Format
Produce artifact directly. No preamble, no postamble, no explanations.

### Completion Criteria
- Root module imports feature modules
- Each domain has its own module with controllers, services, repositories
- Modules export only what other modules need
- Global modules registered sparingly (shared infra only)
- Dynamic modules configured with forRoot/forFeature

### Max Response Length
4096 tokens

# NestJS Skill

## Platform

- Use Fastify — never Express.
- Bootstrap with `FastifyAdapter` typed as `NestFastifyApplication` — never `NestFactory.create()` with the default Express platform.
- Pass `{ trustProxy: true }` so client IPs stay correct behind a reverse proxy.
- Never use Express-specific APIs (`@Res()` passthrough, `express-*` middleware) — use Fastify equivalents and `app.register()` plugins.
- Configure CORS, body-parser limits, and global prefix on the Fastify instance in `main.ts`.

```typescript
// main.ts
import { NestFactory } from '@nestjs/core';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';

const app = await NestFactory.create<NestFastifyApplication>(
  AppModule,
  new FastifyAdapter({ trustProxy: true }),
);
```

## common/guards

- Put only shared guards in `src/common/guards/` — auth, ownership checks reused across features.
- Feature-specific guards belong in `module/{features}/guards/` — never in `common`.
- Guards decide access only — no business logic, no DB writes inside guards.
- Extract request props into explicitly typed locals (e.g., `const user: User | undefined = req.user`) — never branch on `req.*` inline; untyped access is unsafe.
- Apply via `@UseGuards()` — never call guards manually in controllers or services.

```typescript
// common/guards/auth.guard.ts
import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { FastifyRequest } from 'fastify';
import { User } from '../type';
import { IS_PUBLIC_KEY } from '../decorator/public.decorator';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;
    const req = context.switchToHttp().getRequest<FastifyRequest>();
    const user: User | undefined = req.user;
    if (!user) throw new UnauthorizedException();
    return true;
  }
}

// usage: @UseGuards(AuthGuard)
```

## common/interceptor

- Put only shared interceptors in `src/common/interceptor/` — logging, transformation, timeout.
- Never put business logic inside interceptors.
- Keep interceptors thin — one responsibility per interceptor.

```typescript
// common/interceptor/logging.interceptor.ts
import { CallHandler, ExecutionContext, Injectable, Logger, NestInterceptor } from '@nestjs/common';
import { FastifyRequest } from 'fastify';
import { Observable, tap } from 'rxjs';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('HTTP');

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = context.switchToHttp().getRequest<FastifyRequest>();
    const start = Date.now();
    return next.handle().pipe(
      tap(() => this.logger.log(`${req.method} ${req.url} ${Date.now() - start}ms`)),
    );
  }
}
```

## common/decorator

- Put only shared decorators in `src/common/decorator/` — param decorators, metadata helpers.
- Mark public routes with `@Public()` — AuthGuard skips them via Reflector; never bypass the guard manually.
- Never put validation logic inside decorators that belongs in `dto/`.
- Never put business logic inside decorators.

```typescript
// common/decorator/current-user.decorator.ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { FastifyRequest } from 'fastify';
import { User } from '../type';

export const CurrentUser = createParamDecorator(
  (key: keyof User | undefined, ctx: ExecutionContext) => {
    const req = ctx.switchToHttp().getRequest<FastifyRequest>();
    const user: User | undefined = req.user;
    return key ? user?.[key] : user;
  },
);

// usage: handler(@CurrentUser() user) or handler(@CurrentUser('id') id: string)
```

```typescript
// common/decorator/public.decorator.ts
import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

// usage: @Public() on a controller or route handler to skip AuthGuard
```

## common/exception

- All exceptions and filters live in `src/common/exception/` — replaces the old `src/error/` location.
- Define custom `AppException` classes here — never throw raw `Error` for domain failures.
- `errorCode` = uppercase snake_case (e.g., `RESOURCE_NOT_FOUND`).
- Always return consistent JSON: `{ statusCode, timestamp, path, message, errorCode?, details? }`.
- Log unhandled (non-HttpException) errors with logger — never leak internal details to responses.
- Feature helpers (e.g., `[domain]-error.helper.ts`) live here, not inside features.

```typescript
// common/exception/app.exception.ts
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
    super(
      `${resourceType} with identifier ${identifier} not found`,
      HttpStatus.NOT_FOUND,
      'RESOURCE_NOT_FOUND',
    );
  }
}
```

```typescript
// common/exception/global-exception.filter.ts
import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import { FastifyReply } from 'fastify';

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('Exception');

  catch(exception: unknown, host: ArgumentsHost) {
    const reply = host.switchToHttp().getResponse<FastifyReply>();
    if (exception instanceof HttpException) {
      return reply.status(exception.getStatus()).send(exception.getResponse());
    }
    this.logger.error(exception);
    return reply.status(500).send({
      statusCode: 500,
      message: 'Internal server error',
      timestamp: new Date().toISOString(),
    });
  }
}

// main.ts: app.useGlobalFilters(new GlobalExceptionFilter());
```

## common/middleware

- Put only HTTP plumbing in `src/common/middleware/` — req/res preprocessing, correlation IDs.
- Write them as Fastify plugins/hooks registered via `app.register()` — never Express-style `(req, res, next)` middleware.
- Never put business logic inside middleware.
- Prefer guards/interceptors over middleware when the concern fits them.

```typescript
// common/middleware/correlation-id.plugin.ts
import { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';

export async function correlationIdPlugin(app: FastifyInstance) {
  app.addHook('onRequest', async (req) => {
    req.headers['x-correlation-id'] ??= randomUUID();
  });
}

// main.ts: await app.register(correlationIdPlugin);
```

## module/infrastructures (abstract)

- `module/infrastructures/` holds tech adapters only — no business logic, no domain types.
- Subfolders below are examples, not mandates — never hardcode the tech choice:
  - `TypeOrm/` = example relational persistence adapter (entities, repositories, migrations glue).
  - `message/` = example messaging adapter (producers, consumers, topic/queue names).
- Name a subfolder after the adapter role — one folder per external system.
- Adapters implement interfaces owned by features — features depend on abstractions, not on adapter internals.
- Never import `module/{features}/` code into `infrastructures/` — dependency points inward to the abstraction.
- Never let controllers or services import adapter internals directly — go through DI providers/tokens.
- Never share state between adapters — no cross-imports between `TypeOrm/` and `message/`.
- Write adapter code only after the tech is chosen — no placeholder implementations before the decision.

## References

- Feature slice layout, types, guards, dto, service, controller rules: `references/nestjs-module.md`.
- Unit, integration, E2E testing strategies, TestContainers, mocking: `references/nestjs-testing.md`.
