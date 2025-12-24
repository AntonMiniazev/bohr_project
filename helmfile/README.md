# Helmfile: Cluster Services Deployment

This Helmfile configuration deploys platform services into the Kubernetes cluster after the control plane and workers are ready. It installs cert-manager, ingress-nginx, External Secrets Operator, KEDA, PostgreSQL, MinIO, and Airflow, with secrets managed by SOPS and Azure Key Vault.

Guide
- [Helmfile: Cluster Services Deployment](#helmfile-cluster-services-deployment)
  - [Prerequisites](#prerequisites)
  - [Detailed description of deployed infrastructure](#detailed-description-of-deployed-infrastructure)
  - [Steps of deployment](#steps-of-deployment)

## Prerequisites

Required tools
- `kubectl`
- `helm`
- `helmfile`
- `sops`
- Helm plugins: `diff`, `secrets`

Make az login or configure secret decryption environment (Azure Key Vault):
```bash
export AZURE_TENANT_ID=...
export AZURE_CLIENT_ID=...
export AZURE_CLIENT_SECRET=...
export AZURE_KEYVAULT_URL=...
```

Cluster access
- Ensure `KUBECONFIG` points at the target cluster.

## Detailed description of deployed infrastructure

Namespaces
- `cert-manager`: cert-manager CRDs and controllers.
- `ingress-nginx`: ingress-nginx controller and TCP proxying.
- `external-secrets`: External Secrets Operator.
- `keda`: KEDA operator and metrics components.
- `ampere`: application workloads (PostgreSQL, MinIO, Airflow) and ingress resources.

Services and roles
- [cert-manager](https://cert-manager.io/) (jetstack chart): issues TLS certificates for ingress hosts.
- [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) (ingress-nginx chart): ingress controller for HTTP/S and TCP services.
- [External Secrets Operator](https://external-secrets.io/) (external-secrets chart): syncs external secret stores into Kubernetes Secrets.
- [Ingress resources](services/ingress) (custom chart): ingress routes, TCP mappings, and local CA certificates for internal TLS.
- [PostgreSQL](services/postgresql) (custom chart): metadata and operational databases for Airflow and application workloads, exposed through ingress-nginx TCP forwarding with allowlisted networks.
- [MinIO](services/minio) (custom chart): S3-compatible object storage.
- [Airflow](https://airflow.apache.org/docs/helm-chart/1.18.0/) (apache-airflow chart): orchestration for pipelines and DAG execution.
- [KEDA](https://github.com/kedacore/charts) (kedacore chart): event-driven autoscaling for Airflow workers.

Versions (current defaults)
- cert-manager chart `1.16.3`: [`helmfile.yaml`](helmfile.yaml)
- ingress-nginx chart `4.11.2`: [`helmfile.yaml`](helmfile.yaml)
- External Secrets chart `0.10.5`: [`helmfile.yaml`](helmfile.yaml)
- KEDA chart `2.16.0`: [`helmfile.yaml`](helmfile.yaml)
- Airflow chart `1.18.0`: [`helmfile.yaml`](helmfile.yaml)
- Airflow image tag: [`env.yaml`](env.yaml)
- PostgreSQL image tag `16`: [`env.yaml`](env.yaml)
- MinIO image tag `RELEASE.2025-09-07T16-13-09Z-cpuv1`: [`env.yaml`](env.yaml)

Secrets handling
- PostgreSQL and Airflow credentials are referenced via `secrets:` entries in [`helmfile.yaml`](helmfile.yaml) and decrypted by the helm-secrets plugin.
- MinIO credentials are stored as a SOPS-encrypted Secret manifest and applied via a `preapply` hook.
- External Secrets Operator uses SOPS-decrypted Key Vault credentials to sync secrets into Kubernetes.

Credential templates
- [`services/postgresql/postgresql.credentials_template.yaml`](services/postgresql/postgresql.credentials_template.yaml)
- [`services/airflow/airflow.credentials_template.yaml`](services/airflow/airflow.credentials_template.yaml)
- [`services/airflow/airflow.webserver-secret_template.yaml`](services/airflow/airflow.webserver-secret_template.yaml)
- [`services/airflow/git-credentials_template.yaml`](services/airflow/git-credentials_template.yaml)
- [`services/minio/minio.credentials_template.yaml`](services/minio/minio.credentials_template.yaml)
- [`services/external-secrets/external-secrets.credentials_template.yaml`](services/external-secrets/external-secrets.credentials_template.yaml)

Configuration inputs
- Environment values: [`env.yaml`](env.yaml)
- Release definitions: [`helmfile.yaml`](helmfile.yaml)
- Service values and charts: [`services/`](services/)
  - PostgreSQL allowlist CIDRs are defined under `postgresql.access.allowedCidrs`.
  - PostgreSQL TLS can be toggled with `postgresql.tls.enabled` (disabled by default).
  - ingress-nginx TCP NodePort is set with `ingress.controller.tcpNodePorts.postgres`.

## Steps of deployment

1) Configure environment values
- Update node selectors, images, and service settings in [`env.yaml`](env.yaml).

2) Prepare secrets from templates
- Copy each `*_template.yaml` to its non-template name, fill in values, then encrypt with SOPS.

3) Deploy all services
```bash
cd helmfile
helmfile -e [NAMESPACE] apply --skip-diff-on-install
```
Use the environment name defined in [`environments.yaml`](environments.yaml).

Files to review
- [`helmfile.yaml`](helmfile.yaml)
- [`env.yaml`](env.yaml)
- [`services/postgresql`](services/postgresql)
- [`services/minio`](services/minio)
- [`services/airflow`](services/airflow)
- [`services/keda`](services/keda)
- [`services/external-secrets`](services/external-secrets)
