#!/bin/bash
# Runs ONCE after the PostgreSQL cluster is first initialized.
# Patroni passes a connection string as $1, e.g.:
#   "host=/tmp port=5432 user=postgres dbname=postgres"
#
# WHY this script exists:
# Patroni's initdb creates a bare cluster. We need to:
#   1. Set the postgres user's password (initdb leaves it unset)
#   2. Create replicator and rewind_user roles
#   3. Create the counter_db database
#   4. Create the counter table

set -e

CONN="$1"

echo "==> Running post-bootstrap initialization..."

# Set the postgres superuser password for remote (md5) connections.
# Local connections use trust auth, so this isn't needed for psql here,
# but the counter app connects via the overlay network and needs md5.
psql "$CONN" -c "ALTER USER postgres WITH PASSWORD '${POSTGRES_PASSWORD}';"
echo "==> Set postgres password for remote auth"

# Create the replicator user for streaming replication
psql "$CONN" -c "CREATE USER replicator WITH REPLICATION PASSWORD '${REPLICATION_PASSWORD}';"
echo "==> Created replicator user"

# Create the rewind user (used by Patroni's pg_rewind to rejoin a former primary)
psql "$CONN" -c "CREATE USER rewind_user WITH SUPERUSER PASSWORD '${POSTGRES_PASSWORD}';"
echo "==> Created rewind_user"

# Create the counter_db database
psql "$CONN" -c "CREATE DATABASE counter_db;"
echo "==> Created database: counter_db"

# Connect to counter_db (replace dbname=postgres with dbname=counter_db) and run init.sql
COUNTER_CONN="${CONN/dbname=postgres/dbname=counter_db}"
psql "$COUNTER_CONN" -f /scripts/init.sql
echo "==> Counter table created. Bootstrap complete."
