# Using this repo as a template for a new service

This repo is the canonical template for any new dolr-ai service that needs:
- A stateless FastAPI app on rishi-1 + rishi-2
- A fully redundant PostgreSQL backend (Patroni + etcd + HAProxy via Docker Swarm)
- CI/CD via GitHub Actions deploying as the `deploy` user (no root)
- Caddy reverse proxy with Cloudflare in front

The infrastructure layer (Swarm, Patroni, HAProxy, CI, Caddy) is reusable as-is.
Only the **app layer** (`app/`, `patroni/init.sql`) needs to change per project.

---

## What's reusable vs project-specific

| Layer | Files | Action |
|---|---|---|
| **Swarm/HA infra** | `etcd/`, `patroni/Dockerfile`, `patroni/patroni.yml`, `patroni/post_init.sh`, `patroni/stack.yml`, `haproxy/`, `scripts/swarm-setup.sh` | Reuse as-is, only renames needed |
| **CI/CD** | `.github/workflows/deploy.yml` | Reuse as-is, only renames needed |
| **Caddy** | `caddy/Caddyfile`, `caddy/docker-compose.yml` | Add new service block, keep existing ones |
| **App code** | `app/main.py`, `app/database.py`, `requirements.txt`, `Dockerfile`, `docker-compose.yml` | **Replace with new app logic** |
| **DB schema** | `patroni/init.sql` | **Replace with new tables** |

---

## One-command rename (run from new repo dir, after copying files)

```bash
bash scripts/init-from-template.sh <new-service-name>
```

Where `<new-service-name>` is the suffix (e.g. `nsfw-detection`). The script does
all string replacements:
- `yral-hello-world-counter` → `yral-<new-service-name>`
- `hello-world-counter` → `<new-service-name>` (subdomain)
- `counter-db` → `<new-service-name>-db` (Swarm stack name)
- `counter_db` → `<new-service-name>_db` (PostgreSQL database name)

The script does NOT touch `app/`, `patroni/init.sql`, or `requirements.txt` —
those need to be rewritten by hand for the new service.

---

## Step-by-step for a new service (e.g. yral-nsfw-detection)

### 1. Copy the template
```bash
cp -r "Claude Projects/hello-world-counter" "Claude Projects/nsfw-detection"
cd "Claude Projects/nsfw-detection"
rm -rf .git
```

### 2. Run the rename script
```bash
bash scripts/init-from-template.sh nsfw-detection
```

### 3. Replace app code (manual)
- Rewrite `app/main.py` with new routes
- Rewrite `app/database.py` (or delete if no DB needed)
- Update `requirements.txt` with new dependencies
- Rewrite `patroni/init.sql` with new tables (or leave empty if no DB schema needed)

### 4. Add new domain block to BOTH Caddyfiles
On the **counter** repo's `caddy/Caddyfile` AND the new repo's `caddy/Caddyfile`,
add a block for the new service. Both must contain ALL service blocks (the
Caddyfile gets replaced on every deploy).

### 5. Create the GitHub repo
```bash
gh repo create dolr-ai/yral-nsfw-detection --public
```

### 6. Add the 9 GitHub secrets (same names, new values where needed)
- `SERVER_1_IP`, `SERVER_2_IP`, `SERVER_3_IP` — same IPs
- `HETZNER_BARE_METAL_GITHUB_ACTIONS_SSH_PRIVATE_KEY` — `cat ~/.ssh/rishi-hetzner-ci-key`
- `SENTRY_DSN` — create new project at apm.yral.com
- `POSTGRES_PASSWORD`, `REPLICATION_PASSWORD` — `openssl rand -hex 32` (URL-safe)
- `DATABASE_URL_SERVER_1` = `postgresql://postgres:<PG_PASS>@<new-service-name>-db_haproxy-rishi-1:5432/<new-service-name>_db`
- `DATABASE_URL_SERVER_2` = same with `haproxy-rishi-2`

### 7. Initial git push
```bash
git init && git add -A && git commit -m "Initial commit" && git remote add origin git@github.com:dolr-ai/yral-<new-service-name>.git && git push -u origin main
```

CI runs automatically and deploys.

---

## Things you do NOT need to redo (one-time, already done)

These are global to all dolr-ai services on rishi-1/rishi-2/rishi-3:
- ✅ deploy user exists with CI key
- ✅ Docker Swarm cluster initialized (rishi-1 manager, rishi-2/3 workers)
- ✅ Node labels (`server=rishi-1/2/3`)
- ✅ `db-internal` overlay network created
- ✅ `web` Docker network exists
- ✅ Caddy is running on rishi-1 and rishi-2
- ✅ rishi-3 deploy user setup

If you ever rebuild from scratch, run `bash scripts/swarm-setup.sh` once.

---

## What to think about before reusing this template for NSFW detection

1. **Do you actually need PostgreSQL?** If you're just running an ML model and returning a verdict, you might not need a database at all. You can delete the entire `etcd/`, `patroni/`, `haproxy/` stack and skip the `deploy-db-stack` job in CI. Massive simplification.

2. **Image storage?** If you store the input images for audit/training, use S3-compatible object storage (Cloudflare R2, Backblaze B2), not PostgreSQL bytea.

3. **Async processing?** If inference is slow, the API should return a job ID and process in background. That needs a queue (Redis, NATS).

4. **GPU?** None of these servers have GPUs. If your model needs one, you'll need different infra entirely.

5. **Model loading time?** Don't reload the model on every request. Load once at startup, keep in memory. The current `restart: unless-stopped` works.

6. **Rate limiting / abuse:** NSFW endpoints get DoSed. Add Caddy rate limiting per IP.

---

## Improvements to add when you have time (apply to template too)

These are deferred from the counter project — fixing them in the template helps every future service:

- [ ] Use Docker Swarm secrets instead of env vars for `POSTGRES_PASSWORD` / `REPLICATION_PASSWORD`
- [ ] Tag images with git SHA, not just `:latest`
- [ ] Add daily `pg_dump` backup to S3 / B2
- [ ] Enable UFW on rishi-1 and rishi-2 with default-deny
- [ ] Add PgBouncer for connection pooling
- [ ] Move CI inline scripts to `scripts/*.sh` files
- [ ] Tighten `pg_hba.conf` to overlay subnet only
- [ ] Demote `rewind_user` from SUPERUSER to minimum permissions
