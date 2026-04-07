#!/bin/bash
# Runs ON the Swarm manager (rishi-1) over SSH from CI.
# Deploys the counter-db Swarm stack (etcd + Patroni + HAProxy).
#
# Required env vars (passed by CI from GitHub Actions):
#   IMAGE_TAG               — git SHA for immutable image versioning
#   POSTGRES_PASSWORD       — superuser password for PostgreSQL
#   REPLICATION_PASSWORD    — replication user password
#   GITHUB_TOKEN            — for GHCR docker login
#   GITHUB_ACTOR            — GHCR username

set -e

cd /home/deploy/counter-db-stack

# SCP preserves directory structure; flatten so stack deploy finds files locally
mv etcd/stack.yml ./etcd-stack.yml 2>/dev/null || true
mv patroni/stack.yml ./patroni-stack.yml 2>/dev/null || true
mv haproxy/stack.yml ./haproxy-stack.yml 2>/dev/null || true
mv haproxy/haproxy.cfg ./haproxy.cfg 2>/dev/null || true

# Login to GHCR so workers can pull images via --with-registry-auth
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_ACTOR}" --password-stdin

# Create Docker Swarm secrets — namespaced with the stack name.
# WHY namespaced names?
# Swarm secrets are CLUSTER-WIDE, not per-stack. Two services in the same
# Swarm would conflict on a generic name like `postgres_password`. The
# stack name prefix isolates each project's secrets from each other.
#
# WHY only create-if-missing?
# Swarm secrets are immutable — you can't update a secret in place. To
# rotate a password, manually `docker secret rm` first, then redeploy.
PG_SECRET_NAME="counter-db_postgres_password"
REP_SECRET_NAME="counter-db_replication_password"

if ! docker secret ls --format '{{.Name}}' | grep -q "^${PG_SECRET_NAME}$"; then
    echo "${POSTGRES_PASSWORD}" | docker secret create "${PG_SECRET_NAME}" -
    echo "  Created ${PG_SECRET_NAME}"
else
    echo "  ${PG_SECRET_NAME} already exists (skipping)"
fi
if ! docker secret ls --format '{{.Name}}' | grep -q "^${REP_SECRET_NAME}$"; then
    echo "${REPLICATION_PASSWORD}" | docker secret create "${REP_SECRET_NAME}" -
    echo "  Created ${REP_SECRET_NAME}"
else
    echo "  ${REP_SECRET_NAME} already exists (skipping)"
fi

# Export IMAGE_TAG so the stack files can interpolate it
export IMAGE_TAG="${IMAGE_TAG}"

# Deploy (or update) the stack. Idempotent.
docker stack deploy \
    --with-registry-auth \
    --compose-file etcd-stack.yml \
    --compose-file patroni-stack.yml \
    --compose-file haproxy-stack.yml \
    counter-db

echo ""
echo "Stack deployed. Service status:"
docker stack services counter-db
