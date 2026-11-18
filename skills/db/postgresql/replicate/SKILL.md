---
name: postgresql-replicate
description: PostgreSQL leader-follower streaming replication — docker infra (pg_basebackup, sync commit) + NestJS/Prisma read-replica integration (routing, failover circuit breaker, lag metrics). Use when setting up or reviewing Postgres replication.
---

# PostgreSQL Replication (Leader–Follower)

## Purpose

Set up and review a **single leader + single follower** PostgreSQL streaming replication topology, including the Docker infra and the NestJS/Prisma application integration (read routing, failover, observability). Optimized for a read-heavy workload where reads may be served from the follower while all writes go to the leader.

## Agent Protocol

### Trigger
User request includes: `postgres replication`, `leader follower`, `read replica`, `streaming replication`, `pg_basebackup`, `synchronous_standby`, `PrismaReplicaService`, `replica failover`, `replication lag`.

### Input Context
- Postgres image (default `pgvector/pgvector:pg16`; use `postgres:16` if no pgvector needed)
- Sync level (default `remote_apply`)
- App stack (NestJS + Prisma assumed; adapt if different)
- Whether the follower is promoted manually or via external tooling

### Output Artifact
Docker compose services, init/entrypoint scripts, env vars, Prisma replica service, read-routing helper, failover circuit breaker, lag probe, and the sync-enable step.

### Response Format
Produce artifacts directly. No preamble. Prefer editing existing files over rewriting; keep secrets as env placeholders.

### Completion Criteria
- Leader boots and creates `replicator` role + replication slot + `pg_hba` replication entry.
- Follower performs `pg_basebackup` on first start, then streams; re-starts are idempotent.
- `synchronous_standby_names` is enabled **after** init (not at boot) to avoid the init deadlock.
- App writes go to leader (`PrismaService`); reads use `runRead` (leader-first, follower fallback).
- Follower lag + up/down are exported as metrics; circuit breaker opens on repeated follower failures.
- `DATABASE_URL_REPLICA` falls back to `DATABASE_URL` so unit tests/dev without a follower still work.

### Max Response Length
4096 tokens

# Rules

## Topology

- One leader, one follower (streaming replication, physical). Scale out by adding followers; each needs its own slot and `application_name`.
- All writes go to the leader. Reads may go to the follower via `runRead`.
- Default sync level: `remote_apply` (`synchronous_commit=remote_apply`) — leader acks only after the follower has replayed, so a read from the follower immediately after commit sees the new data. Trade-off: write latency ≈ follower replay latency; if the follower dies, writes block until `statement_timeout` (default `10s`) then fail.
- Set `statement_timeout` so a dead follower cannot hang commits forever.

## Infra

- Image: `pgvector/pgvector:pg16` by default (ships pgvector for RAG). Swap to `postgres:16` if vector support is not needed — everything else is identical.
- Leader service name in compose must be `db` (follower references `db:5432`). Follower service `db-follower`.
- Leader init runs via `docker-entrypoint-initdb.d/01-replication.sh` (only on first init, empty data dir).
- Follower uses a custom entrypoint that basebacks up only when `$PGDATA` is empty, then patches `application_name` and starts `hot_standby=on`.
- Never set `synchronous_standby_names` in the leader's boot command — the init temp server would deadlock waiting for a standby that is itself waiting for the leader's TCP port. Enable it after init via `ALTER SYSTEM` + reload (see `references/infra.md` → enable-sync).
- Persist `application_name=follower` in `postgresql.auto.conf` on every follower start — `pg_basebackup -R` does not write it, and old volumes lack it.
- Replication credentials live in env (`REPLICATION_PASSWORD`); never hardcode in scripts committed without env substitution. The init script interpolates `${REPLICATION_PASSWORD}` at runtime (it runs inside the container with env present).

## Application (NestJS + Prisma)

- `PrismaService` (leader) for all writes and any read-after-write. `PrismaReplicaService` (follower) for read candidates.
- `PrismaReplicaService` falls back to `DATABASE_URL` when `DATABASE_URL_REPLICA` is unset — callers never break in tests/dev.
- Read routing: `runRead(target, op)` tries leader first; on error retries once on the follower (unless the circuit is open). Record metrics per source.
- Writes never go through `runRead` and never touch the replica.
- Circuit breaker (`ReplicaFailoverService`): after `REPLICA_FAILOVER_THRESHOLD` (default 3) consecutive follower failures, skip follower fallback for `REPLICA_FAILOVER_COOLDOWN_MS` (default 30s). Probe results also drive it.
- Probe leader + follower every 10s (`ReplicaMetricsService`): `app_db_replica_up{instance}`, `app_db_replica_lag_seconds{role="follower"}`. Probes must never throw.
- Lag source: follower's `pg_last_xact_replay_timestamp()` (`now() - ...`).
- Metric for read source: `app_db_replica_read_total{source,target,result}`.

## Operations

- First boot: `docker compose up -d db` → wait healthy → `docker compose up -d db-follower` → wait healthy → run enable-sync script.
- Re-sync a broken follower: stop it, wipe its volume (`docker volume rm ..._postgres_follower_data`), start again (basebackup re-runs).
- Manual promotion (leader loss): `docker exec db-follower pg_ctl promote -D $PGDATA` (or `pg_ctlcluster`), then repoint `DATABASE_URL` to the follower and rebuild/restart app. Re-attach the old leader as a follower afterward. Skill does not automate this.
- Never edit an applied migration; create a new one.

## Troubleshooting

- Init hangs / `CREATE DATABASE` stuck: `synchronous_standby_names` set at boot — remove it from the command and enable after init.
- Follower can't connect: check `pg_hba.conf` replication entry (`host replication replicator all scram-sha-256`) and that the `replicator` role has `REPLICATION`.
- `application_name` missing → sync never engages (standby shows `async`): patch auto.conf (done by entrypoint) and reload.
- Basebackup fails "slot does not exist": leader init didn't run (data dir not empty on first boot) — wipe leader volume and recreate.
- Reads from follower stale despite sync: confirm `synchronous_commit=remote_apply` and `sync_state='sync'` in `pg_stat_replication`.

## References

- Infra (compose, init scripts, env, enable-sync): `references/infra.md`.
- App integration (Prisma replica, routing, failover, metrics): `references/app-integration.md`.
