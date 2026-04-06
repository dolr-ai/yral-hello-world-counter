import os
import psycopg2

# DATABASE_URL format: postgresql://postgres:PASSWORD@haproxy:5432/counter_db
# "haproxy" resolves because both containers are on the same Docker "web" network.
# HAProxy automatically routes to whichever Patroni node is currently primary.
DATABASE_URL = os.environ["DATABASE_URL"]


def get_connection():
    return psycopg2.connect(DATABASE_URL)


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
    conn = get_connection()
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
        conn.close()


def check_db_health() -> bool:
    try:
        conn = get_connection()
        conn.close()
        return True
    except Exception:
        return False
