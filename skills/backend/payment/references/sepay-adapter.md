# Sepay adapter reference (default PaymentGateway implementation)

Adapter location: `payment/sepay/`. Implements `PaymentGateway` from `references/payment-gateway-interface.md`.

## Constants

```typescript
export const SEPAY = {
  BASE_URL: 'https://pay.sepay.vn',
  CHECKOUT_PATH: '/v1/checkout/init',
  OPERATION: 'PURCHASE',
  TIMEOUT_MS: 5000,
  WEBHOOK_SECRET_HEADER: 'x-secret-key',
};
export const SEPAY_NOTIFICATION_TYPE = { ORDER_PAID: 'ORDER_PAID', TRANSACTION_VOID: 'TRANSACTION_VOID' };
export const SEPAY_SUCCESS_ORDER_STATUSES = ['CAPTURED','COMPLETED','PAID','SUCCESS'];
export const SEPAY_SUCCESS_TRANSACTION_STATUSES = ['APPROVED','SUCCESS','PAID','COMPLETED','CAPTURED'];
```

## Checkout signing

Field order (do not reorder; skip absent optionals like `payment_method`):

```typescript
export const SEPAY_SIGN_FIELDS = [
  'order_amount','merchant','currency','operation','order_description',
  'order_invoice_number','customer_id','payment_method','success_url','error_url','cancel_url',
] as const;
```

```typescript
private signCheckout(payload, secret): string {
  const signingString = SEPAY_SIGN_FIELDS
    .filter(f => payload[f] !== undefined && payload[f] !== null && payload[f] !== '')
    .map(f => `${f}=${payload[f]}`).join(',');
  return createHmac('sha256', secret).update(signingString, 'utf8').digest('base64');
}
```

`createCheckout` returns `{ kind: 'form', action, method: 'POST', fields }` (Sepay is a browser form POST, no server-side POST / no checkout_url).

## Return token (browser redirect)

```typescript
const SEPAY_RETURN_TOKEN_TTL_S = 30 * 60;
private buildReturnToken(orderId, userId): string { /* HMAC orderId.userId.exp, base64url, exp.sig */ }
private verifyReturnToken(order, token): void { /* split, exp check, timingSafeEqual */ }
```

## initCheckout (adapter)

Acquires checkout lock (per order) via core-provided lock service or adapter-local; loads order via `OrderService.getOwnerOrder`; if PAID → ConflictException; builds return URLs with `{orderId}`/query/suffix + token; signs form; `orderService.saveStatus(order.id, { paymentMethod: 'SEPAY' })`; returns CheckoutResult.

## Webhook auth (fail-closed)

```typescript
export function assertSepayWebhookSecret(secret, secretKeyHeader): void {
  if (!secret || secret === 'REPLACE_ME') throw new UnauthorizedException('Webhook secret not configured');
  if (!secretKeyHeader) throw new UnauthorizedException('Missing webhook secret');
  const a = Buffer.from(secretKeyHeader,'utf8'); const b = Buffer.from(secret,'utf8');
  if (a.length !== b.length || !timingSafeEqual(a,b)) throw new UnauthorizedException('Invalid webhook secret');
}
```

## applyIpn (settle mapping)

- Validate customer_id, currency, tx/order amounts round to `order.finalPrice`.
- Map `notification_type`: `ORDER_PAID` → check success markers → PAID or FAILED; `TRANSACTION_VOID` → CANCELLED; else 400.
- Terminal immutability: if already terminal, ack idempotent.
- On PAID → `orderService.settlePaid(...)`; on FAILED/CANCELLED → `orderService.settleFailed(...)`.
- Duplicate Sepay reference → Prisma `P2002` → `ConflictException('Duplicate Sepay reference')`.

## doHandleWebhook

- `assertSepayWebhookSecret(secret, header)`.
- `invoiceNumber = dto.order.order_invoice_number` (required).
- Replay guard: timestamp seconds; reject if older than 5 min; accept future.
- Unified settle lock per order (`order:lock:idempotency-key:<orderId>:<orderId>`).
- Load order, applyIpn, revoke idempotency key on terminal. Return WebhookResult.

## Browser return (adapter)

- Verify return token (exp 30 min). success/error are read-only; cancel on PENDING → `orderService.cancelOrder`. Never marks PAID, never downgrades. Revoke idempotency key. Return WebhookResult.

## Sync (adapter)

- Delegates to `orderService.syncOrder` (lazy expire). Adapter may optionally query Sepay PG; default IPN remains sole PAID path.

## Webhook DTO

See `SepayWebhookDto` with nested `order`/`transaction`/`customer`, `timestamp` int, `notification_type`, `agreement` optional (whitelisted for real IPN). Contract mirrors SePay ORDER_PAID notification verbatim.

## Env (adapter)

```
SEPAY_MERCHANT=...
SEPAY_SECRET_KEY=...          # HMAC secret + webhook auth
SEPAY_BASE_URL=https://pay.sepay.vn
SEPAY_SUCCESS_URL=https://.../payment/sepay/success   # or {orderId} placeholder / REST suffix
SEPAY_ERROR_URL=https://.../payment/sepay/error
SEPAY_CANCEL_URL=https://.../payment/sepay/cancel
```

## HTML checkout (optional)

Controller/adapter can render an auto-submitting `<form>` when `?format=html`. Escape all values.
