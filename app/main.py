import os

import sentry_sdk
from fastapi import FastAPI, HTTPException

from database import get_next_count, check_db_health

sentry_sdk.init(dsn=os.getenv("SENTRY_DSN"))

app = FastAPI()


@app.get("/")
def root():
    """
    Every GET request atomically increments the counter and returns the new value.
    Uses PostgreSQL atomic UPDATE...RETURNING — safe even with 1000 simultaneous requests.
    """
    try:
        count = get_next_count()
        return {"message": f"Hello World Person {count}"}
    except Exception as e:
        raise HTTPException(status_code=503, detail="Database unavailable") from e


@app.get("/health")
def health():
    """
    Checks both app and database health.
    CI, Uptime Kuma, and Docker healthchecks all hit this.
    """
    if not check_db_health():
        raise HTTPException(status_code=503, detail={"status": "ERROR", "database": "unreachable"})
    return {"status": "OK", "database": "reachable"}
