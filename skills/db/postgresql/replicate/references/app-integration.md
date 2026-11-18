# App integration reference — NestJS + Prisma

## PrismaReplicaService

Read-only client pointed at the follower. Falls back to `DATABASE_URL` when `DATABASE_URL_REPLICA` is unset (tests/dev without a follower).

```typescript
@Injectable()
export class PrismaReplicaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor(private readonly configService: ConfigService) {
    const replicaUrl = configService.get<string>('DATABASE_URL_REPLICA');
    const connectionString = replicaUrl ?? configService.getOrThrow<string>('DATABASE_URL');
    const adapter = new PrismaPg({ connectionString });
    super({ adapter });
  }
  async onModuleInit() { await this.$connect(); }
  async onModuleDestroy() { await this.$disconnect(); }
}
```

## PrismaModule (global)

```typescript
@Global()
@Module({
  providers: [PrismaService, PrismaReplicaService, ReplicaFailoverService],
  exports: [PrismaService, PrismaReplicaService, ReplicaFailoverService],
})
export class PrismaModule {}
```

## Read routing (leader-first + follower fallback)

```typescript
private async runRead<T>(target: string, op: (db: PrismaService | PrismaReplicaService) => Promise<T>): Promise<T> {
  try {
    const result = await op(this.prismaService);
    this.metrics?.incReplicaRead('leader', target, 'success');
    return result;
  } catch (leaderError) {
    this.metrics?.incReplicaRead('leader', target, 'error');
    if (this.replica && (!this.failover || this.failover.useReplica())) {
      try {
        const result = await op(this.replica);
        this.failover?.onSuccess();
        this.metrics?.incReplicaRead('replica', target, 'success');
        return result;
      } catch (replicaError) {
        this.failover?.onFailure();
        this.metrics?.incReplicaRead('replica', target, 'error');
        throw replicaError;
      }
    }
    throw leaderError;
  }
}
```

Usage:

```typescript
async getAllFilms() {
  return this.runRead('film', (db) => db.film.findMany({ orderBy: { id: 'asc' } }));
}
// writes always use PrismaService directly
async createFilm(dto) { return this.prismaService.film.create({ data: dto }); }
```

Constructor injection uses `@Optional()` for replica/failover/metrics so the service works without them.

## ReplicaFailoverService (circuit breaker)

```typescript
@Injectable()
export class ReplicaFailoverService {
  private consecutiveFailures = 0;
  private openUntil = 0;
  private readonly threshold: number;
  private readonly cooldownMs: number;

  constructor(@Optional() config?: ConfigService) {
    const t = Number(config?.get('REPLICA_FAILOVER_THRESHOLD') ?? 3);
    const c = Number(config?.get('REPLICA_FAILOVER_COOLDOWN_MS') ?? 30000);
    this.threshold = Number.isFinite(t) && t > 0 ? Math.floor(t) : 3;
    this.cooldownMs = Number.isFinite(c) && c > 0 ? Math.floor(c) : 30000;
  }
  useReplica(): boolean { return Date.now() >= this.openUntil; }
  onSuccess(): void { this.consecutiveFailures = 0; }
  onFailure(): void {
    this.consecutiveFailures += 1;
    if (this.consecutiveFailures >= this.threshold) {
      this.openUntil = Date.now() + this.cooldownMs;
      this.consecutiveFailures = 0;
    }
  }
  reset(): void { this.consecutiveFailures = 0; this.openUntil = 0; }
}
```

No timers/retry loops — a timestamp gate prevents hot loops against a dead follower.

## ReplicaMetricsService (probe every 10s)

```typescript
@Injectable()
export class ReplicaMetricsService {
  constructor(
    private readonly prismaService: PrismaService,
    private readonly replica: PrismaReplicaService,
    @Optional() private readonly metrics?: MetricsService,
    @Optional() private readonly failover?: ReplicaFailoverService,
  ) {}

  @Cron(CronExpression.EVERY_10_SECONDS)
  async probe(): Promise<void> {
    await this.probeLeader();
    await this.probeFollower();
  }

  private async probeLeader(): Promise<void> {
    try { await this.prismaService.$queryRaw`SELECT 1`; this.metrics?.setReplicaUp('leader', 1); }
    catch { this.metrics?.setReplicaUp('leader', 0); }
  }

  private async probeFollower(): Promise<void> {
    try {
      const rows = await this.replica.$queryRaw<{ lag_seconds: number }[]>`
        SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS "lag_seconds"
      `;
      const lag = Number(rows?.[0]?.lag_seconds);
      this.metrics?.setReplicaUp('follower', 1);
      this.failover?.onSuccess();
      if (Number.isFinite(lag)) {
        this.metrics?.setReplicaLag(lag);
        this.metrics?.incReplicaRead('replica', 'probe', 'success');
      }
    } catch {
      this.metrics?.setReplicaUp('follower', 0);
      this.failover?.onFailure();
      this.metrics?.incReplicaRead('replica', 'probe', 'error');
    }
  }
}
```

Probes must never throw (wrap everything in try/catch).

## Metrics

- `app_db_replica_read_total{source,target,result}` — counter, source in {leader, replica}.
- `app_db_replica_up{instance}` — gauge, instance in {leader, follower}.
- `app_db_replica_lag_seconds{role="follower"}` — gauge, seconds since last replay.

## Env (app)

```
DATABASE_URL=postgresql://...@localhost:5432/...
DATABASE_URL_REPLICA=postgresql://...@localhost:5433/...
REPLICA_FAILOVER_THRESHOLD=3
REPLICA_FAILOVER_COOLDOWN_MS=30000
```

## Read-after-write caution

With `remote_apply`, a follower read immediately after a leader commit sees the new data because the leader only acks after replay. If you lower the sync level (or run async), route read-after-write queries to the leader or accept staleness.
