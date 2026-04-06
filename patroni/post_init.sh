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

# Create the counter_db database using the superuser URL
psql "${SUPERUSER_URL}" -c "CREATE DATABASE counter_db;"
echo "==> Created database: counter_db"

# Connect to counter_db and run our init.sql to create the counter table
# The URL substitution replaces "/postgres" at the end with "/counter_db"
psql "${SUPERUSER_URL%/postgres}/counter_db" -f /scripts/init.sql
echo "==> Counter table created. Bootstrap complete."
