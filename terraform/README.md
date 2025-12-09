## Terraform layouts

- `terraform/libvirt` — KVM/libvirt provisioning for ampere-main:
  - Templates under `templates/cloud-init` (VM bootstrap) and `templates/kubeadm` (kubeadm init/join).
  - Inputs via `terraform.tfvars` (SSH keys list, control-plane/worker specs, network defaults, pod/service CIDRs, join HTTP bind/port).

### Run (Ubuntu KVM host)
```bash
cd terraform/libvirt
terraform init
terraform apply -var-file=terraform.tfvars
```

Notes:
- Control-plane renders kubeadm-init.yaml, runs kubeadm init, and serves token/hash/join.sh over HTTP for workers.
- Workers render kubeadm-join.yaml and retry join until the API is ready.
- NoCloud tri-file can be derived from the templates if needed; current flow uses single user-data.
