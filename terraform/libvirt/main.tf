terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "= 0.9.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }

  }
}

provider "libvirt" {
  uri = var.libvirt.libvirt_uri
}

resource "null_resource" "ampere_pool_path" {
  triggers = {
    pool_id = libvirt_pool.ampere_pool.id
  }

  provisioner "local-exec" {
    command = <<EOT
      sudo mkdir -p /var/lib/libvirt/images/ampere
      sudo chown -R libvirt-qemu:kvm /var/lib/libvirt/images/ampere
      sudo chmod -R 770 /var/lib/libvirt/images/ampere    
    EOT
  }
}

resource "libvirt_network" "ampere_net" {
  name      = "ampere-net"
  mode      = "nat"
  autostart = true
  bridge    = "virbr10"

  ips = [{
    address = "192.168.11.1"
    prefix  = 24

    dhcp = {
          ranges = [{
            start = var.network.dchp_addresses_range.dhcp_start
            end   = var.network.dchp_addresses_range.dhcp_end
          }]
          hosts = concat(
            [
              {
                mac  = var.fleet.control_plane.mac
                ip   = var.fleet.control_plane.ip
                name = var.fleet.control_plane.hostname
              }
            ],
            [
              for hostname, node in var.fleet.worker_nodes : {
                mac  = node.mac
                ip   = node.ip
                name = hostname
              }
            ]
          )
        }
  }]
}

resource "libvirt_pool" "ampere_pool" {
  name = "ampere-pool"
  type = "dir"
  target = {
    path = "/var/lib/libvirt/images/ampere"
  }
}

resource "libvirt_volume" "ubuntu_base" {
  name   = "${var.identity.project_name}-ubuntu-base.qcow2"
  pool   = libvirt_pool.ampere_pool.name
  format = "qcow2"

  create = {
    content = {
      # Prefer local path; fall back to URL if left blank
      url = var.image.base_image_path != "" ? var.image.base_image_path : var.image.base_image_url
    }
  }
}

locals {
  kubeadm_init_raw = templatefile(
    "${path.module}/templates/kubeadm/kubeadm-init.yaml.tpl",
    {
      control_plane = var.fleet.control_plane
      packages      = var.packages
    }
  )

  bootstrap_init_script = templatefile(
    "${path.module}/templates/bootstrap/bootstrap-init.sh.tpl",
    {
      identity               = var.identity
      network                = var.network
    }
  )  

  bootstrap_master_script = templatefile(
    "${path.module}/templates/bootstrap/bootstrap-k8s.sh.tpl",
    {
      identity               = var.identity
      control_plane          = var.fleet.control_plane
      packages               = var.packages
    }
  )

  bootstrap_addons_script = templatefile(
    "${path.module}/templates/bootstrap/bootstrap-addons.sh.tpl",
    {
      packages               = var.packages
      identity               = var.identity
      addons                 = var.addons
      control_plane          = var.fleet.control_plane
      network                = var.network
    }
  )  

  control_plane_network_config = templatefile(
    "${path.module}/templates/bootstrap/netplan.yaml.tpl",
    {
      network = var.network
      ip      = var.fleet.control_plane.ip
    }
  )  

  worker_network_config = {
    for name, cfg in var.fleet.worker_nodes :
    name => templatefile("${path.module}/templates/bootstrap/netplan.yaml.tpl", {
      network = var.network
      ip      = cfg.ip

    })
  }


  local_path_configmap_yaml = indent(6, file("${path.module}/templates/bootstrap/k8s/local-path-configmap.yaml.tpl"))
  kubeadm_init_indented = indent(6, local.kubeadm_init_raw)
  bootstrap_init_script_indented = indent(6, local.bootstrap_init_script)
  bootstrap_master_script_indented = indent(6, local.bootstrap_master_script)
  bootstrap_addons_script_indented = indent(6, local.bootstrap_addons_script)
  worker_user_data = {
    for name, cfg in var.fleet.worker_nodes :
    name => templatefile("${path.module}/templates/cloud-init/worker.tpl", {
      hostname                = name
      ssh                     = var.ssh
      network                 = var.network
      control_plane           = var.fleet.control_plane
      join                    = var.join
      registry                = var.registry
      identity                = var.identity
      packages                = var.packages
    })
  }  

}

locals {
  cloudinit_cp = templatefile(
    "${path.module}/templates/cloud-init/control-plane.tpl",
    {
      control_plane                          = var.fleet.control_plane
      ssh                                    = var.ssh
      join                                   = var.join
      registry                               = var.registry
      identity                               = var.identity
      kubeadm_init_indented                   = local.kubeadm_init_indented
      bootstrap_init_script_indented          = local.bootstrap_init_script_indented
      bootstrap_master_script_indented        = local.bootstrap_master_script_indented
      bootstrap_addons_script_indented        = local.bootstrap_addons_script_indented
      local_path_configmap_indented           = local.local_path_configmap_yaml
    }
  )
}

locals {

}

