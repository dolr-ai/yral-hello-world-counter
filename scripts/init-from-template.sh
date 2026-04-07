#!/bin/bash
# =============================================================================
# Rename this template to a new service.
#
# Usage (from the new repo dir, after copying files from this template):
#   bash scripts/init-from-template.sh <new-service-name>
#
# Example:
#   bash scripts/init-from-template.sh nsfw-detection
#
# This will rename the following project-specific strings everywhere:
#   yral-hello-world-counter  →  yral-<new-service-name>     (image/repo name)
#   hello-world-counter       →  <new-service-name>          (subdomain)
#   counter-db                →  <new-service-name>-db       (Swarm stack name)
#   counter_db                →  <new-service-name>_db       (Postgres database)
#   counter-cluster           →  <new-service-name>-cluster  (Patroni scope)
#   counter-etcd-cluster      →  <new-service-name>-etcd-cluster (etcd token)
#
# Files NOT touched by the script (project-specific, must be rewritten by hand):
#   - app/                  (your application logic)
#   - patroni/init.sql      (your database schema)
#   - requirements.txt      (your Python dependencies)
#   - TEMPLATE.md           (kept as reference, has counter examples)
#   - this script           (would corrupt itself)
# =============================================================================

set -e

if [ -z "$1" ]; then
    echo "Usage: bash scripts/init-from-template.sh <new-service-name>"
    echo "Example: bash scripts/init-from-template.sh nsfw-detection"
    exit 1
fi

NEW_NAME="$1"

# Validate the name (lowercase, alphanumeric + hyphens, no leading/trailing hyphen)
if ! echo "$NEW_NAME" | grep -qE '^[a-z][a-z0-9-]*[a-z0-9]$'; then
    echo "ERROR: Name must be lowercase alphanumeric with hyphens (e.g. nsfw-detection)"
    exit 1
fi

# Underscores version for Postgres database name (Postgres dislikes hyphens)
NEW_NAME_UNDERSCORE=$(echo "$NEW_NAME" | tr '-' '_')

echo "==> Renaming template to: $NEW_NAME"
echo "    Image/repo:        yral-$NEW_NAME"
echo "    Subdomain:         $NEW_NAME.rishi.yral.com"
echo "    Swarm stack:       $NEW_NAME-db"
echo "    Postgres db:       ${NEW_NAME_UNDERSCORE}_db"
echo "    Patroni scope:     $NEW_NAME-cluster"
echo "    etcd cluster tag:  $NEW_NAME-etcd-cluster"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Files to process. We process EVERYTHING under the repo except:
# - .git/                              (git internals)
# - app/                               (your code, you'll rewrite it)
# - patroni/init.sql                   (your schema, you'll rewrite it)
# - requirements.txt                   (your deps, you'll rewrite them)
# - TEMPLATE.md                        (reference doc with examples)
# - scripts/init-from-template.sh      (this script — would corrupt itself)
FILES=$(find . -type f \
    -not -path './.git/*' \
    -not -path './app/*' \
    -not -path './patroni/init.sql' \
    -not -path './requirements.txt' \
    -not -path './TEMPLATE.md' \
    -not -path './scripts/init-from-template.sh')

# Rules ordered longest-first to avoid partial matches.
# (e.g. "yral-hello-world-counter" must be replaced before "hello-world-counter")
for FILE in $FILES; do
    if [ -f "$FILE" ]; then
        # macOS sed and GNU sed differ on -i flag — use a backup file then remove
        sed -i.bak \
            -e "s/yral-hello-world-counter/yral-$NEW_NAME/g" \
            -e "s/hello-world-counter/$NEW_NAME/g" \
            -e "s/counter-etcd-cluster/$NEW_NAME-etcd-cluster/g" \
            -e "s/counter-cluster/$NEW_NAME-cluster/g" \
            -e "s/counter-db/$NEW_NAME-db/g" \
            -e "s/counter_db/${NEW_NAME_UNDERSCORE}_db/g" \
            "$FILE"
        rm "$FILE.bak"
        echo "  ✓ $FILE"
    fi
done

echo ""
echo "==> Renames complete."
echo ""
echo "NEXT STEPS (manual):"
echo "  1. Replace app/main.py and app/database.py with your new app logic"
echo "  2. Replace patroni/init.sql with your new database schema (or delete)"
echo "  3. Update requirements.txt with your new Python dependencies"
echo "  4. Update README.md with what your new service actually does"
echo "  5. Update CLAUDE.md with new project-specific architecture details"
echo "  6. Add a new domain block to caddy/Caddyfile (keep existing service blocks!)"
echo "  7. Also add the same block to other services' Caddyfiles so deploys don't break routing"
echo "  8. Create GitHub repo: gh repo create dolr-ai/yral-$NEW_NAME --public"
echo "  9. Set 9 GitHub secrets (see TEMPLATE.md for the full list)"
echo " 10. git init && git add -A && git commit -m 'Initial commit' && git push"
echo ""
echo "If you don't need a database at all, you can also delete:"
echo "  - etcd/, patroni/, haproxy/, scripts/swarm-setup.sh"
echo "  - The deploy-db-stack job in .github/workflows/deploy.yml"
echo "  - DATABASE_URL_* secrets and references in docker-compose.yml"
