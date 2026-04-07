# yral-hello-world-counter

Per-visitor counter service. Every GET to `/` returns the next sequential
visitor number, persisted in a fully redundant PostgreSQL cluster.

**Live:** https://hello-world-counter.rishi.yral.com

```bash
$ curl https://hello-world-counter.rishi.yral.com/
{"message":"Hello World Person 1"}

$ curl https://hello-world-counter.rishi.yral.com/
{"message":"Hello World Person 2"}
```

This service is also the **canonical infrastructure template** for any new
dolr-ai service. See [TEMPLATE.md](TEMPLATE.md) for how to reuse it.

---

## Architecture

```
                              Internet
                                 │
                       Cloudflare (*.rishi.yral.com)
                                 │
                  ┌──────────────┼──────────────┐
                  ▼                             ▼
              rishi-1                       rishi-2                     rishi-3
        ┌─────────────────┐           ┌─────────────────┐         ┌─────────────────┐
        │ Caddy (HTTPS)   │           │ Caddy (HTTPS)   │         │  (DB tier only) │
        │ FastAPI app     │           │ FastAPI app     │         │                 │
        │ HAProxy ────┐   │           │ HAProxy ────┐   │         │                 │
        │ Patroni+PG  │   │           │ Patroni+PG  │   │         │ Patroni+PG      │
        │ etcd        │   │           │ etcd        │   │         │ etcd            │
        └─────┬───────┘   │           └─────┬───────┘   │         └─────┬───────────┘
              │           │                 │           │               │
              └─── db-internal overlay (private, encrypted) ─────────────┘
```

- **Caddy** terminates TLS (Cloudflare Full SSL → `tls internal`) and reverse-proxies to the FastAPI app
- **App** (FastAPI + psycopg2 pool) connects to the local HAProxy on the `db-internal` overlay network
- **HAProxy** health-checks Patroni's `/master` endpoint and routes SQL to the current PostgreSQL leader
- **Patroni** manages the PostgreSQL cluster, uses **etcd** for leader election, and auto-promotes a standby on failure
- **db-internal** is a Docker Swarm overlay network — private, encrypted, not accessible from the internet

---

## Quick reference

| Concern | Where |
|---|---|
| **App code** | `app/main.py`, `app/database.py` |
| **DB schema** | `patroni/init.sql` |
| **Patroni stack** | `patroni/stack.yml`, `patroni/Dockerfile`, `patroni/patroni.yml`, `patroni/post_init.sh` |
| **etcd / HAProxy stacks** | `etcd/stack.yml`, `haproxy/stack.yml`, `haproxy/haproxy.cfg` |
| **CI/CD** | `.github/workflows/deploy.yml`, `scripts/ci/*.sh` |
| **One-time Swarm setup** | `scripts/swarm-setup.sh` |
| **Architecture deep-dive** | [CLAUDE.md](CLAUDE.md) |
| **Reusing as template** | [TEMPLATE.md](TEMPLATE.md) |

---

## Local development

You can't run a 3-node Patroni cluster on your laptop with these production
files (they assume Docker Swarm with overlay networks). For local development
that mirrors production, see the **`yral-rishi-offline-testing`** companion
repo (separate single-node docker-compose setup).

To make a small app-only change without testing locally:
1. Edit `app/main.py` or `app/database.py`
2. `git push` — CI deploys in ~3 minutes
3. Test on the live URL

---

## Operations

### Health
```bash
curl https://hello-world-counter.rishi.yral.com/health
# {"status":"OK","database":"reachable"}
```

### Cluster status (SSH into any server)
```bash
ssh deploy@138.201.137.181 \
  "docker exec \$(docker ps -qf name=patroni) patronictl -c /etc/patroni.yml list"
```

Should show: 1 Leader (`running`) + 2 Replicas (`streaming`) with `Lag = 0`.

### Roll back to a specific version
Every CI build pushes images tagged with the git SHA. To roll back:
```bash
ssh deploy@138.201.137.181
cd /home/deploy/counter-db-stack
IMAGE_TAG=<old-git-sha> docker stack deploy --with-registry-auth \
    --compose-file etcd-stack.yml \
    --compose-file patroni-stack.yml \
    --compose-file haproxy-stack.yml \
    counter-db
```

Or `git revert` the bad commit and let CI deploy normally.

### Sentry
Errors are reported to https://apm.yral.com (project 23). Tagged with
`environment=production` and `release=<git-sha>` so you can correlate
errors to specific deploys.

---

## Status

- ✅ Live in production with full HA (3 Patroni nodes streaming, 0 lag)
- ✅ Failover tested (kill any 1 node → cluster keeps serving)
- ✅ Database not accessible from internet (verified by port scan)
- ✅ Passwords stored as Docker Swarm secrets (not in `docker inspect`)
- ✅ Sentry error reporting + release tagging
- ✅ Connection pool with retry-on-dead-connection
- ✅ Immutable image versioning via git SHA tags

See [TEMPLATE.md](TEMPLATE.md) for the deferred TODO list (backups,
monitoring, staging, etc.) — items we left for later but tracked.
