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
# This will rename:
#   yral-hello-world-counter  →  yral-<new-service-name>     (repo/image name)
#   hello-world-counter       →  <new-service-name>          (subdomain)
#   counter-db                →  <new-service-name>-db       (Swarm stack name)
#   counter_db                →  <new-service-name>_db       (Postgres database)
#
# It does NOT touch app/, patroni/init.sql, or requirements.txt — those are
# project-specific and need to be rewritten by hand.
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

# Underscores version for Postgres database name (Postgres dislikes hyphens in db names)
NEW_NAME_UNDERSCORE=$(echo "$NEW_NAME" | tr '-' '_')

echo "==> Renaming template to: $NEW_NAME"
echo "    Image/repo:    yral-$NEW_NAME"
echo "    Subdomain:     $NEW_NAME.rishi.yral.com"
echo "    Swarm stack:   $NEW_NAME-db"
echo "    Postgres db:   ${NEW_NAME_UNDERSCORE}_db"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Files to process (skip .git, app/, patroni/init.sql, requirements.txt, this script, TEMPLATE.md)
FILES=$(find . -type f \
    -not -path './.git/*' \
    -not -path './app/*' \
    -not -path './patroni/init.sql' \
    -not -path './requirements.txt' \
    -not -path './scripts/init-from-template.sh' \
    -not -path './TEMPLATE.md' \
    -not -name '*.md')

# Order matters: replace longest patterns first to avoid partial replacements
for FILE in $FILES; do
    if [ -f "$FILE" ]; then
        # macOS sed and GNU sed differ on -i flag — use a backup file then remove
        sed -i.bak \
            -e "s/yral-hello-world-counter/yral-$NEW_NAME/g" \
            -e "s/hello-world-counter/$NEW_NAME/g" \
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
echo "  4. Add a new domain block to caddy/Caddyfile (keep existing service blocks!)"
echo "  5. Also add the same block to other services' Caddyfiles so deploys don't break routing"
echo "  6. Update CLAUDE.md with new project description"
echo "  7. Create GitHub repo: gh repo create dolr-ai/yral-$NEW_NAME --public"
echo "  8. Set 9 GitHub secrets (see TEMPLATE.md for the list)"
echo "  9. git init && git add -A && git commit -m 'Initial commit' && git push"
echo ""
echo "If you don't need a database at all, you can also delete:"
echo "  - etcd/, patroni/, haproxy/, scripts/swarm-setup.sh"
echo "  - The deploy-db-stack job in .github/workflows/deploy.yml"
echo "  - DATABASE_URL_* secrets and references in docker-compose.yml"
