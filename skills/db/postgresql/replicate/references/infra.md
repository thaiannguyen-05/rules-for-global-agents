# Infra reference — Postgres leader–follower

## docker-compose services

```yaml
services:
  db:
    image: pgvector/pgvector:pg16
    container_name: order-cinema-db
    restart: 'no'
    env_file: [.env.development]
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}
    ports:
      - '${DB_PORT:-5432}:5432'
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./replication/postgres/leader-init.sh:/docker-entrypoint-initdb.d/01-replication.sh:ro
    # synchronous_standby_names is NOT set here (see note).
    command:
      - postgres
      - '-c'
      - synchronous_commit=${SYNC_COMMIT:-remote_apply}
      - '-c'
      - statement_timeout=${STATEMENT_TIMEOUT:-10s}
    networks: [order-cinema-network]
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U ${DB_USER} -d ${DB_NAME}']
      interval: 5s
      timeout: 3s
      retries: 20

  db-follower:
    image: pgvector/pgvector:pg16
    container_name: order-cinema-db-follower
    restart: 'no'
    user: postgres
    env_file: [.env.development]
    entrypoint: ['sh', '/entrypoint.sh']
    ports:
      - '${DB_FOLLOWER_PORT:-5433}:5432'
    volumes:
      - postgres_follower_data:/var/lib/postgresql/data
      - ./replication/postgres/follower-entrypoint.sh:/entrypoint.sh:ro
    networks: [order-cinema-network]
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U ${DB_USER} -d ${DB_NAME}']
      interval: 5s
      timeout: 3s
      retries: 20

volumes:
  postgres_data:
  postgres_follower_data:
```

NOTE: `synchronous_standby_names` is deliberately absent from the boot command. The entrypoint passes `"$@"` to the temp server during init (`docker_temp_server_start "$@"`), so a `CREATE DATABASE` would block forever waiting for a standby that is itself waiting for the leader TCP port. Enable sync after init (enable-sync below).

## leader-init.sh (mounted into docker-entrypoint-initdb.d)

```sh
#!/bin/sh
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
  CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';
  SELECT pg_create_physical_replication_slot('follower_slot');
EOSQL
echo "host replication replicator all scram-sha-256" >> "$PGDATA/pg_hba.conf"
```

Runs only on first init (empty data dir). Creates the replication role, a physical slot named `follower_slot`, and allows replication connections.

## follower-entrypoint.sh

```sh
#!/bin/sh
set -e
if [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
  echo ">> Data dir empty, waiting for leader..."
  until pg_isready -h db -p 5432 -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"; do sleep 2; done

  echo ">> pg_basebackup from leader..."
  echo "db:5432:replication:replicator:$REPLICATION_PASSWORD" > ~/.pgpass
  chmod 600 ~/.pgpass
  PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
    -h db -p 5432 -U replicator \
    -D "$PGDATA" -R -X stream -S follower_slot -P
  chmod 700 "$PGDATA"
fi

# Ensure application_name=follower (pg_basebackup -R omits it; old volumes lack it).
AUTO_CONF="$PGDATA/postgresql.auto.conf"
if [ -f "$AUTO_CONF" ] && grep -q "^primary_conninfo" "$AUTO_CONF"; then
  if grep -q "application_name" "$AUTO_CONF"; then
    sed -i "s/application_name=[^ ']*/application_name=follower/g" "$AUTO_CONF"
  else
    sed -i "s/^primary_conninfo = '\(.*\)'$/primary_conninfo = '\1 application_name=follower'/" "$AUTO_CONF"
  fi
fi

exec docker-entrypoint.sh postgres -c hot_standby=on
```

Idempotent: basebackup only when data dir empty; application_name patch runs every start.

## enable-sync.sh (run after both are healthy)

```sh
#!/bin/sh
set -e
NAMES="${SYNC_STANDBY_NAMES:-FIRST 1 (follower)}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-order_cinema_db}"

until docker exec order-cinema-db pg_isready -U "$DB_USER" -d postgres >/dev/null 2>&1; do sleep 2; done

docker exec order-cinema-db psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "ALTER SYSTEM SET synchronous_standby_names = '$NAMES';" \
  -c "SELECT pg_reload_conf();"

docker exec order-cinema-db psql -U "$DB_USER" -d postgres \
  -c "SHOW synchronous_standby_names;" \
  -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"
```

Persisted in `postgresql.auto.conf` inside PGDATA, survives restarts.

## Env vars

```
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=order_cinema_db
DB_PORT=5432
DB_FOLLOWER_PORT=5433
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/order_cinema_db
DATABASE_URL_REPLICA=postgresql://postgres:postgres@localhost:5433/order_cinema_db

REPLICATION_PASSWORD=andev

SYNC_COMMIT=remote_apply          # synchronous_commit
SYNC_STANDBY_NAMES=FIRST 1 (follower)
STATEMENT_TIMEOUT=10s
```

## First-boot sequence

1. `docker compose up -d db` — wait healthy.
2. `docker compose up -d db-follower` — basebacks up, wait healthy.
3. Run `enable-sync.sh` (or `pnpm infra:sync`).
4. Verify `SELECT application_name, state, sync_state FROM pg_stat_replication;` shows `sync`.

## Reset a broken follower

```sh
docker compose stop db-follower
docker volume rm <project>_postgres_follower_data
docker compose up -d db-follower   # re-basebacks
```
