## Overview
This repository is a sandbox for provisioning a KVM/libvirt VM fleet and deploying a Kubernetes-based data platform. It uses Terraform + Cloud-Init for VM bootstrap, kubeadm for cluster initialization, and Helmfile to deploy infrastructure services and workloads (cert-manager, ingress-nginx, External Secrets Operator, PostgreSQL, MinIO, Airflow, KEDA). Services are exposed through ingress routes and TCP forwarding for internal access.

## Repository layout
- [`terraform/`](terraform/) VM provisioning with libvirt, Cloud-Init, and kubeadm.
- [`helmfile/`](helmfile/) Helmfile releases and service charts for cluster workloads.
- [`custom_images/`](custom_images/) Dockerfiles for custom images published to a registry.
- [`docs/`](docs/) C4-style architecture docs and diagrams.

## Guides
- [Terraform guide](terraform/README.md)
- [Helmfile guide](helmfile/README.md)
- [Architecture docs](docs/README.md)

## High-level workflow
1) Provision VMs on the KVM host with Terraform.
2) Bootstrap Kubernetes with kubeadm + Cilium.
3) Deploy platform services, ingress, and secrets with Helmfile.

## Secrets
Secrets are stored encrypted with SOPS + Azure Key Vault. Use the credential templates under [`helmfile/services`](helmfile/services) to create new secrets before encrypting them.

