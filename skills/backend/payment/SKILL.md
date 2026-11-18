---
name: payment
description: Payment & order lifecycle — gateway interface (swappable), Order state machine, checkout, webhook, browser return, sync poll, expiry cron, locking & idempotency. Sepay included as default adapter. Use when building or reviewing payment/order code.
---

# Payment Skill

## Purpose

Implement and review the payment/order subsystem for cinema ticket booking with a **gateway-agnostic core**: define a `PaymentGateway` interface first, then plug a concrete adapter (Sepay by default, or MoMo/VNPay/etc.). The core owns the Order lifecycle, state machine, locking and idempotency; the adapter owns gateway-specific signing, webhook verification and payload mapping. Only the gateway's IPN/webhook may move an Order to `PAID`.

## Agent Protocol

### Trigger
User request includes: `payment`, `order`, `payment gateway`, `payment interface`, `sepay`, `checkout`, `webhook`, `IPN`, `idempotency`, `order expiry`, `ticket booking payment`.

### Input Context
- Gateway choice is made **after** the `PaymentGateway` interface is defined. Default adapter: Sepay.
- Storage: PostgreSQL via Prisma + Redis for locks/idempotency.
- Framework: NestJS (assumed). Adapt DI if different.

### Output Artifact
`PaymentGateway` interface + token, gateway-agnostic Order service, concrete adapter module, locking/idempotency helpers, expiry cron, metrics hooks.

### Response Format
Produce artifacts directly. No preamble. Prefer editing existing files; keep secrets as env placeholders. Always define the interface before implementing a gateway.

### Completion Criteria
- `PaymentGateway` interface exists and is the only dependency of the payment core.
- Order status transitions follow `ALLOWED_TRANSITIONS`; terminal states immutable.
- Only the gateway webhook may set `PAID`; browser return never marks `PAID` and never downgrades.
- Checkout returns a signed form / URL produced by the adapter (core never signs).
- Webhook verification is adapter-specific and fail-closed.
- Distributed lock serializes per-ticket creation and per-order settle; idempotency cache short-circuits retries.
- Expiry cron frees `PROCESSING` ticket back to `AVAILABLE`.
- Swapping gateways requires only a new adapter + DI binding, no core changes.

### Max Response Length
4096 tokens

# Rules

## Gateway abstraction (define first)

- Create `PaymentGateway` interface in `payment/` module **before** choosing a concrete gateway. The core (`OrderService`, `PaymentController`) depends only on this interface, injected via a token (`PAYMENT_GATEWAY`).
- Adapter (e.g. `SepayGateway`) implements the interface and lives in its own subfolder (`payment/sepay/`). Gateway-specific constants, DTOs, HMAC signing and verification stay in the adapter, never in the core.
- Gateway is selected by configuration/DI binding, so swapping gateways needs no core changes.
- Interface contract (gateway-agnostic result types):

```typescript
interface PaymentGateway {
  createCheckout(order: PaymentOrder, user: User): Promise<CheckoutResult>;
  // { action, method, fields } or { redirectUrl } — adapter decides
  handleWebhook(payload: unknown, headers: Record<string,string>): Promise<WebhookResult>;
  // { orderId, status, idempotent }
  handleBrowserReturn(orderId: string, outcome: 'success'|'error'|'cancel', token?: string): Promise<WebhookResult>;
  syncOrder(orderId: string, userId: string): Promise<WebhookResult>;
}
```

- Result types (`CheckoutResult`, `WebhookResult`) are generic; adapter maps gateway payloads to them.
- Webhook route is generic: controller passes raw payload + headers to `gateway.handleWebhook`; adapter does auth + mapping.

## Domain model (gateway-agnostic)

- **Order**: a User's request to acquire one Ticket (1-1, FK `Order.ticketId`). Statuses: `PENDING → {PAID, FAILED, EXPIRED, CANCELLED}`. Terminal states immutable.
- **Payment**: settlement recorded on `Order` itself (`paidAmount`, `paymentMethod`, `callbackPayload`). No separate Payment table.
- **Ticket**: `AVAILABLE → PROCESSING` on order creation; `PROCESSING → BOOKED` on PAID; `PROCESSING → AVAILABLE` on FAILED/EXPIRED/CANCELLED.
- Only the gateway webhook may move Order to `PAID`/`FAILED`. Browser return is read-only except cancel PENDING→CANCELLED.
- `ALLOWED_TRANSITIONS` is the single source of truth; `updateOrder` must check it.

## Order creation

- Create under a per-ticket Redis lock (global) so concurrent buyers serialize.
- Idempotency: client `Idempotency-Key` (validated) or fallback to `ticketId`. Cache `lockResource -> orderId` in Redis (5 min).
- On lock contention → `ConflictException('Order creation is already in progress for this ticket')`.
- Inside transaction: delegate validation to transaction-aware service methods (pass `tx` in). Keep the `$transaction` callback thin (orchestration only). Then set ticket PROCESSING; delete stale terminal orders (EXPIRED/FAILED/CANCELLED) — required because `Order.ticketId` is `@unique` (one Order per Ticket); create Order with `expiresAt = now + 15 min`.
- On Prisma `P2002` → `ConflictException`.
- After creation, cache ids (best effort).

