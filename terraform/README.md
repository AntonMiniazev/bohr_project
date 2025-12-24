# Terraform: KVM/libvirt Kubernetes Deployment

This Terraform module provisions a reproducible Kubernetes cluster on a KVM/libvirt host using Cloud-Init and kubeadm. It creates one control-plane VM and a set of worker VMs, installs the container runtime and Kubernetes components, bootstraps the control plane, and applies core addons (Cilium + local-path-provisioner). Helm, Helmfile, and SOPS are installed on the control plane for later service deployment.

Guide
- [Terraform: KVM/libvirt Kubernetes Deployment](#terraform-kvmlibvirt-kubernetes-deployment)
  - [Prerequisites](#prerequisites)
  - [Detailed description of deployed infrastructure](#detailed-description-of-deployed-infrastructure)
  - [Steps of deployment](#steps-of-deployment)

## Prerequisites

Where to run: Ubuntu KVM host.

Host requirements
- KVM/libvirt stack and supporting tools
- Terraform CLI
- SSH access to the control-plane and worker VMs
- Ubuntu cloud image path or URL

Install host packages:
```bash
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst cloud-image-utils genisoimage
```

Enable libvirt for your user (log out/in after this):
```bash
sudo usermod -aG libvirt "$USER"
sudo usermod -aG kvm "$USER"
```

Install Terraform (example via HashiCorp repo):
```bash
sudo apt-get install -y gnupg software-properties-common

wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update
sudo apt-get install terraform
```

Configure inputs in [`libvirt/terraform.tfvars`](libvirt/terraform.tfvars):
- VM sizes, IPs, SSH keys, base image path/URL
- Network settings (gateway, DNS, prefix)
- Kubernetes, Cilium, Helm, Helmfile, SOPS versions under `packages`

Files to review:
- [`libvirt/main.tf`](libvirt/main.tf)
- [`libvirt/variables.tf`](libvirt/variables.tf)
- [`libvirt/terraform.tfvars`](libvirt/terraform.tfvars)

## Detailed description of deployed infrastructure

VM layout and bootstrap pipeline
- One control-plane VM and N worker VMs are created by `libvirt_domain` resources in [`libvirt/main.tf`](libvirt/main.tf).
- Each VM uses Cloud-Init templates in [`libvirt/templates/cloud-init`](libvirt/templates/cloud-init) to apply netplan and install Kubernetes prerequisites.
- kubeadm initializes the control plane and joins worker nodes.
- Cilium provides the CNI, and local-path-provisioner supplies the default StorageClass.

Components installed on the control plane
- containerd (container runtime)
- kubeadm, kubelet, kubectl (control plane and node agent)
- Cilium agent + operator + envoy (pod networking)
- local-path-provisioner (default storage class)
- Helm, Helmfile, and SOPS (GitOps tooling for later service deployments, ingress, and secrets)

Components installed on worker nodes
- containerd
- kubeadm, kubelet, kubectl
- Cilium agent + envoy

Version sources
- Package versions are defined in `terraform/libvirt/terraform.tfvars` under `packages.*`.

Service exposure (ingress routes and TCP forwarding) is configured later via Helmfile. See [`helmfile/README.md`](../helmfile/README.md).

## Steps of deployment

These steps map directly to the template files in this repository.

1) Terraform orchestration
Where to run: Ubuntu KVM host.
- Terraform renders templates and provisions libvirt resources:
  - [`libvirt/main.tf`](libvirt/main.tf)
  - [`libvirt/variables.tf`](libvirt/variables.tf)
  - [`libvirt/terraform.tfvars`](libvirt/terraform.tfvars)
- Run:
```bash
cd terraform/libvirt
terraform init
terraform apply -var-file=terraform.tfvars
```

2) Stage 1: OS ready (control-plane)
- The VM boots with Cloud-Init, applies static network config, and prepares kernel/sysctl settings required by Kubernetes and Cilium. This stage writes the OS_READY marker.
  - Network plan: [`libvirt/templates/bootstrap/netplan.yaml.tpl`](libvirt/templates/bootstrap/netplan.yaml.tpl)
  - OS bootstrap script: [`libvirt/templates/bootstrap/bootstrap-init.sh.tpl`](libvirt/templates/bootstrap/bootstrap-init.sh.tpl)
  - Cloud-Init unit wiring: [`libvirt/templates/cloud-init/control-plane.tpl`](libvirt/templates/cloud-init/control-plane.tpl)

3) Stage 2: kubeadm init (control-plane)
- Installs containerd and Kubernetes packages, runs `kubeadm init`, and writes kubeconfig. This stage writes the CONTROL_PLANE_CREATED marker.
  - Runtime + control-plane setup: [`libvirt/templates/bootstrap/bootstrap-k8s.sh.tpl`](libvirt/templates/bootstrap/bootstrap-k8s.sh.tpl)
  - kubeadm configuration: [`libvirt/templates/kubeadm/kubeadm-init.yaml.tpl`](libvirt/templates/kubeadm/kubeadm-init.yaml.tpl)

4) Stage 3: cluster addons (control-plane)
- Installs cluster networking and storage defaults. Cilium brings pod networking online, local-path-provisioner provides the default StorageClass, and Helm/Helmfile/SOPS are installed.
  - Addons bootstrap: [`libvirt/templates/bootstrap/bootstrap-addons.sh.tpl`](libvirt/templates/bootstrap/bootstrap-addons.sh.tpl)
  - local-path-provisioner config: [`libvirt/templates/bootstrap/k8s/local-path-configmap.yaml.tpl`](libvirt/templates/bootstrap/k8s/local-path-configmap.yaml.tpl)

5) Stage 4: workers join
- Each worker VM applies network config, installs containerd and Kubernetes node components, then joins the cluster using the join script served by the control plane.
  - Worker bootstrap + join flow: [`libvirt/templates/cloud-init/worker.tpl`](libvirt/templates/cloud-init/worker.tpl)
  - Worker network plan: [`libvirt/templates/bootstrap/netplan.yaml.tpl`](libvirt/templates/bootstrap/netplan.yaml.tpl)
