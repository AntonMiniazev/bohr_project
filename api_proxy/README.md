# FastAPI SQL Proxy

Minimal FastAPI application that exposes the curated SQL Server datamart through a hardened HTTPS endpoint. The service connects to SQL Server exclusively through the Tailscale address and limits every response to a bounded row count.

## Project layout

```
api_proxy/
  app/
    __init__.py
    config.py
    database.py
    main.py
  Dockerfile
  README.md
```

## Prerequisites

- Python 3.12+ on the Windows working machine (local development) or on whichever host will run the proxy.
- [uv](https://github.com/astral-sh/uv) CLI for managing virtual environments and dependencies. Install once on Windows:
  ```powershell
  pip install uv
  ```
- Microsoft ODBC Driver 18 for SQL Server installed on that host:
  - **Windows dev box**: download from Microsoft (`msodbcsql.msi`) and run the installer.
  - **Ubuntu server / public host**: `sudo apt install msodbcsql18 unixodbc-dev`.
- Network path to the SQL Server through Tailscale (e.g., `100.85.35.82:14330` from Phase 1).

## Configuration

Create a local `.env` under `api_proxy/` (git-ignored) for development. Production secrets live only on `/opt/api-proxy/.env` in the Hetzner host.

```bash
cat <<'EOF' > /c/Users/likelol/Projects/bohr_project/api_proxy/.env
SQL_SERVER_HOST=100.85.35.82
SQL_SERVER_PORT=14330
SQL_SERVER_DB=Ampere
SQL_SERVER_USER=sa
SQL_SERVER_PASSWORD=***replace***
SQL_QUERY_LIMIT=100
SQL_TEST_QUERY=SELECT TOP (:limit) * FROM [reporting].[dim_stores]
EOF
```

Key variables:

| Variable | Description |
| --- | --- |
| `SQL_SERVER_HOST` | Tailscale IP or MagicDNS name of the Ubuntu server. |
| `SQL_SERVER_PORT` | SQL listener port (14330). |
| `SQL_SERVER_DB` | Target database/catalog name. |
| `SQL_SERVER_USER` / `SQL_SERVER_PASSWORD` | SQL Server credentials (never commit). |
| `SQL_QUERY_LIMIT` | Max rows returned per call; enforced server-side. |
| `SQL_TEST_QUERY` | Parameterized query used by `/test-query`. Defaults to a placeholder view; adjust to one of your curated views. |
| `API_KEY` | Secret string required in the `X-API-Key` header for every request. |

All credentials stay in `.env` (listed in `.gitignore`).

## Local run & validation

1. **Install dependencies with uv** (run from the repo root so `pyproject.toml` is discovered):
   ```bash
   cd /c/Users/likelol/Projects/bohr_project
   uv venv                # creates .venv next to the project
   source .venv/Scripts/activate
   uv sync
   ```

2. **Start FastAPI** (same bash terminal, venv already active):
   ```bash
   cd /c/Users/likelol/Projects/bohr_project/api_proxy
   uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

3. **Smoke tests** (from the same machine, still on Tailscale):
   ```bash
   curl -H "X-API-Key: $API_KEY" http://127.0.0.1:8000/health
   curl -H "X-API-Key: $API_KEY" http://127.0.0.1:8000/test-query
   ```

   The second call returns JSON with a `rows` array limited by `SQL_QUERY_LIMIT`.

4. **SQL connectivity validation**:
   - Stop Tailscale on Windows and re-run `/test-query` -> it must fail (verifies tunnel-only access).
   - Reconnect to Tailscale afterward for continued development.

## Container build & deployment

### Continuous build

`.github/workflows/build-api-proxy.yml` builds the Docker image with `uv sync` (using `pyproject.toml` + `uv.lock`) and pushes it to `ghcr.io/<repo-owner>/bohr-sql-proxy` on every push.

### Manual run on Hetzner host

1. Create the runtime config directory and `.env` file (never stored in Git):
   ```bash
   sudo mkdir -p /opt/api-proxy
   sudo tee /opt/api-proxy/.env >/dev/null <<'EOF'
   SQL_SERVER_HOST=100.85.35.82
   SQL_SERVER_PORT=14330
   SQL_SERVER_DB=Ampere
   SQL_SERVER_USER=sa
   SQL_SERVER_PASSWORD=***replace***
   SQL_QUERY_LIMIT=100
   SQL_TEST_QUERY=SELECT TOP (:limit) * FROM [reporting].[dim_stores]
   EOF
   ```

2. Deploy with Docker Compose (image pre-built in GHCR):
   ```bash
   cd /root/bohr_project
   docker compose pull api-proxy
   docker compose up -d api-proxy
   ```

3. Verify:
   ```bash
   curl -H "X-API-Key: $API_KEY" http://localhost:8080/health
   curl -H "X-API-Key: $API_KEY" http://localhost:8080/test-query
   ```

## API endpoints

All endpoints require the `X-API-Key` header and support ISO date filters (`YYYY-MM-DD`). When dates are omitted, the backend defaults to the last 30 days ending today. `store_name` / `zone_name` filters accept exact matches.

- `GET /metrics/summary`
  - Returns aggregate metrics `{sales, cost_of_sales, gross_profit}` after filters.
  - Example:
    ```bash
    curl -H "X-API-Key: $API_KEY" \
      "https://api.ampere-data.work/metrics/summary?start_date=2025-10-01&end_date=2025-10-31&zone_name=North"
    ```

- `GET /metrics/sales-trends`
  - Query params: `granularity=month|day` (default month) plus standard filters.
  - Response contains `store_rows` (sales per store per period) and `summary_rows` (overall totals with average order value) so the UI can render stacked bars + line.

- `GET /metrics/top-stores`
  - Query params: `limit` (default 5, max 25) plus filters.
  - Returns ordered rows with `store_name`, `avg_order_value`, `total_sales`, `total_gp`.

- `GET /filters/options`
  - Returns `{stores: [...], zones: [...]}` for populating dropdown filters.

Use these endpoints from the Streamlit app to power all visuals described in `data_structure.md`.

## Next steps

- Configure TLS/front-door proxy on the Hetzner host so the public endpoint is HTTPS-only.
- Add request authentication (e.g., API key or OAuth) before exposing `/test-query` publicly.
- Expand to multiple curated endpoints or stored procedures with stricter query whitelisting.
