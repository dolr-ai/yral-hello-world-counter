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

# Update counter's Caddy snippet (only THIS file, never the global Caddyfile).
# Caddy is now a shared platform service managed at /home/deploy/caddy/ via
# the snippet directory pattern. Counter only owns its own snippet file.
# Per-app deploys never recreate the Caddy container.
mkdir -p /home/deploy/caddy/conf.d

SNIPPET_DEST="/home/deploy/caddy/conf.d/yral-hello-world-counter.caddy"
SNIPPET_TMP="${SNIPPET_DEST}.tmp"

cp /home/deploy/yral-hello-world-counter/caddy/snippet.caddy "${SNIPPET_TMP}"

# Validate Caddy is healthy BEFORE swap — abort if existing config is broken
docker exec caddy caddy validate --config /etc/caddy/Caddyfile || {
    echo "FATAL: existing Caddy config invalid before swap, aborting"
    rm -f "${SNIPPET_TMP}"
    exit 1
}

# Atomic swap
mv "${SNIPPET_TMP}" "${SNIPPET_DEST}"

# Validate AFTER swap — catches snippet syntax errors. If invalid, remove it.
docker exec caddy caddy validate --config /etc/caddy/Caddyfile || {
    echo "FATAL: new snippet broke Caddy config, removing"
    rm -f "${SNIPPET_DEST}"
    exit 1
}

# Graceful reload
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --force

echo "App + Caddy snippet deployed."
