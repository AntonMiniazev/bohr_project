## Overview
This repository is a sandbox for provisioning a KVM/libvirt VM fleet and deploying a Kubernetes-based data platform. It uses Terraform + Cloud-Init for VM bootstrap, kubeadm for cluster initialization, and Helmfile to deploy infrastructure services and workloads (cert-manager, ingress-nginx, External Secrets Operator, PostgreSQL, MinIO, Airflow, Spark Operator, KEDA, Prometheus/Grafana). Services are exposed through ingress routes and TCP forwarding for internal access.

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

## Secrets
Secrets are stored encrypted with SOPS + Azure Key Vault. Use the credential templates under [`helmfile/services`](helmfile/services) and the Terraform variables template [`terraform/libvirt/terraform_template.tfvars_`](terraform/libvirt/terraform_template.tfvars_) to create new values before encrypting them.

