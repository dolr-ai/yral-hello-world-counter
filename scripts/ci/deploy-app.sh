#!/bin/bash
# Runs ON each app server (rishi-1 or rishi-2) over SSH from CI.
# Deploys the counter app via docker-compose and reloads Caddy.
#
# Required env vars (passed by CI):
#   IMAGE_TAG               — git SHA for immutable image versioning
#   DATABASE_URL            — server-specific (haproxy-rishi-1 or rishi-2)
#   SENTRY_DSN              — Sentry project DSN (can be empty)
#   GITHUB_TOKEN            — for GHCR docker login
#   GITHUB_ACTOR            — GHCR username

set -e

# Login to GHCR (private packages need auth for every pull)
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_ACTOR}" --password-stdin

cd /home/deploy/yral-hello-world-counter

# Write DATABASE_URL to a secret file (mounted into the container at /run/secrets/database_url).
# This keeps the password out of `docker inspect`.
mkdir -p secrets
umask 077  # secret file readable only by owner
echo -n "${DATABASE_URL}" > secrets/database_url

# Pull the new image and (re)create the container
export IMAGE_TAG="${IMAGE_TAG}"
SENTRY_DSN="${SENTRY_DSN}" docker compose pull
SENTRY_DSN="${SENTRY_DSN}" docker compose up -d

# Reload Caddy with the latest Caddyfile (zero-downtime)
mkdir -p /home/deploy/caddy
cp caddy/Caddyfile /home/deploy/caddy/Caddyfile
cp caddy/docker-compose.yml /home/deploy/caddy/docker-compose.yml
cd /home/deploy/caddy
docker compose up -d
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --force

echo "App + Caddy deployed."
