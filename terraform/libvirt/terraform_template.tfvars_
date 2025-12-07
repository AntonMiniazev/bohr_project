identity = {
  project_name = "PROJECT_NAME"
}

libvirt = {
  libvirt_uri  = "qemu:///system"
  storage_pool = "default"
}

image = {
  base_image_path = ""
  base_image_url  = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
}

ssh = {
  ssh_public_keys = [
    "SSH_PUBLIC_KEY"
  ]
  control_plane_ssh_user = "USERNAME"
  ssh_known_hosts_path   = "SSH_KNOWN_HOSTS_PATH"
}

network = {
  network_name       = "default"
  network_gateway    = "192.168.11.1"
  network_interface  = "enp0s2"
  network_dns        = ["8.8.8.8", "8.8.4.4"]
  network_prefix     = 24
  dchp_addresses_range = {
    dhcp_start = "192.168.11.100"
    dhcp_end   = "192.168.11.200"
  }
}

packages = {
  kubernetes = {
    k8s_version   = "stable"
    repo_version  = "v1.31"
    cluster_name  = "CLUSTER_NAME"
    service_subnet = "10.96.0.0/12"
  }
  cilium = {
    version_cli       = "v0.18.9"
    version_operator  = "1.18.4"
    operator_replicas = 1
    pod_network_cidr  = "10.10.0.0/16"
  }
  helm = {
    version = "v3.19.4"
  }
  helmfile = {
    version = "v1.2.2"
  }
  sops = {
    version = "v3.11.0"
  }
  helm_plugins = {
    helm_secrets_version = "v4.7.4"
  }
}

join = {
  join_http_bind_address = "192.168.11.100"
  join_http_port         = 8000
}

addons = {
  local_path_url = "https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml"
}

registry = {
  dockerhub_username = "DOCKER"
  dockerhub_token    = "DOCKER_TOKEN"
}

fleet = {
  control_plane = {
    hostname = "CONTROL_PLANE_HOSTNAME"
    memory   = 4096
    vcpu     = 2
    disk_gb  = 40
    ip       = "192.168.11.100"
    mac      = "02:16:3A:9B:01:10"
  }
  worker_nodes = {
    "WORKER_NODE_1" = {
      memory  = 4096
      vcpu    = 2
      disk_gb = 40
      ip      = "192.168.11.101"
      mac     = "02:1C:55:F3:22:47"
    }
    "WORKER_NODE_2" = {
      memory  = 4096
      vcpu    = 2
      disk_gb = 40
      ip      = "192.168.11.102"
      mac     = "02:28:A7:6C:33:8D"
    }
    "WORKER_NODE_3" = {
      memory  = 10240
      vcpu    = 4
      disk_gb = 40
      ip      = "192.168.11.103"
      mac     = "02:34:F9:DA:44:E2"
    }
  }
}
