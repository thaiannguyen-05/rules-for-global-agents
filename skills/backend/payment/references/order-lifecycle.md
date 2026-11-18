# Order lifecycle reference

## Type & state machine

```typescript
// order/type.ts
export type PaymentOrder = Order; // Prisma Order
export const ALLOWED_TRANSITIONS: Record<OrderStatus, readonly OrderStatus[]> = {
  [OrderStatus.PENDING]: [OrderStatus.PAID, OrderStatus.FAILED, OrderStatus.EXPIRED, OrderStatus.CANCELLED],
  [OrderStatus.PAID]: [],
  [OrderStatus.FAILED]: [],
  [OrderStatus.EXPIRED]: [],
  [OrderStatus.CANCELLED]: [],
};
```

## OrderService.createOrder

```typescript
async createOrder(dto: CreateOrderDto & { userId; idempotencyKey? }): Promise<PaymentOrder> {
  const idem = normalizeIdempotencyKey(dto.idempotencyKey) ?? dto.ticketId;
  const lockResource = IDEMPOTENCY_KEYS.ORDER_CREATE_LOCK(dto.ticketId);

  // idempotency cache check
  const existingId = await redis.get(lockResource);
  if (existingId) { ... return existing if PENDING/PAID and same user ... }

  const order = await redisLockService.runExclusive<PaymentOrder>(lockResource, PAYMENT_LOCK_TTL_MS.CREATE, async () => {
    return prismaService.$transaction(async (tx) => {
      // Validation (not-found, booked, cancelled, price mismatch, showtime
      // ended, active order) is encapsulated in getTicketById(id, tx) — pass
      // tx and let it throw. Keep this callback thin (orchestration only).
      const ticket = await ticketService.getTicketById(dto.ticketId, tx);
      if (ticket.ticketStatus === TicketStatus.AVAILABLE) await ticketService.updateTicketStatus(ticket.id, TicketStatus.PROCESSING, tx);
      // Order.ticketId is @unique (one Order per Ticket), so a new order for
      // a ticket that previously had a terminal order (EXPIRED/FAILED/CANCELLED)
      // requires deleting those stale rows first. Active (PENDING/PAID) orders
      // are already blocked by the active-order check above.
      await tx.order.deleteMany({ where: { ticketId: dto.ticketId, status: { in: [EXPIRED, FAILED, CANCELLED] } } });
      // replay cache check inside tx
      ...
      return await tx.order.create({ data: { ticketId, userId, finalPrice: ticket.price, currency: dto.currency ?? 'VND', expiresAt: new Date(Date.now() + 15*60*1000) } });
    });
  });

  if (order === null) throw new ConflictException('Order creation is already in progress for this ticket');

  // cache (best effort)
  await redis.set(lockResource, order.id, 'EX', 5*60);
  await redis.set(`idemp:order:${order.id}`, idem, 'EX', 5*60);
  return order;
}
```

## updateOrder

```typescript
async updateOrder(id, dto) {
  const result = await redisLockService.runExclusive<PaymentOrder>(
    IDEMPOTENCY_KEYS.ORDER_SETTLE_LOCK(id),
    PAYMENT_LOCK_TTL_MS.UPDATE,
    async () => prismaService.$transaction(async (tx) => {
      const current = await tx.order.findUnique({ where: { id } });
      if (!current) throw new NotFoundException('Order not found');
      if (current.status === dto.status) return current;
      if (!ALLOWED_TRANSITIONS[current.status].includes(dto.status)) throw new ConflictException(`Cannot transition ...`);
      return await tx.order.update({ where: { id }, data: { status: dto.status } });
    }),
  );
  if (result === null) throw new ConflictException('Order update is already in progress for this order');
  return result;
}
```

## Settlement helpers

```typescript
async settlePaid(order: PaymentOrder, data: SettlePaymentData): Promise<PaymentOrder> {
  const updated = await prismaService.$transaction(async (tx) => {
    const paid = await tx.order.update({ where: { id: order.id }, data: { status: PAID, sepayOrderId, sepayTransactionId, paymentMethod, paidAmount, callbackPayload } });
    await ticketService.updateTicketStatus(order.ticketId, TicketStatus.BOOKED, tx);
    return paid;
  });
  await revokeIdempotencyKey({ orderId: updated.id, userId: order.userId });
  return updated;
}

async settleFailed(order, data, nextStatus): Promise<PaymentOrder> { ... status update + ticket PROCESSING->AVAILABLE ... }
async cancelOrder(order): Promise<PaymentOrder> { ... CANCELLED + free ticket ... }
async expireOrder(order): Promise<PaymentOrder> { ... EXPIRED + free ticket ... }
```