## State machine & settlement

- `settlePaid` / `settleFailed` / `cancelOrder` / `expireOrder` live in `OrderService` (core), called by the gateway adapter after it validates & maps the payload.
- `settlePaid`: Order→PAID + Ticket→BOOKED, then revoke idempotency key.
- `settleFailed`/`cancel`/`expire`: Order→terminal + free Ticket, then revoke idempotency key.
- Terminal states immutable: if already terminal and different status → return idempotent, do not mutate.

## Transactions

- Pass `tx` (Prisma `TransactionClient`) down into service methods; those methods own validation and throw domain exceptions. Keep `$transaction` callbacks thin (orchestration only) — no re-validation in the caller.
- Multi-step writes (settle paid/failed, cancel, expire) run inside `$transaction`; no partial writes.
- No external calls inside transactions.
- Avoid N+1 in bulk jobs: select all needed columns (incl. userId) up front. Revoke/cache I/O can run in parallel (`Promise.all`) when N is modest; for very large N prefer a Redis pipeline/batch to avoid thousands of concurrent commands. Never do per-row DB lookups.

## Locking & idempotency

- Redis Redlock (`runExclusive`) with TTLs: create 5s, checkout 10s, webhook 10s, update 5s.
- `runExclusive` returns `null` on contention; Redis failures → `ServiceUnavailableException` (503).
- Unified settle lock per order via `IDEMPOTENCY_KEYS.ORDER_SETTLE_LOCK(orderId)` (`order:lock:settle:<orderId>`), shared by webhook, browser return, sync poll and `updateOrder` to serialize all mutations of one Order (prevents PENDING→CANCELLED vs PENDING→PAID races). Create-order uses `IDEMPOTENCY_KEYS.ORDER_CREATE_LOCK(ticketId)` (`order:lock:create:<ticketId>`) because the Order does not exist yet. Client-facing `Idempotency-Key` stays per request and is never reused as a lock resource. Avoid calling a two-arg key builder with identical args (`ORDER_LOCK_IDEMPOTENCY_KEY(id, id)`) — define a dedicated single-arg builder instead.
- Revoke idempotency key on terminal settlement.

## Checkout (core delegates to adapter)

- Core acquires checkout lock (per order), loads order, checks not PAID, then calls `gateway.createCheckout(order, user)` and persists `paymentMethod`.
- Adapter builds gateway-specific signed payload and returns `CheckoutResult` (`action`, `method`, `fields` or `redirectUrl`).
- On already PAID → `ConflictException`. On contention → `ConflictException('Checkout already in progress for this order')`.

## Webhook (IPN)

- Generic endpoint `POST /payment/webhook` (or gateway-prefixed), `@Public()`, throttled. Controller forwards raw payload + headers to `gateway.handleWebhook`.
- Adapter verifies auth (fail-closed), validates amount/currency/customer, replay-guards timestamp, maps to Order status, calls core settle.
- Only adapter may trigger `settlePaid`/`settleFailed`.
- Duplicate gateway reference → `ConflictException('Duplicate ... reference')`.

## Browser return

- Generic endpoints per outcome; adapter verifies signed return token, returns status. cancel on PENDING → CANCELLED via core.
- Never marks PAID, never downgrades PAID.

## Sync poll

- Authenticated, ownership-checked; core returns DB status and lazily expires. Adapter may optionally query gateway; core stays gateway-agnostic (default: IPN is sole PAID path).

## Expiry

- Cron every 5 min acquires global lock, `expireDueOrders()`: bulk PENDING→EXPIRED + PROCESSING→AVAILABLE. Revoke idempotency keys. Log count.

## Metrics

- `app_payment_orders_total{result}`, `app_payment_checkout_total{result}`, `app_payment_webhook_total{result}`, `app_payment_sync_total{result}`.
- Cron: start/success/skipped/failed, expired count.

## Env (core)

```
PAYMENT_GATEWAY=sepay   # selects adapter binding
```

Gateway-specific env lives in the adapter (see `references/sepay-adapter.md`).

## Troubleshooting

- Swapping gateway: implement `PaymentGateway`, bind token, add env. No core changes.
- Webhook 401: adapter auth failed — check adapter secret env.
- Ticket stuck PROCESSING: expiry cron or sync poll frees it.
- Lock contention 409 vs Redis down 503.

## Conventions

- If a request body or method input has more than 2 properties, wrap it in a DTO; otherwise positional params are acceptable.
- The Prisma transaction client (`tx`) is always passed as a separate parameter, never folded into a DTO.
- DTOs live in `dto/` and are validated with `class-validator`/`class-transformer`.

## References

- Interface contract & DI wiring: `references/payment-gateway-interface.md`.
- Order lifecycle, state machine, locking, expiry: `references/order-lifecycle.md`.
- Sepay adapter (default): `references/sepay-adapter.md`.
