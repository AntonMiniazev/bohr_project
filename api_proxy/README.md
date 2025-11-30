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
  requirements.txt
  .env.example
```

## Prerequisites

- Python 3.11+ on the Windows working machine (local development) or on whichever host will run the proxy.
- [uv](https://github.com/astral-sh/uv) CLI for managing virtual environments and dependencies. Install once on Windows:
  ```powershell
  pip install uv
  ```
- Microsoft ODBC Driver 18 for SQL Server installed on that host:
  - **Windows dev box**: download from Microsoft (`msodbcsql.msi`) and run the installer.
  - **Ubuntu server / public host**: `sudo apt install msodbcsql18 unixodbc-dev`.
- Network path to the SQL Server through Tailscale (e.g., `100.85.35.82:14330` from Phase 1).

## Configuration

Copy the example env file and fill it in. This stays local for development; production secrets live on the host under `/opt/api-proxy/.env`.

```bash
# VS Code bash terminal (Windows dev box)
cd /c/Users/likelol/Projects/bohr_project/api_proxy
cp .env.example .env
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

All credentials stay in `.env` (listed in `.gitignore`).

## Local run & validation

1. **Install dependencies with uv** (VS Code bash terminal on Windows with venv auto-activation):
   ```bash
   cd /c/Users/likelol/Projects/bohr_project/api_proxy
   uv venv                # creates .venv next to the project
   source .venv/Scripts/activate
   uv pip sync requirements.txt
   ```

2. **Start FastAPI** (same bash terminal, venv already active):
   ```bash
   uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

3. **Smoke tests** (from the same machine, still on Tailscale):
   ```bash
   curl http://127.0.0.1:8000/health
   curl http://127.0.0.1:8000/test-query
   ```

   The second call returns JSON with a `rows` array limited by `SQL_QUERY_LIMIT`.

4. **SQL connectivity validation**:
   - Stop Tailscale on Windows and re-run `/test-query` -> it must fail (verifies tunnel-only access).
   - Reconnect to Tailscale afterward for continued development.

## Container build & deployment

### Continuous build

`.github/workflows/build-api-proxy.yml` builds the `api_proxy` Docker image and pushes it to `ghcr.io/<repo-owner>/bohr-sql-proxy` on every push.

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
   curl http://localhost:8080/health
   curl http://localhost:8080/test-query
   ```

## Next steps

- Configure TLS/front-door proxy on the Hetzner host so the public endpoint is HTTPS-only.
- Add request authentication (e.g., API key or OAuth) before exposing `/test-query` publicly.
- Expand to multiple curated endpoints or stored procedures with stricter query whitelisting.
