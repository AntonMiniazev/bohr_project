project_name = "ampere"
libvirt_uri  = "qemu:///system"
network_name = "default"

# Base Ubuntu cloud image present on the KVM host
base_image_path         = "/var/lib/libvirt/images/jammy-server-cloudimg-amd64.img"
ssh_public_keys = [
  "AAAAC3NzaC1lZDI1NTE5AAAAIBCi9s1vZleOv8mgTpVbS+onvy06OIFazNVOy70XBn3c"
]

network_gateway = "192.168.11.1"
network_dns     = ["8.8.8.8", "8.8.4.4"]
network_prefix  = 24
storage_pool    = "default"
calico_interface = "ens3"

k8s_version      = "stable"
pod_network_cidr = "10.10.0.0/16"
service_subnet   = "10.96.0.0/12"
join_http_bind_address = "192.168.11.100"
join_http_port         = 8000

control_plane = {
  hostname = "ampere-k8s-master"
  memory   = 4096
  vcpu     = 2
  disk_gb  = 40
  ip       = "192.168.11.100"
}

# Workers: replicate the old fleet (node1..node3). IPs are rendered into the template.
worker_nodes = {
  "ampere-k8s-node1" = {
    memory  = 4096
    vcpu    = 2
    disk_gb = 40
    ip      = "192.168.11.101"
  }
  "ampere-k8s-node2" = {
    memory  = 4096
    vcpu    = 2
    disk_gb = 40
    ip      = "192.168.11.102"
  }
  "ampere-k8s-node3" = {
    memory  = 10240
    vcpu    = 4
    disk_gb = 40
    ip      = "192.168.11.103"
  }
}
