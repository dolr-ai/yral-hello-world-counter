import os
import psycopg2
from psycopg2.pool import ThreadedConnectionPool


def _read_database_url() -> str:
    """
    Read DATABASE_URL from a Docker secret file (preferred) or env var (fallback).

    WHY a secret file?
    Env vars are visible in `docker inspect` to anyone in the docker group on
    the host. Secret files are mounted at /run/secrets/ in tmpfs and never
    appear in any inspect output. CI writes the file before docker compose up.
    """
    secret_file = "/run/secrets/database_url"
    if os.path.exists(secret_file):
        with open(secret_file) as f:
            return f.read().strip()
    return os.environ["DATABASE_URL"]


DATABASE_URL = _read_database_url()

# Connection pool — shared across all FastAPI requests.
# WHY pool instead of fresh connections?
# Opening a PG connection takes 5-50ms (TCP + TLS + auth). With a pool we
# pay that cost once at startup and reuse the connection. ThreadedConnectionPool
# is safe for FastAPI's threadpool execution model.
#
# minconn=2:  always keep 2 connections warm
# maxconn=10: scale up to 10 under load (per app container)
_pool = ThreadedConnectionPool(minconn=2, maxconn=10, dsn=DATABASE_URL)


def get_next_count() -> int:
    """
    WHY this one SQL statement is race-condition safe:

    WRONG (two statements — race condition if two requests arrive simultaneously):
        SELECT value FROM counter;
        UPDATE counter SET value = 5;  ← someone else might have changed it!

    CORRECT (one atomic operation):
        UPDATE counter SET value = value + 1 WHERE id = 1 RETURNING value;

    PostgreSQL processes this as a single indivisible step. Even 1000 simultaneous
    requests each get a unique sequential number.
    """
    conn = _pool.getconn()
    try:
        with conn:  # auto-commits on success, rolls back on exception
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE counter SET value = value + 1 WHERE id = 1 RETURNING value;"
                )
                row = cur.fetchone()
                if row is None:
                    raise RuntimeError("Counter row missing — was init.sql run?")
                return row[0]
    finally:
        _pool.putconn(conn)


def check_db_health() -> bool:
    """Quick liveness check — gets a pooled connection and runs SELECT 1."""
    try:
        conn = _pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
            return True
        finally:
            _pool.putconn(conn)
    except Exception:
        return False
