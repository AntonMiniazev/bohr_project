## Overview
This repository is a sandbox for provisioning a KVM/libvirt VM fleet and deploying a Kubernetes-based data platform. It uses Terraform + Cloud-Init for VM bootstrap, kubeadm for cluster initialization, and Helmfile to deploy infrastructure services and workloads (cert-manager, ingress-nginx, External Secrets Operator, PostgreSQL, MinIO, Airflow, Spark Operator, Spark Connect, KEDA, Prometheus/Grafana, Unity Catalog OSS). Services are exposed through ingress routes and TCP forwarding for internal access.

## Repository layout
- [`terraform/`](terraform/) VM provisioning with libvirt, Cloud-Init, and kubeadm.
- [`helmfile/`](helmfile/) Helmfile releases and service charts for cluster workloads.
- [`custom_images/`](custom_images/) Dockerfiles for custom images published to a registry.
- [`docs/`](docs/) C4-style architecture docs and diagrams.
  - [System Context diagram](docs/images/Context.svg)
  - [Internal Cluster Containers diagram](docs/images/Internal-Cluster-Containers.svg)
  - [Deployment workflow diagram](docs/images/Workflow.svg)

## Guides
- [Terraform guide](terraform/README.md)
- [Helmfile guide](helmfile/README.md)
- [Architecture docs](docs/README.md)

## High-level workflow
1) Provision VMs on the KVM host with Terraform.
2) Bootstrap Kubernetes with kubeadm + Cilium.
3) Deploy platform services, ingress, and secrets with Helmfile.

## Current delivery status
- Step 1: Internal home-lab cluster on KVM/libvirt completed.
- Step 2: Core platform services via Helmfile completed.
- Step 5: CI/CD image build and push automation completed.
- Step 6: Spark Connect deployment completed (`sparkconnect.local`).
- Step 7: Unity Catalog OSS deployment completed (`ucatalog.local`).
- Step 3 and Step 4 remain postponed (public API cluster and custom image refactor rollout).

## Access endpoints (home Wi-Fi DNS)
- `airflow.local`
- `minio.local`
- `s3.minio.local`
- `sparkconnect.local`
- `ucatalog.local`

## Secrets
Secrets are stored encrypted with SOPS + Azure Key Vault. Use the credential templates under [`helmfile/services`](helmfile/services) and the Terraform variables template [`terraform/libvirt/terraform_template.tfvars_`](terraform/libvirt/terraform_template.tfvars_) to create new values before encrypting them.
