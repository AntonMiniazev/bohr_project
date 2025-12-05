from fastapi import Depends, FastAPI, HTTPException, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader

from .database import get_settings, run_test_query

settings = get_settings()
app = FastAPI(
    title="Bohr SQL Proxy",
    description="Controlled API facade to expose curated SQL Server slices.",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["*"],
)

api_key_scheme = APIKeyHeader(name="X-API-Key", auto_error=False)


def require_api_key(key: str = Security(api_key_scheme)):
    if not key or key != settings.api_key:
        raise HTTPException(status_code=401, detail="Unauthorized")


@app.get("/health")
def health_check(api_key: str = Depends(require_api_key)):
    return {
        "status": "ok",
        "sql_host": settings.sql_server_host,
        "limit": settings.sql_query_limit,
    }


@app.get("/test-query")
def test_query(api_key: str = Depends(require_api_key)):
    try:
        payload = run_test_query()
    except Exception as exc:  # noqa: BLE001 - log and return sanitized error
        raise HTTPException(status_code=502, detail="SQL query failed") from exc
    return payload
