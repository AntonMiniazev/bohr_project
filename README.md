## Overview
This repository is a sandbox for provisioning a KVM/libvirt VM fleet and deploying a Kubernetes-based data platform. It uses Terraform + Cloud-Init for VM bootstrap, kubeadm for cluster initialization, and Helmfile to deploy services.

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
3) Deploy platform services with Helmfile.

## Secrets
Secrets are stored encrypted with SOPS + Azure Key Vault. Use the credential templates under [`helmfile/services`](helmfile/services) to create new secrets before encrypting them.

## Old infrastructure
- [Old infra](old_infra) Vagrant + VirtualBox previous deployment version.