# Helmfile: Cluster Services Deployment

This Helmfile configuration deploys platform services into the Kubernetes cluster after the control plane and workers are ready. It installs KEDA, PostgreSQL, MinIO, and Airflow, with secrets managed by SOPS and Azure Key Vault.

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
- `keda`: KEDA operator and metrics components.
- `ampere`: PostgreSQL, MinIO, and Airflow workloads.

Services and roles
- [PostgreSQL](services/postgresql) (custom chart): metadata and operational databases for Airflow and application workloads.
- [MinIO](services/minio) (custom chart): S3-compatible object storage.
- [Airflow](https://airflow.apache.org/docs/helm-chart/1.18.0/) (apache-airflow chart): orchestration for pipelines and DAG execution.
- [KEDA](https://github.com/kedacore/charts) (kedacore chart): event-driven autoscaling for Airflow workers.

Versions (current defaults)
- KEDA chart `2.16.0`: [`helmfile.yaml`](helmfile.yaml)
- Airflow chart `1.18.0`: [`helmfile.yaml`](helmfile.yaml)
- Airflow image tag: [`env.yaml`](env.yaml)
- PostgreSQL image tag `16`: [`env.yaml`](env.yaml)
- MinIO image tag `RELEASE.2025-07-23T15-54-02Z`: [`env.yaml`](env.yaml)

Secrets handling
- PostgreSQL and Airflow credentials are referenced via `secrets:` entries in [`helmfile.yaml`](helmfile.yaml) and decrypted by the helm-secrets plugin.
- MinIO credentials are stored as a SOPS-encrypted Secret manifest and applied via a `preapply` hook.

Credential templates
- [`services/postgresql/postgresql.credentials_template.yaml`](services/postgresql/postgresql.credentials_template.yaml)
- [`services/airflow/airflow.credentials_template.yaml`](services/airflow/airflow.credentials_template.yaml)
- [`services/airflow/airflow.webserver-secret_template.yaml`](services/airflow/airflow.webserver-secret_template.yaml)
- [`services/airflow/git-credentials_template.yaml`](services/airflow/git-credentials_template.yaml)
- [`services/minio/minio.credentials_template.yaml`](services/minio/minio.credentials_template.yaml)

Configuration inputs
- Environment values: [`env.yaml`](env.yaml)
- Release definitions: [`helmfile.yaml`](helmfile.yaml)
- Service values and charts: [`services/`](services/)

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
