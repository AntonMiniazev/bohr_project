from decimal import Decimal
from functools import lru_cache
from typing import Any, Dict, List
from urllib.parse import quote_plus

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine, Result

from .config import Settings

SUMMARY_SQL = text(
    """
    WITH store_lookup AS (
        SELECT 
            store_id, 
            MIN(store_name) AS store_name
        FROM Ampere.reporting.dim_stores
        GROUP BY store_id
    ),
    order_costs AS (
        SELECT
            order_id,
            SUM(total_cost) AS total_cost,
            MAX(store_id) AS store_id
        FROM Ampere.reporting.dim_costing
        GROUP BY order_id
    ),
    filtered AS (
        SELECT
            f.order_id,
            f.total_amount,
            f.order_date,
            COALESCE(cost.total_cost, 0) AS total_cost,
            COALESCE(del.tariff, 0) AS tariff,
            s.store_name
        FROM Ampere.reporting.fct_orders_sales f
        LEFT JOIN order_costs cost ON cost.order_id = f.order_id
        LEFT JOIN store_lookup s ON s.store_id = cost.store_id
        LEFT JOIN Ampere.reporting.dim_delivery_cost del ON del.order_id = f.order_id
        WHERE f.order_date BETWEEN :start_date AND :end_date
          AND (:store_name IS NULL OR s.store_name = :store_name)
    )
    SELECT
        COALESCE(SUM(total_amount), 0) AS sales,
        COALESCE(SUM(total_cost), 0) AS cost_of_sales,
        COALESCE(SUM(total_amount - total_cost - tariff), 0) AS gross_profit,
        COUNT(DISTINCT order_id) AS total_orders
    FROM filtered
    """
)

SALES_TRENDS_STORE_SQL = text(
    """
    WITH store_lookup AS (
        SELECT 
            store_id, 
            MIN(store_name) AS store_name
        FROM Ampere.reporting.dim_stores
        GROUP BY store_id
    ),
    order_costs AS (
        SELECT
            order_id,
            SUM(total_cost) AS total_cost,
            MAX(store_id) AS store_id
        FROM Ampere.reporting.dim_costing
        GROUP BY order_id
    ),
    filtered AS (
        SELECT
            f.order_id,
            f.order_date,
            f.total_amount,
            s.store_name
        FROM Ampere.reporting.fct_orders_sales f
        LEFT JOIN order_costs cost ON cost.order_id = f.order_id
        LEFT JOIN store_lookup s ON s.store_id = cost.store_id
        WHERE f.order_date BETWEEN :start_date AND :end_date
          AND (:store_name IS NULL OR s.store_name = :store_name)
    )
    SELECT
        period.period_start,
        COALESCE(filtered.store_name, 'Unknown') AS store_name,
        SUM(filtered.total_amount) AS total_sales
    FROM filtered
    CROSS APPLY (
        SELECT CASE
            WHEN :granularity = 'day' THEN CONVERT(date, filtered.order_date)
            ELSE DATEFROMPARTS(YEAR(filtered.order_date), MONTH(filtered.order_date), 1)
        END AS period_start
    ) AS period
    GROUP BY period.period_start, COALESCE(filtered.store_name, 'Unknown')
    ORDER BY period.period_start, store_name
    """
)

SALES_TRENDS_SUMMARY_SQL = text(
    """
    WITH store_lookup AS (
        SELECT 
            store_id, 
            MIN(store_name) AS store_name
        FROM Ampere.reporting.dim_stores
        GROUP BY store_id
    ),
    order_costs AS (
        SELECT
            order_id,
            SUM(total_cost) AS total_cost,
            MAX(store_id) AS store_id
        FROM Ampere.reporting.dim_costing
        GROUP BY order_id
    ),
    filtered AS (
        SELECT
            f.order_id,
            f.order_date,
            f.total_amount,
            s.store_name
        FROM Ampere.reporting.fct_orders_sales f
        LEFT JOIN order_costs cost ON cost.order_id = f.order_id
        LEFT JOIN store_lookup s ON s.store_id = cost.store_id
        WHERE f.order_date BETWEEN :start_date AND :end_date
          AND (:store_name IS NULL OR s.store_name = :store_name)
    )
    SELECT
        period.period_start,
        SUM(filtered.total_amount) AS total_sales,
        COUNT(DISTINCT filtered.order_id) AS total_orders,
        CASE
            WHEN COUNT(DISTINCT filtered.order_id) = 0 THEN 0
            ELSE SUM(filtered.total_amount) / COUNT(DISTINCT filtered.order_id)
        END AS avg_order_value
    FROM filtered
    CROSS APPLY (
        SELECT CASE
            WHEN :granularity = 'day' THEN CONVERT(date, filtered.order_date)
            ELSE DATEFROMPARTS(YEAR(filtered.order_date), MONTH(filtered.order_date), 1)
        END AS period_start
    ) AS period
    GROUP BY period.period_start
    ORDER BY period.period_start
    """
)

