#!/bin/bash
# This script runs ONCE after the PostgreSQL cluster is first initialized (bootstrap).
# Patroni passes the superuser connection URL as argument $1.
# Example $1: postgresql://postgres:PASSWORD@localhost:5432/postgres
#
# WHY this script exists:
# When Patroni runs "initdb", it creates a bare PostgreSQL cluster with just the
# postgres database. We need to create our "counter_db" database and "counter" table.
# This script does exactly that, and then it never runs again (data is replicated
# to standbys automatically).

set -e

SUPERUSER_URL="$1"

echo "==> Running post-bootstrap initialization..."

# Set the postgres superuser password for remote (non-localhost) connections.
# Patroni's initdb creates postgres with no password. pg_hba.conf uses "trust"
# for localhost but "md5" for remote connections (from the overlay network).
# Without this, the counter app can't authenticate through HAProxy.
psql "${SUPERUSER_URL}" -c "ALTER USER postgres WITH PASSWORD '${POSTGRES_PASSWORD}';"
echo "==> Set postgres password for remote auth"

# Create the replicator user for streaming replication between Patroni nodes
psql "${SUPERUSER_URL}" -c "CREATE USER replicator WITH REPLICATION PASSWORD '${REPLICATION_PASSWORD}';"
echo "==> Created replicator user"

# Create the rewind user (used by Patroni's pg_rewind to rejoin a former primary)
psql "${SUPERUSER_URL}" -c "CREATE USER rewind_user WITH SUPERUSER PASSWORD '${POSTGRES_PASSWORD}';"
echo "==> Created rewind_user"

# Create the counter_db database using the superuser URL
psql "${SUPERUSER_URL}" -c "CREATE DATABASE counter_db;"
echo "==> Created database: counter_db"

# Connect to counter_db and run our init.sql to create the counter table
# The URL substitution replaces "/postgres" at the end with "/counter_db"
psql "${SUPERUSER_URL%/postgres}/counter_db" -f /scripts/init.sql
echo "==> Counter table created. Bootstrap complete."
