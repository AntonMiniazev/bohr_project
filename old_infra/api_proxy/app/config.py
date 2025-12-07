import os
from dataclasses import dataclass

from dotenv import load_dotenv


load_dotenv()


def _require(env_key: str) -> str:
    value = os.getenv(env_key)
    if not value:
        raise ValueError(f"Environment variable '{env_key}' must be set")
    return value


@dataclass(frozen=True)
class Settings:
    sql_server_host: str = _require("SQL_SERVER_HOST")
    sql_server_port: int = int(os.getenv("SQL_SERVER_PORT", "14330"))
    sql_server_db: str = _require("SQL_SERVER_DB")
    sql_server_user: str = _require("SQL_SERVER_USER")
    sql_server_password: str = _require("SQL_SERVER_PASSWORD")
    sql_query_limit: int = max(1, int(os.getenv("SQL_QUERY_LIMIT", "100")))
    sql_test_query: str = os.getenv(
        "SQL_TEST_QUERY",
        "SELECT TOP (:limit) event_dt, total_revenue, total_orders "
        "FROM dbo.orders_daily ORDER BY event_dt DESC",
    )
    odbc_driver: str = os.getenv("SQL_ODBC_DRIVER", "ODBC Driver 18 for SQL Server")
    request_timeout_seconds: float = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "15"))
    api_key: str = _require("API_KEY")