TOP_STORES_SQL = text(
    """
    WITH store_lookup AS (
        SELECT 
            store_id, 
            MIN(store_name) AS store_name
        FROM Ampere.reporting.dim_stores
        GROUP BY store_id
    ),
    order_costs AS (
        SELECT
            order_id,
            SUM(total_cost) AS total_cost,
            MAX(store_id) AS store_id
        FROM Ampere.reporting.dim_costing
        GROUP BY order_id
    ),
    filtered AS (
        SELECT
            f.order_id,
            f.total_amount,
            COALESCE(cost.total_cost, 0) AS total_cost,
            COALESCE(del.tariff, 0) AS tariff,
            s.store_name
        FROM Ampere.reporting.fct_orders_sales f
        LEFT JOIN order_costs cost ON cost.order_id = f.order_id
        LEFT JOIN store_lookup s ON s.store_id = cost.store_id
        LEFT JOIN Ampere.reporting.dim_delivery_cost del ON del.order_id = f.order_id
        WHERE f.order_date BETWEEN :start_date AND :end_date
          AND (:store_name_filter IS NULL OR s.store_name = :store_name_filter)
    )
    SELECT
        store_name,
        CASE
            WHEN COUNT(DISTINCT order_id) = 0 THEN 0
            ELSE SUM(total_amount) / COUNT(DISTINCT order_id)
        END AS avg_order_value,
        SUM(total_amount) AS total_sales,
        SUM(total_amount - total_cost - tariff) AS total_gp
    FROM filtered
    WHERE store_name IS NOT NULL
    GROUP BY store_name
    ORDER BY total_sales DESC
    OFFSET 0 ROWS FETCH NEXT :limit ROWS ONLY
    """
)


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


def _rows_to_dicts(result: Result) -> List[Dict[str, Any]]:
    rows = result.fetchall()
    columns = result.keys()
    return [dict(zip(columns, row)) for row in rows]


def _to_float(value: Any) -> float:
    if value is None:
        return 0.0
    if isinstance(value, Decimal):
        return float(value)
    return float(value)


def run_test_query():
    """Runs the configured SQL slice and returns rows as list of dicts."""
    settings = get_settings()
    limit = settings.sql_query_limit

    engine = get_engine()
    stmt = text(settings.sql_test_query)
    bound_stmt = stmt.bindparams(limit=limit)

    with engine.connect() as conn:
        result = conn.execute(bound_stmt)
        rows = _rows_to_dicts(result)

    return {"row_count": len(rows), "rows": rows, "limit_applied": limit}


def run_sales_summary(filters: Dict[str, Any]) -> Dict[str, float]:
    engine = get_engine()
    with engine.connect() as conn:
        row = conn.execute(SUMMARY_SQL, filters).mappings().fetchone()

    if not row:
        return {"sales": 0.0, "cost_of_sales": 0.0, "gross_profit": 0.0, "total_orders": 0}

    return {
        "sales": _to_float(row["sales"]),
        "cost_of_sales": _to_float(row["cost_of_sales"]),
        "gross_profit": _to_float(row["gross_profit"]),
        "total_orders": int(row["total_orders"]) if row["total_orders"] is not None else 0,
    }


def run_sales_trends(filters: Dict[str, Any], granularity: str) -> List[Dict[str, Any]]:
    params = {**filters, "granularity": granularity}
    engine = get_engine()
    with engine.connect() as conn:
        store_rows = _rows_to_dicts(conn.execute(SALES_TRENDS_STORE_SQL, params))
        summary_rows = _rows_to_dicts(conn.execute(SALES_TRENDS_SUMMARY_SQL, params))

    for row in store_rows:
        row["total_sales"] = _to_float(row["total_sales"])

    for row in summary_rows:
        row["total_sales"] = _to_float(row["total_sales"])
        row["avg_order_value"] = _to_float(row["avg_order_value"])
        row["total_orders"] = (
            int(row["total_orders"]) if row["total_orders"] is not None else 0
        )

    return {"store_rows": store_rows, "summary_rows": summary_rows}


def run_top_stores(filters: Dict[str, Any], limit: int) -> List[Dict[str, Any]]:
    params = {
        **filters,
        "limit": limit,
        "store_name_filter": filters.get("store_name"),
    }
    engine = get_engine()
    with engine.connect() as conn:
        result = conn.execute(TOP_STORES_SQL, params)
        rows = _rows_to_dicts(result)

    for row in rows:
        row["avg_order_value"] = _to_float(row["avg_order_value"])
        row["total_sales"] = _to_float(row["total_sales"])
        row["total_gp"] = _to_float(row["total_gp"])
        row["gross_profit_pct"] = (
            (row["total_gp"] / row["total_sales"]) * 100 if row["total_sales"] not in (None, 0) else 0.0
        )
    return rows


def run_filter_options() -> Dict[str, List[str]]:
    engine = get_engine()
    store_names: List[str] = []
    with engine.connect() as conn:
        store_names = [
            name
            for name in conn.execute(
                text(
                    "SELECT DISTINCT store_name FROM Ampere.reporting.dim_stores "
                    "WHERE store_name IS NOT NULL ORDER BY store_name"
                )
            ).scalars()
            if name
        ]
    return {"stores": store_names}
