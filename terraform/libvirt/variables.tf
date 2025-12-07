variable "identity" {
  description = "Project-level naming"
  type = object({
    project_name = string
  })
}

variable "libvirt" {
  description = "Libvirt connection and storage"
  type = object({
    libvirt_uri  = string
  })
}

variable "image" {
  description = "Ubuntu cloud image settings"
  type = object({
    base_image_path = string
    base_image_url  = string
  })
}

variable "network" {
  description = "Network and DHCP settings"
  type = object({
    network_gateway    = string
    network_interface  = string
    network_dns        = list(string)
    network_prefix     = number
    dchp_addresses_range = object({
      dhcp_start = string
      dhcp_end   = string
    })
  })
}

variable "ssh" {
  description = "SSH access configuration"
  type = object({
    ssh_public_keys      = list(string)
    control_plane_ssh_user = string
    ssh_known_hosts_path = string
  })
}

variable "join" {
  description = "Join server settings"
  type = object({
    join_http_bind_address = string
    join_http_port         = number
  })
}

variable "addons" {
  description = "Addons and manifests"
  type = object({
    local_path_url = string
  })
}

variable "registry" {
  description = "Registry credentials"
  type = object({
    dockerhub_username = string
    dockerhub_token    = string
  })
  sensitive = true
}

variable "fleet" {
  description = "VM fleet definition"
  type = object({
    control_plane = object({
      hostname = string
      memory   = number
      vcpu     = number
      disk_gb  = number
      ip       = string
      mac      = string
    })
    worker_nodes = map(object({
      memory  = number
      vcpu    = number
      disk_gb = number
      ip      = string
      mac     = string
    }))
  })
}

variable "packages" {
  description = "Package versions and related configuration"
  type = object({
    kubernetes = object({
      k8s_version  = string
      repo_version = string
      cluster_name   = string
      service_subnet = string
    })
    cilium = object({
      version_cli       = string
      version_operator  = string
      operator_replicas = number
      pod_network_cidr  = string
    })
    helm = object({
      version = string
    })
    helmfile = object({
      version = string
    })
    sops = object({
      version = string
    })
    helm_plugins = object({
      helm_secrets_version = string
    })
  })
}
