from datetime import date, timedelta
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Query, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader

from .database import (
    get_settings,
    run_filter_options,
    run_sales_summary,
    run_sales_trends,
    run_test_query,
    run_top_stores,
)

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


def _parse_iso_date(value: Optional[str], label: str, fallback: date) -> date:
    if value is None:
        return fallback
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise HTTPException(
            status_code=400, detail=f"{label} must be in YYYY-MM-DD format"
        ) from exc


def _normalize_text(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _build_filters(
    start_date: Optional[str],
    end_date: Optional[str],
    store_name: Optional[str],
    zone_name: Optional[str],
):
    today = date.today()
    default_end = today
    default_start = today - timedelta(days=30)

    start = _parse_iso_date(start_date, "start_date", default_start)
    end = _parse_iso_date(end_date, "end_date", default_end)

    if start > end:
        raise HTTPException(
            status_code=400, detail="start_date must be before end_date"
        )

    return {
        "start_date": start,
        "end_date": end,
        "store_name": _normalize_text(store_name),
        "zone_name": _normalize_text(zone_name),
    }


def _filters_metadata(filters: dict) -> dict:
    return {
        "start_date": filters["start_date"].isoformat(),
        "end_date": filters["end_date"].isoformat(),
        "store_name": filters["store_name"],
        "zone_name": filters["zone_name"],
    }


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


@app.get("/metrics/summary")
def metrics_summary(
    start_date: Optional[str] = Query(None, description="ISO date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="ISO date (YYYY-MM-DD)"),
    store_name: Optional[str] = Query(None),
    zone_name: Optional[str] = Query(None),
    api_key: str = Depends(require_api_key),
):
    filters = _build_filters(start_date, end_date, store_name, zone_name)
    summary = run_sales_summary(filters)
    return {"filters": _filters_metadata(filters), "summary": summary}


@app.get("/metrics/sales-trends")
def sales_trends(
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    store_name: Optional[str] = Query(None),
    zone_name: Optional[str] = Query(None),
    granularity: str = Query("month", regex="^(day|month)$"),
    api_key: str = Depends(require_api_key),
):
    filters = _build_filters(start_date, end_date, store_name, zone_name)
    granularity_normalized = granularity.lower()
    trend_payload = run_sales_trends(filters, granularity_normalized)
    return {
        "filters": _filters_metadata(filters),
        "granularity": granularity_normalized,
        "store_rows": trend_payload["store_rows"],
        "summary_rows": trend_payload["summary_rows"],
    }


@app.get("/metrics/top-stores")
def top_stores(
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    store_name: Optional[str] = Query(None),
    zone_name: Optional[str] = Query(None),
    limit: int = Query(5, ge=1, le=25),
    api_key: str = Depends(require_api_key),
):
    filters = _build_filters(start_date, end_date, store_name, zone_name)
    rows = run_top_stores(filters, limit)
    return {"filters": _filters_metadata(filters), "limit": limit, "rows": rows}


@app.get("/filters/options")
def filter_options(api_key: str = Depends(require_api_key)):
    return run_filter_options()
