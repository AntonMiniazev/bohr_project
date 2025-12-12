## Terraform (libvirt) for ampere-main

Declarative KVM/libvirt provisioning that renders cloud-init and kubeadm configs:
- Cloud-init templates: `templates/cloud-init/control-plane.tpl`, `templates/cloud-init/worker.tpl`
- kubeadm templates: `templates/kubeadm/kubeadm-init.yaml.tpl`, `templates/kubeadm/kubeadm-join.yaml.tpl`
- Inputs: `terraform.tfvars` (ssh_public_keys list, control_plane/worker specs, network defaults, pod/service CIDRs, join HTTP bind/port)

### Prereqs (Ubuntu KVM host)
- libvirt + qemu running, Terraform installed.
- Ubuntu cloud image (e.g., `jammy-server-cloudimg-amd64.img`) on the host.

### Run
```bash
cd terraform/libvirt
terraform init
terraform apply -var-file=terraform.tfvars
```

### Notes
- Control-plane renders kubeadm-init, runs kubeadm init, and serves token/hash/join.sh over HTTP for workers (bind/port configurable).
- Workers render kubeadm-join and retry join until the API is ready.
- SSH keys support multiple authorized keys (list).
- Network gateway/DNS/prefix come from tfvars; adjust to your LAN.
- Control-plane cloud-init installs Calico; storage provisioner (local-path) is managed declaratively via Helmfile.
