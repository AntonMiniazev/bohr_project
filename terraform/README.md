## Terraform layouts

- `terraform/libvirt` — KVM/libvirt provisioning for ampere-main:
  - Templates under `templates/cloud-init` (VM bootstrap) and `templates/kubeadm` (kubeadm init/join).
  - Inputs via `terraform.tfvars` (SSH keys list, control-plane/worker specs, network defaults, pod/service CIDRs, join HTTP bind/port).

### Current flow
- Control-plane boots with cloud-init, runs `bootstrap-master.service` (kubeadm init + Calico apply), and serves join artifacts over HTTP.
- Workers boot with cloud-init, install kube bits (incl. conntrack, sysctls for ip_forward), and `kubeadm-join.service` keeps retrying join; logs: `/var/log/kubeadm-join.log`.
- Terraform waits for control-plane SSH and for join artifacts before creating workers (`null_resource.wait_for_control_plane`). SSH host/user come from `control_plane_ssh_user`, known_hosts path from `ssh_known_hosts_dir`/`ssh_known_hosts_file`.

### Run (Ubuntu KVM host)
```bash
cd terraform/libvirt
terraform init
terraform apply -var-file=terraform.tfvars
```

Notes:
- Control-plane renders kubeadm-init.yaml, runs kubeadm init, and serves token/hash/join.sh over HTTP for workers.
- Workers render kubeadm-join.yaml and retry join until the API is ready; check `/var/log/kubeadm-join.log` on nodes if join fails.
- To re-seed after template changes, force rebuild: `terraform apply -var-file=terraform.tfvars --auto-approve -replace=libvirt_cloudinit_disk.control_plane_seed -replace=libvirt_domain.control_plane -replace=libvirt_cloudinit_disk.worker_seed -replace=libvirt_domain.worker`.
