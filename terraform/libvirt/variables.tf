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

variable "control_plane" {
  description = "Control-plane definition"
  type = object({
    hostname = string
    memory   = number
    vcpu     = number
    disk_gb  = number
    ip       = string
  })
}

variable "worker_nodes" {
  description = "Map of worker node definitions; key is VM name"
  type = map(object({
    memory  = number
    vcpu    = number
    disk_gb = number
    ip      = string
  }))
  default = {}
}

variable "pod_network_cidr" {
  description = "Pod network CIDR used by kubeadm/Calico"
  type        = string
  default     = "10.10.0.0/16"
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
