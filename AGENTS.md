# Ampere DevOps Architecture Specification  
# Purpose
Refactoring project: deployment of a reproducible, declarative, OSS-based architecture for the **Ampere** Data Engineering Platform, now extended into a **dual-cluster topology**:

1. **Home-Lab Kubernetes Cluster (internal workloads)**  
2. **Hetzner Cloud Kubernetes Cluster (public API workloads)**  

Outdated **Vagrant + VirtualBox** stack replaced with **KVM/libvirt**: old_infra folder contain old vagrant file and scripts for deployment.
KVM/libvirt (Type-1 hypervisor) provides near-native performance and reflects realistic production deployments.

The methodology eliminates shell provisioning, enforces GitOps, and relies on:

[Infrastructure steps]:
- Terraform: Cloud-Init + KVM/libvirt (use documents from https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.0/docs as we are using dmacvicar provider libvirt version 0.9.0)  
- K8s   
- Cilium as CNI (https://docs.cilium.io/en/stable/#getting-started)
- Rancher local-path-provisioner (https://github.com/rancher/local-path-provisioner/tree/master)

[Service deployment step] 
- Helmfile
- **SOPS + Azure KeyVault KMS (foundational requirement)**  
- Docker images (GHCR) for services

---

# Core Principles
0. **Roles**
   - User (developer)
   - Agent (mentoring developer) 

1. **Agent–Developer workflow relationships**
   - Agent may request environment details as needed.
   - Workflow:
     - When I provide new context for current config update - just change files yourself
     - Agent acts like a Senior DevOps architect and mentor of user
     - Agent prepares/updates config files
     - (MOST IMPORTANT!) Agent explains execution steps (which commands to run) and where they must be performed:
       - Windows Dev Machine
       - Ubuntu KVM host
       - ampere-main cluster (on Ubuntu host)
       - ampere-api cluster

2. **Three Independent Components**
   - **Laptop** — development environment
   - **ampere-main** — home-lab server on Ubuntu host. Connected to home wi-fi network Ubuntu host (access through ssh oppie@oppie-server)
   - **ampere virtual machines** — VMs deployed on ampere-main:
     - ampere-k8s-master (access through ssh ampere@ampere-k8s-master)
     - ampere-k8s-node1 (access through ssh ampere@ampere-k8s-node1)
     - ampere-k8s-node2 (access through ssh ampere@ampere-k8s-node2)
     - ampere-k8s-node3 (access through ssh ampere@ampere-k8s-node3)
   - **ampere-api** — cloud API platform

3. **No mutable shell provisioning**
   - All .sh provisioning scripts to be deprecated is the main target
   - Idempotency of terraform appy operation accross any Ubuntu servers

4. **Foundational GitOps Secret Management**
   - SOPS + Azure KeyVault integration  
   - All secrets are encrypted in Git from the beginning  
   - Helmfile never touches plaintext  

---

# System Context Overview and Stack

## Home-Lab Kubernetes Cluster
(Internal workloads, KVM/libvirt VMs)

- Cloud-Init provisioning
- kubeadm cluster bootstrap
- PostgreSQL, MinIO, dbt/DuckDB, Airflow (PostgreSQL backend)
- Internal-only networking
- SOPS secrets consumed via Helmfile

## Hetzner API Kubernetes Cluster
(Public API + website)

- Single-node kubeadm control-plane  
- Cloud-Init provisioning on Hetzner VM  
- Ingress + cert-manager  
- Public HTTPS + API-key / JWT  
- GHCR Docker images  
- Tailscale optional for admin access  

## OSS Instruments
- Terraform
- Cloud-Init  
- K8s
- Helmfile  
- SOPS + KeyVault  
- Docker images

## Terraform deployment schema (terraform\libvirt\main.tf):
Master (terraform\libvirt\templates\cloud-init\control-plane.tpl + terraform\libvirt\templates\bootstrap\netplan.yaml.tpl):
   Stage 1 Master deployemtn (terraform\libvirt\templates\bootstrap\bootstrap-init.sh.tpl):
      - networking/ssh stable
      - Kernel / systctl modifications including Cilium preparation
      - Preparation for k8s + Cilium installation and master availability
      - emits OS_READY marker

   Stage 2 k8s on Master configuration (terraform\libvirt\templates\bootstrap\bootstrap-k8s.sh.tpl):
      - conntrack containerd kubelet kubeadm kubectl installation and enablement
      - kubeadm and kubeconfig modification
      - kube-apiserver ready validation (6443 + /readyz stable)
      - emits CONTROL_PLANE_CREATED marker

   Stage 3 k8s configuration on master (terraform\libvirt\templates\bootstrap\bootstrap-addons.sh.tpl):
      - cni-installation (Cilium) after API_STABLE
      - storage installation (rancher local-path)
      - Helm / Helmfile / SOPS
      - kubeadm-write-join.service -> kubeadm-join-http.service from 
  
Workers (terraform\libvirt\templates\cloud-init\worker.tpl + terraform\libvirt\templates\bootstrap\netplan.yaml.tpl):
   Stage 4 workers configuration (terraform\libvirt\templates\cloud-init\worker.tpl):
      - networking/ssh stable
      - Kernel / systctl modifications including Cilium preparation
      - Preparation for k8s + Cilium installation and master availability
      - kubeadm-join.service - connection to the cluster
      - conntrack containerd kubelet kubeadm kubectl installation and enablement
---

# Assumptions

1. All deployment files in old repo `/old_infra` are operational and can be used for reference.
2. New architecture must be isolated from old one.
3. Existing helm charts may be reused after refactoring.  
4. Home wi-fi Static DNS configured:
   - minio.local - 192.168.1.29
   - airflow.local - 192.168.1.29
   - s3.minio.local - 192.168.1.29
5. Ubuntu host NGINX configs in `/nginx_ubuntu_host`, to be updated for the refactored infrastructure
6. Actual variables and secrets for work I will be storing in 'env_files\.env'
---

# Documentation Agent
- Must not reference these instructions in documentation artefacts
- Must update `/docs/diagrams/*.puml` after completing this refactoring project
- Update README.md files and other docs only on direct request

---

# Tasks

## [done] Step 1 — Deploy Internal Home-Lab Cluster (ampere-main)
- Launch libvirt VMs [done] 
- Use Cloud-Init to install prerequisites [done] 
- Use kubeadm to bootstrap control plane and nodes [done]
- Deploy Cilium as CNI [done]

### Acceptance Criteria
- Stable ampere-main cluster on ampere-k8s-main, ampere-k8s-node1, ampere-k8s-node2, ampere-k8s-node3 VMs ready for Helmfile deployment

---

## [done] Step 2 — Deploy Services on ampere-main
- Prepare Helmfile charts for each services based on old deployment from old_infra [done]
- Replace SQL Server deployment with corresponding PostgreSQL deployment [done]
- Organize deployment of PostgreSQL before Airflow. Airflow should use this new PostgreSQL as backend on separate database [done] 

### Acceptance Criteria
- All services are ready to be deployed via Helmfile on ampere-main cluster 

---

## [postponed] Step 3 — Deploy Hetzner API Cluster (ampere-api)
- Create Hetzner VM  
- Provision via Cloud-Init (incl. Tailscale)  
- kubeadm init single-node cluster  
- Deploy ingress + cert-manager  
- Deploy API + website via Helmfile  

### Acceptance Criteria
- Public API over HTTPS  
- API-key logic enforced  
- CI/CD deploys updates  

---

## [postponed] Step 4 — Build and Push Custom Docker Images
- Build API, dbt runner, Airflow plugins, website  
- Push images to GHCR  
- Update Helmfile tags  

### Acceptance Criteria
- Versioned, immutable deployments  
- Rolling updates successful  

---

## [done] Step 5 — Automation Backend Integration
- Configure GitHub Actions or local runner  
- Pipelines:
  - docker build  
  - docker push  
- Support `home` and `api` envs  

### Acceptance Criteria
- Zero-touch deployment  
- Git = single source of truth  

---
