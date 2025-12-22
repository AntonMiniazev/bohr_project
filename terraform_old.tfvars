project_name = "ampere"
libvirt_uri  = "qemu:///system"
network_name = "default"

# Base Ubuntu cloud image present on the KVM host
base_image_path         = ""
base_image_url          = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
ssh_public_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBCi9s1vZleOv8mgTpVbS+onvy06OIFazNVOy70XBn3c oppie@client"
]
local_path_url = "https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml"

network_gateway = "192.168.11.1"
network_dns     = ["8.8.8.8", "8.8.4.4"]
network_prefix  = 24
storage_pool    = "default"
#calico_interface = "enp0s2"

k8s_version      = "stable"
service_subnet   = "10.96.0.0/12"
join_http_bind_address = "192.168.11.100"
join_http_port         = 8000

control_plane = {
  hostname = "ampere-k8s-master"
  memory   = 4096
  vcpu     = 2
  disk_gb  = 40
  ip       = "192.168.11.100"
  mac      = "02:16:3A:9B:01:10"
}

cilium = {
  version            = "1.18.4"
  operator_replicas  = 1
  pod_network_cidr 	 = "10.10.0.0/16"
}

# Workers: replicate the old fleet (node1..node3). IPs are rendered into the template.
worker_nodes = {
  "ampere-k8s-node1" = {
    memory  = 4096
    vcpu    = 2
    disk_gb = 40
    ip      = "192.168.11.101"
    mac     = "02:1C:55:F3:22:47"
  }
  "ampere-k8s-node2" = {
    memory  = 4096
    vcpu    = 2
    disk_gb = 40
    ip      = "192.168.11.102"
    mac     = "02:28:A7:6C:33:8D"
  }
  "ampere-k8s-node3" = {
    memory  = 10240
    vcpu    = 4
    disk_gb = 40
    ip      = "192.168.11.103"
    mac     = "02:34:F9:DA:44:E2"
  }
}

# Start and end of DHCP range
dchp_addresses_range = { 
  dhcp_start = "192.168.11.100" 
  dhcp_end = "192.168.11.200" 
}

dockerhub_username = "an7on"
dockerhub_token    = "dckr_pat_cPL6Km5nCGro9QYphyjVYfUzEFc"