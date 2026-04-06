# WHY build a custom image?
# Patroni is not a standalone application — it needs to be installed ON TOP of PostgreSQL.
# No official public Docker image combines both. We build our own simple image.
#
# This image contains:
# - Ubuntu 22.04 base
# - PostgreSQL 16 (the database itself)
# - Patroni + etcd3 client (the HA manager)

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install PostgreSQL 16 from the official PGDG repository
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 python3-pip curl gnupg2 lsb-release && \
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list && \
    curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor > /etc/apt/trusted.gpg.d/postgresql.gpg && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-16 postgresql-client-16 && \
    pip3 install --no-cache-dir "patroni[etcd3]" psycopg2-binary && \
    rm -rf /var/lib/apt/lists/*

# Create data directory and set postgres user as owner
RUN mkdir -p /data/patroni /scripts && \
    chown -R postgres:postgres /data/patroni /scripts

# Copy config and scripts
COPY patroni.yml /etc/patroni.yml
COPY init.sql /scripts/init.sql
COPY post_init.sh /scripts/post_init.sh
RUN chmod +x /scripts/post_init.sh

# Run as postgres user (never as root)
USER postgres

# Patroni manages PostgreSQL — just start patroni
CMD ["patroni", "/etc/patroni.yml"]
