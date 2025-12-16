variable "project_name" {
  description = "Prefix for libvirt resources and VM hostnames"
  type        = string
  default     = "ampere"
}

variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "network_name" {
  description = "Libvirt network to attach (e.g., default or a bridged network)"
  type        = string
  default     = "default"
}

variable "base_image_path" {
  description = "Path to the Ubuntu cloud image (e.g., jammy-server-cloudimg-amd64.img)"
  type        = string
}

variable "ssh_public_keys" {
  description = "SSH public keys to inject into VMs"
  type        = list(string)
}

variable "network_gateway" {
  description = "Gateway for static IPs"
  type        = string
  default     = "192.168.11.1"
}

variable "network_interface" {
  description = "Guest interface name used in netplan (e.g., enp1s0)"
  type        = string
  default     = "enp0s2"
}

variable "network_dns" {
  description = "DNS servers list"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "network_prefix" {
  description = "CIDR prefix length for static IPs"
  type        = number
  default     = 24
}

variable "storage_pool" {
  description = "Libvirt storage pool name"
  type        = string
  default     = "default"
}

variable "base_image_url" {
  description = "HTTP(S) URL to the Ubuntu cloud image (used for upload)"
  type        = string
}

variable "local_path_url" {
  description = "URL to the Local Path Provisioner YAML file"
  type        = string
}

variable "control_plane" {
  description = "Control-plane definition"
  type = object({
    hostname = string
    memory   = number
    vcpu     = number
    disk_gb  = number
    ip       = string
    mac      = string
  })
}

variable "worker_nodes" {
  description = "Map of worker node definitions; key is VM name"
  type = map(object({
    memory  = number
    vcpu    = number
    disk_gb = number
    ip      = string
    mac      = string
  }))
  default = {}
}

variable "service_subnet" {
  description = "Service subnet used by kubeadm"
  type        = string
  default     = "10.96.0.0/12"
}

variable "k8s_version" {
  description = "Kubernetes version string for kubeadm (e.g., stable or v1.31.0)"
  type        = string
  default     = "stable"
}

variable "join_http_bind_address" {
  description = "Bind address for serving join token/hash"
  type        = string
  default     = "0.0.0.0"
}

variable "join_http_port" {
  description = "Port for join token/hash HTTP server"
  type        = number
  default     = 8000
}

variable "control_plane_ssh_user" {
  description = "SSH user to wait on the control-plane node"
  type        = string
  default     = "ampere"
}

variable "ssh_known_hosts_dir" {
  description = "Directory for cluster-specific known_hosts file"
  type        = string
  default     = "~/.ssh"
}

variable "ssh_known_hosts_file" {
  description = "Filename for cluster-specific known_hosts"
  type        = string
  default     = "ampere_known_hosts"
}

variable "dchp_addresses_range" {
  description = "Start and end of DHCP range"
  type = object({
    dhcp_start = string
    dhcp_end   = string
  })
}

variable "dockerhub_username" {
  type      = string
  sensitive = true
}

variable "dockerhub_token" {
  type      = string
  sensitive = true
}

variable "cilium" {
  description = "Cilium variables"
  type = object({
    version            = string
    operator_replicas  = number
    pod_network_cidr   = string
  })
}