resource "libvirt_volume" "control_plane_disk" {
  depends_on = [null_resource.ampere_pool_path]
  name           = "${var.fleet.control_plane.hostname}.qcow2"
  pool           = libvirt_pool.ampere_pool.name
  format         = "qcow2"
  capacity       = var.fleet.control_plane.disk_gb * 1024 * 1024 * 1024

  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = "qcow2"
  }
}

resource "libvirt_cloudinit_disk" "control_plane_seed" {
  name           = "${var.fleet.control_plane.hostname}-seed.iso"
  pool           = libvirt_pool.ampere_pool.name
  user_data      = local.cloudinit_cp
  network_config = local.control_plane_network_config

  meta_data      = yamlencode({
    "instance-id"    = var.fleet.control_plane.hostname
    "local-hostname" = var.fleet.control_plane.hostname
  })
}

resource "libvirt_domain" "control_plane" {
  name   = var.fleet.control_plane.hostname
  memory = var.fleet.control_plane.memory
  unit   = "MiB"
  vcpu   = var.fleet.control_plane.vcpu
  type   = "kvm"
  running   = true
  autostart = true  

  os = {
    type         = "hvm"
    arch         = "x86_64"
    boot_devices = ["hd"]
  }

  devices = {
    disks = [
      {
        device = "disk"
        target = { dev = "vda", bus = "virtio" }
        source = {
          pool   = libvirt_pool.ampere_pool.name
          volume = libvirt_volume.control_plane_disk.name
        }
      },
      {
        device = "cdrom"
        target = { dev = "sda", bus = "sata" }
        source = {
          file = libvirt_cloudinit_disk.control_plane_seed.path
        }
      }
    ]
    interfaces = [
      {
        type   = "network"
        model  = "virtio"
        source = { network = libvirt_network.ampere_net.name }
      }
    ]
  }
}

resource "null_resource" "wait_for_control_plane" {
  depends_on = [libvirt_domain.control_plane]

  provisioner "local-exec" {
    command = <<EOT
      set -eu

      CONTROL_PLANE_HOSTNAME="${var.fleet.control_plane.hostname}" \
      CONTROL_PLANE_USER="${var.ssh.control_plane_ssh_user}" \
      KNOWN_HOSTS_PATH="${var.ssh.ssh_known_hosts_path}" \
      PROJECT_NAME="${var.identity.project_name}" \
      bash "${path.module}/scripts/wait_for_control_plane.sh"
    EOT
  }
}

resource "libvirt_volume" "worker_disk" {
  for_each = var.fleet.worker_nodes
  depends_on = [null_resource.ampere_pool_path]
  name           = "${each.key}.qcow2"
  pool           = libvirt_pool.ampere_pool.name
  format         = "qcow2"
  capacity       = each.value.disk_gb * 1024 * 1024 * 1024

  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = "qcow2"
  }
}

resource "libvirt_cloudinit_disk" "worker_seed" {
  for_each = var.fleet.worker_nodes

  name           = "${each.key}-seed.iso"
  pool           = libvirt_pool.ampere_pool.name
  user_data      = local.worker_user_data[each.key]
  network_config = local.worker_network_config[each.key]

  meta_data      = yamlencode({
    "instance-id"    = each.key
    "local-hostname" = each.key
  })
}

resource "libvirt_domain" "worker" {
  for_each = var.fleet.worker_nodes

  name      = each.key
  memory    = each.value.memory
  unit      = "MiB"
  vcpu      = each.value.vcpu
  type      = "kvm"
  running   = true
  autostart = true

  os = {
    type         = "hvm"
    arch         = "x86_64"
    boot_devices = ["hd"]
  }

  devices = {
    disks = [
      {
        device = "disk"
        target = { dev = "vda", bus = "virtio" }
        source = {
          pool   = libvirt_pool.ampere_pool.name
          volume = libvirt_volume.worker_disk[each.key].name
        }
      },
      {
        device = "cdrom"
        target = { dev = "sda", bus = "sata" }
        source = {
          file = libvirt_cloudinit_disk.worker_seed[each.key].path
        }
      }
    ]
    interfaces = [
      {
        type   = "network"
        model  = "virtio"
        source = { network = libvirt_network.ampere_net.name }
        mac    = lower(each.value.mac)
      }
    ]
  }
  depends_on = [null_resource.wait_for_control_plane]
}

resource "null_resource" "wait_for_workers" {
  depends_on = [libvirt_domain.worker]

  provisioner "local-exec" {
    command = <<EOT
      set -eu

      CONTROL_PLANE_HOSTNAME="${var.fleet.control_plane.hostname}" \
      CONTROL_PLANE_USER="${var.ssh.control_plane_ssh_user}" \
      KNOWN_HOSTS_PATH="${var.ssh.ssh_known_hosts_path}" \
      WORKER_NODES="${join(" ", keys(var.fleet.worker_nodes))}" \
      bash "${path.module}/scripts/wait_for_workers.sh"
    EOT
  }
}
