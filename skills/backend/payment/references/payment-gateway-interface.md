# Payment gateway interface reference

## Interface definition

```typescript
// payment/payment-gateway.interface.ts
export interface PaymentGateway {
  createCheckout(order: PaymentOrder, user: UserContext): Promise<CheckoutResult>;
  handleWebhook(payload: unknown, headers: Record<string, string>): Promise<WebhookResult>;
  handleBrowserReturn(orderId: string, outcome: BrowserOutcome, token?: string): Promise<WebhookResult>;
  syncOrder(orderId: string, userId: string): Promise<WebhookResult>;
}

export type CheckoutResult =
  | { kind: 'form'; action: string; method: 'POST'; fields: Record<string, string> }
  | { kind: 'redirect'; url: string };

export type WebhookResult = { orderId: string; status: OrderStatus; idempotent: boolean };
export type BrowserOutcome = 'success' | 'error' | 'cancel';
```

## DI wiring

```typescript
// payment/payment.constants.ts
export const PAYMENT_GATEWAY = Symbol('PAYMENT_GATEWAY');

// payment.module.ts
@Module({
  imports: [OrderModule, /* adapter module */],
  controllers: [PaymentController],
  providers: [
    { provide: PAYMENT_GATEWAY, useClass: SepayGateway }, // swap here
  ],
  exports: [PAYMENT_GATEWAY],
})
export class PaymentModule {}
```

Or bind by config:

```typescript
providers: [
  {
    provide: PAYMENT_GATEWAY,
    useFactory: (config: ConfigService) => {
      const name = config.get<string>('PAYMENT_GATEWAY', 'sepay');
      if (name === 'sepay') return new SepayGateway(...);
      throw new Error(`Unknown payment gateway: ${name}`);
    },
    inject: [ConfigService, /* adapter deps */],
  },
],
```

## Controller (gateway-agnostic, thin)

Controller only delegates to the gateway/service — no orchestration, no status checks, no signing.

```typescript
@Controller({ path: 'payment', version: '1' })
export class PaymentController {
  constructor(
    @Inject(PAYMENT_GATEWAY) private readonly gateway: PaymentGateway,
    private readonly paymentService: PaymentService, // owns checkout orchestration
  ) {}

  @Post('checkout')
  async checkout(@Body() dto: CheckoutDto, @User('id') userId: string) {
    return this.paymentService.checkout(dto, userId);
  }

  @Public()
  @Post('webhook')
  async webhook(@Body() payload: unknown, @Headers() headers: Record<string, string>) {
    return this.gateway.handleWebhook(payload, headers);
  }

  @Public()
  @Get('return/:outcome/:orderId')
  async browserReturn(
    @Param('outcome') outcome: BrowserOutcome,
    @Param('orderId') orderId: string,
    @Query('token') token?: string,
  ) {
    return this.gateway.handleBrowserReturn(orderId, outcome, token);
  }

  @Post('sync/:orderId')
  async sync(@Param('orderId') orderId: string, @User('id') userId: string) {
    return this.gateway.syncOrder(orderId, userId);
  }
}
```

Checkout orchestration lives in the service (gateway-agnostic), which calls the gateway internally:

```typescript
@Injectable()
export class PaymentService {
  constructor(
    @Inject(PAYMENT_GATEWAY) private readonly gateway: PaymentGateway,
    private readonly orderService: OrderService,
  ) {}

  async checkout(dto: CheckoutDto, userId: string): Promise<CheckoutResult> {
    const order = await this.orderService.getOwnerOrder({ orderId: dto.orderId, userId });
    if (order.status === OrderStatus.PAID) throw new ConflictException('Order already paid');
    const result = await this.gateway.createCheckout(order, { id: userId });
    await this.orderService.saveStatus(order.id, {
      paymentMethod: result.kind === 'form' ? 'FORM' : 'REDIRECT',
    });
    return result;
  }
}
```

## Adapter contract

An adapter must:
1. Implement `PaymentGateway`.
2. Keep all gateway-specific constants/DTOs/HMAC/signing inside its own folder.
3. Map gateway payloads to generic `WebhookResult` and call `OrderService.settlePaid` / `settleFailed` / `cancelOrder` / `expireOrder`.
4. Verify auth fail-closed (never trust missing/placeholder secrets).
5. Replay-guard timestamps if gateway provides them.
6. Validate amount/currency/customer before settling.

## Adding a new gateway

1. Create `payment/<name>/` with `<Name>Gateway implements PaymentGateway`.
2. Add env vars for that gateway.
3. Bind token to new adapter (config or module).
4. No changes to `OrderService`, `PaymentController`, or expiry cron.

## Sepay as default adapter

See `references/sepay-adapter.md` for the reference implementation (HMAC signing, IPN mapping, browser token, DTOs).
