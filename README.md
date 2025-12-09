## Overview
Declarative scaffolding for the refactored Ampere platform:
- Cloud-Init templates (rendered by Terraform) for KVM/libvirt VMs.
- kubeadm configs for ampere-main and ampere-api clusters (templated).
- Helmfile skeleton for internal (home) and external (api) workloads.
- Secrets encrypted with SOPS + Azure KeyVault.
- Terraform (libvirt) to provision KVM VMs declaratively (no manual virt-install or cloud-localds).

## Layout
- `helmfile/` — Helmfile with environments `home` and `api`; values per env; secrets referenced via SOPS.
- `charts/` — legacy/local charts used by Helmfile.
- `terraform/libvirt/` — Terraform config + templates (cloud-init + kubeadm) to create control-plane and worker VMs.
- `env_files/.env` — local Azure/key settings for SOPS (gitignored).
- `api-host/` — API host assets (if needed).
- `docs/` — diagrams and docs (update per AGENTS.md).

## SOPS usage (Azure KeyVault)
Prereqs: set secrets in shell/CI:
```
AZURE_TENANT_ID=...
AZURE_CLIENT_ID=...
AZURE_CLIENT_SECRET=...
AZURE_KEYVAULT_URL=https://az-ampere-kv.vault.azure.net/
```
Encrypt/decrypt:
```
sops --config .sops.yaml --encrypt --in-place secrets/<component>/credentials.yaml
sops --config .sops.yaml -d secrets/<component>/credentials.yaml
```

## Deployment flow (GitOps-first, actionable)
1) Prepare placeholders (Windows dev box or wherever you edit Git):
   - `helmfile/environments/*`: align node names/IPs, ports, images with desired versions.
   - `helmfile/secrets/*`: keep encrypted with SOPS.
   - `terraform/libvirt/terraform.tfvars`: set ssh_public_keys (list), control_plane block (hostname/ip/CPU/RAM/disk), worker_nodes map (ip/CPU/RAM/disk), base image path, optional k8s_version/pod/service CIDRs, network gateway/DNS/prefix, join HTTP bind/port.
   - `env_files/.env`: AZURE_* for SOPS/KeyVault (not committed).

2) Create ampere-main control-plane VM (Ubuntu KVM host):
   ```bash
   cd terraform/libvirt
   terraform init
   terraform apply -var-file=terraform.tfvars
   ```
   - Control-plane cloud-init installs containerd/kubeadm, runs kubeadm init via systemd, writes kubeadm-init.yaml (templated), and serves token/hash/join.sh over HTTP (bind/port from tfvars).

3) Bring up ampere-main workers (Ubuntu KVM host):
   - Add worker entries to `terraform.tfvars` (memory/vcpu/disk/ip); templated worker cloud-init is rendered per node with kubeadm join YAML populated from control-plane token/hash.
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```
   - Worker systemd unit retries kubeadm join until the API is ready.

4) Validate cluster core (Ubuntu KVM host or Windows with KUBECONFIG):
   ```bash
   kubectl get nodes
   ```
   Install CNI + storage:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/tigera-operator.yaml
   kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/custom-resources.yaml
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
   ```

5) Deploy workloads to ampere-main (Windows dev box or control-plane with kubectl and AZURE_* set):
   ```bash
   cd helmfile
   helmfile -e home apply
   ```

6) ampere-api control-plane (Ubuntu KVM host):
   - Ensure `cloud-init/ampere-api.yaml` and `kubeadm/ampere-api-control-plane.yaml` have `<PUBLIC_IP>` set.
   - Add an ampere-api VM block in Terraform or run a separate Terraform workspace.
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```
   - Install CNI/storage similar to step 4 (podSubnet/serviceSubnet differ per kubeadm config).

7) Deploy workloads to ampere-api (Windows dev box or API node with kubectl and AZURE_* set):
   ```bash
   cd helmfile
   helmfile -e api apply
   ```

Adjust values under `helmfile/environments/*` to match node names/IPs and ingress settings before deploying.

## What to fill (placeholder map)
- `cloud-init/ampere-main-control-plane.yaml`: SSH public key, static IP/gateway.
- `cloud-init/ampere-api.yaml`: SSH public key, `<PUBLIC_IP>`, DNS if needed.
- `kubeadm/ampere-api-control-plane.yaml`: set `<PUBLIC_IP>` (Hetzner node).
- `env_files/.env`: set AZURE_* (and update any rotated Azure secret values).
- `terraform/libvirt/terraform.tfvars`: set ssh_public_key, control_plane block, worker_nodes map, base image path, network.
- `helmfile/environments/home/*.values.yaml`: align node names/IPs, ports, images with desired versions (reuse old_infra charts: ms-chart, minio-chart, airflow-chart).
- `helmfile/environments/api/*.values.yaml`: set ingress/service details for public API as needed.
