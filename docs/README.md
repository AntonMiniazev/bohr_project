# Architecture Documentation

## Purpose
C4-like documentation for the infrastructure platform, covering the home-lab Kubernetes cluster, the KVM/libvirt host, and the planned public cluster. The diagrams focus on deployment boundaries, core services, and the GitOps-style delivery flow used to bootstrap and operate the platform.

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
