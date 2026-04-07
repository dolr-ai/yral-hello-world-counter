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

# Create or update Docker Swarm secrets.
# WHY this dance?
# `docker secret create` fails if the secret already exists. To rotate:
#   1. Try to create with a temp name
#   2. If success, remove the old and rename — but Swarm secrets can't be renamed
# So instead we just check existence and only create if missing.
# To rotate passwords: manually `docker secret rm` first, then redeploy.
if ! docker secret ls --format '{{.Name}}' | grep -q '^postgres_password$'; then
    echo "${POSTGRES_PASSWORD}" | docker secret create postgres_password -
    echo "  Created postgres_password secret"
else
    echo "  postgres_password secret already exists (skipping)"
fi
if ! docker secret ls --format '{{.Name}}' | grep -q '^replication_password$'; then
    echo "${REPLICATION_PASSWORD}" | docker secret create replication_password -
    echo "  Created replication_password secret"
else
    echo "  replication_password secret already exists (skipping)"
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