## syncOrder (lazy expire)

```typescript
async syncOrder(orderId, userId) {
  return redisLockService.runExclusive(..., async () => {
    const order = await getOwnerOrder({ orderId, userId });
    if (order.status === PENDING && order.expiresAt?.getTime() <= Date.now()) {
      const updated = await expireOrder(order);
      return { orderId: updated.id, status: updated.status, idempotent: false };
    }
    return { orderId: order.id, status: order.status, idempotent: true };
  }).then(r => { if (r === null) throw new ConflictException(...); return r; });
}
```

## expireDueOrders (cron)

```typescript
async expireDueOrders(): Promise<number> {
  // Select userId up front to avoid per-order DB lookups in the revoke loop.
  const due = await prismaService.order.findMany({
    where: { status: PENDING, expiresAt: { lte: new Date() } },
    select: { id: true, ticketId: true, userId: true },
  });
  if (due.length === 0) return 0;
  const result = await prismaService.$transaction(async (tx) => {
    const r = await tx.order.updateMany({
      where: { id: { in: due.map((o) => o.id) }, status: PENDING },
      data: { status: EXPIRED },
    });
    await tx.ticket.updateMany({
      where: { id: { in: due.map((o) => o.ticketId) }, ticketStatus: PROCESSING },
      data: { ticketStatus: AVAILABLE },
    });
    return r;
  });
  // Revoke in parallel; revokeIdempotencyKey is best-effort and swallows errors.
  await Promise.all(due.map((o) => revokeIdempotencyKey({ orderId: o.id, userId: o.userId })));
  return result.count;
}
```

## Types (order/type.ts)

```typescript
export type RevokeIdempotencyKeyDto = { orderId: string; userId?: string };
export type SettlePaymentData = {
  sepayOrderId: string;
  sepayTransactionId: string;
  paymentMethod: string;
  paidAmount: number;
  callbackPayload: unknown;
};
```

## revokeIdempotencyKey

```typescript
// dto: RevokeIdempotencyKeyDto = { orderId: string; userId?: string }
async revokeIdempotencyKey(dto: RevokeIdempotencyKeyDto): Promise<void> {
  const idem = await redis.get(`idemp:order:${dto.orderId}`);
  if (!idem) return;
  const uid =
    dto.userId ??
    (await prismaService.order.findUnique({
      where: { id: dto.orderId },
      select: { userId: true },
    }))?.userId;
  if (uid) {
    await redis.del(`idemp:payment:create:${uid}:${idem}`, `idemp:order:${dto.orderId}`);
  } else {
    await redis.del(`idemp:order:${dto.orderId}`);
  }
}
```

Callers pass the typed dto: `revokeIdempotencyKey({ orderId: updated.id, userId: order.userId })`.

## Locks & idempotency keys (constant.ts)

```typescript
export const PAYMENT_LOCK_TTL_MS = { CREATE: 5000, CHECKOUT: 10000, WEBHOOK: 10000, UPDATE: 5000 };

export const IDEMPOTENCY_KEYS = {
  // Per-ticket lock for order creation (concurrent buyers serialize).
  ORDER_CREATE_LOCK: (ticketId) => `order:lock:create:${ticketId}`,
  // Unified settle lock per order (webhook/browser/sync/update).
  ORDER_SETTLE_LOCK: (orderId) => `order:lock:settle:${orderId}`,
  // Client idempotency cache (per user + client key).
  PAYMENT_IDEMPOTENCY_KEY: (userId, idem) => `payment:lock:idempotency-key:${userId}:${idem}`,
};
```

## RedisLockService.runExclusive contract

- Returns `T | null`. `null` = contention (lock not acquired) → caller throws ConflictException.
- Redis/client failure → throws `ServiceUnavailableException` (503), never masquerade as contention.
- Acquires with Redlock retryCount 5, releases in finally.
