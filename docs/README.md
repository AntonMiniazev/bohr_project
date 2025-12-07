# Architecture Documentation

## Purpose
Prepared C4-like documentation for the self-service project backend on the home-lab. The goal is to communicate how the Developer operates the home-lab data platform, how synthetic data is transformed into curated SQL Server marts, and how the public dashboard consumes those metrics without exposing private infrastructure.
Directory covers architecture of three projects:
- [Ampere](https://github.com/AntonMiniazev/ampere_project): specifies on ETL processes
- [Bohr](https://github.com/AntonMiniazev/bohr_project): specifies on backend deployment on home-lab
- [CurrieM](https://github.com/AntonMiniazev/curiem_project): specifies on external reporting


## Diagram Inventory
| View | Focus | Source | Rendered Output |
| --- | --- | --- | --- |
| System Context | External viewers, Developer, public services, and the secure home cluster boundary | `docs/diagrams/context.puml` | `docs/images/Context.svg` |
| Container | Compute and storage building blocks across Streamlit Cloud, the public proxy, and Kubernetes workloads | `docs/diagrams/containers.puml` | `docs/images/Containers.svg` |
| Component Workflow | Step-by-step data journey: generation → ingestion → DuckDB/dbt processing → SQL Server gold layer → API proxy → Streamlit | `docs/diagrams/workflow.puml` | `docs/images/Workflow.svg` |

## GitHub Actions Rendering
`.github/workflows/render-diagrams.yml` renders any updated `.puml` files in CI. When a pull request or push touches `docs/diagrams/**`, the workflow:
1. Installs Java, Graphviz, and PlantUML.
2. Generates SVGs inside `docs/images`.
3. Commits the refreshed diagrams back to the branch via `git-auto-commit-action`.

No manual commits of SVG assets are required when the workflow runs on the default branch. If working locally without CI, run the command above to keep images in sync.

## Diagram Highlights
- **Context view**: Shows how the External Viewer accesses the Streamlit dashboard, how the Developer manages both the API proxy and the data platform, and how a tunnel isolates SQL Server and supporting services.
- **Container view**: Details operational components such as Airflow, DuckDB, MinIO, SQL Server, and the FastAPI proxy, plus how the Developer interacts with them through GitOps/automation.
- **Workflow view**: Illustrates the exact processing path from synthetic data generation to the aggregated responses consumed by Streamlit, emphasizing read-only, parametrized access to SQL Server through the encrypted tunnel.

## Operational Guardrails
- Keep references abstract—no credentials, internal IPs, or sensitive hostnames appear in these docs.
- Maintain the API proxy as the single ingress for analytical queries; Streamlit never connects to SQL Server directly.
- Ensure the tunnel process is supervised (systemd/Kubernetes) so the API can always reach SQL Server without opening inbound ports.
- Continue using parametrized SQL patterns within the API to prevent injection and to keep queries index-friendly.
