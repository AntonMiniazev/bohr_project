# Architecture Documentation

## Purpose
Prepared C4-like documentation for the self-service project backend on the home-lab. The goal is to communicate how the Developer operates the home-lab data platform, how synthetic data is transformed into curated SQL Server marts, and how the public dashboard consumes those metrics without exposing private infrastructure.
Directory covers architecture of three projects:
- [Ampere](https://github.com/AntonMiniazev/ampere_project): specifies on ETL processes
- [Bohr](https://github.com/AntonMiniazev/bohr_project): specifies on backend deployment on home-lab
- [CurrieM](https://github.com/AntonMiniazev/curiem_project): specifies on external reporting


## Diagram inventory
| View | Focus | Source | Rendered Output |
| --- | --- | --- | --- |
| System Context | Developer, key external systems, and the home-lab/public cluster boundaries | `docs/diagrams/context.puml` | `docs/images/Context.svg` |
| Container | Core infrastructure and runtime services within the home-lab cluster | `docs/diagrams/containers.puml` | `docs/images/Containers.svg` |
| Deployment Workflow | Terraform + Cloud-Init + kubeadm provisioning, followed by Helmfile services | `docs/diagrams/workflow.puml` | `docs/images/Workflow.svg` |

## Rendering
`.github/workflows/render-diagrams.yml` renders any updated `.puml` files in CI. When a pull request or push touches `docs/diagrams/**`, the workflow:
1. Installs Java, Graphviz, and PlantUML.
2. Generates SVGs inside `docs/images`.
3. Commits the refreshed diagrams back to the branch via `git-auto-commit-action`.

If working locally, run PlantUML against the `.puml` files and export SVGs to `docs/images`.
