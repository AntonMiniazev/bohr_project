from functools import lru_cache
from urllib.parse import quote_plus

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from .config import Settings


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


def _build_connection_string(settings: Settings) -> str:
    password = quote_plus(settings.sql_server_password)
    return (
        "mssql+pyodbc://"
        f"{settings.sql_server_user}:{password}"
        f"@{settings.sql_server_host}:{settings.sql_server_port}/"
        f"{settings.sql_server_db}"
        f"?driver={quote_plus(settings.odbc_driver)}"
        "&Encrypt=yes"
        "&TrustServerCertificate=yes"
    )


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    settings = get_settings()
    connection_string = _build_connection_string(settings)
    return create_engine(
        connection_string,
        pool_pre_ping=True,
        pool_recycle=300,
        pool_size=5,
        max_overflow=2,
    )


def run_test_query():
    """Runs the configured SQL slice and returns rows as list of dicts."""
    settings = get_settings()
    limit = settings.sql_query_limit

    engine = get_engine()
    stmt = text(settings.sql_test_query)
    bound_stmt = stmt.bindparams(limit=limit)

    with engine.connect() as conn:
        result = conn.execute(bound_stmt)
        columns = result.keys()
        rows = [dict(zip(columns, row)) for row in result.fetchall()]

    return {"row_count": len(rows), "rows": rows, "limit_applied": limit}
