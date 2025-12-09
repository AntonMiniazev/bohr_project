terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

resource "libvirt_volume" "ubuntu_base" {
  name   = "${var.project_name}-ubuntu-base"
  pool   = var.storage_pool
  source = var.base_image_path
}

locals {
  kubeadm_init = templatefile(
    "${path.module}/templates/kubeadm/kubeadm-init.yaml.tpl",
    {
      control_plane_ip  = var.control_plane.ip
      pod_network_cidr  = var.pod_network_cidr
      service_subnet    = var.service_subnet
      k8s_version       = var.k8s_version
    }
  )
}

locals {
  cloudinit_cp = templatefile(
    "${path.module}/templates/cloud-init/control-plane.tpl",
    {
      hostname         = var.control_plane.hostname
      ip               = var.control_plane.ip
      ssh_keys         = var.ssh_public_keys
      gateway          = var.network_gateway
      dns              = var.network_dns
      prefix           = var.network_prefix
      join_bind        = var.join_http_bind_address
      join_port        = var.join_http_port
      calico_interface = var.calico_interface
      kubeadm_init_yaml = indent(6, local.kubeadm_init)
    }
  )
}

locals {
  worker_user_data = {
    for name, cfg in var.worker_nodes :
    name => templatefile("${path.module}/templates/cloud-init/worker.tpl", {
      hostname          = name
      ip                = cfg.ip
      ssh_keys          = var.ssh_public_keys
      gateway           = var.network_gateway
      dns               = var.network_dns
      prefix            = var.network_prefix
      kubeadm_join_yaml = indent(6, templatefile("${path.module}/templates/kubeadm/kubeadm-join.yaml.tpl", {
        hostname         = name
        node_ip          = cfg.ip
        control_plane_ip = var.control_plane.ip
        bootstrap_token  = trimspace(data.http.join_token.response_body)
        ca_cert_hash     = trimspace(data.http.ca_hash.response_body)
      }))
    })
  }
}

resource "libvirt_volume" "control_plane_disk" {
  name           = "${var.control_plane.hostname}.qcow2"
  pool           = var.storage_pool
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = var.control_plane.disk_gb * 1024 * 1024 * 1024
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "control_plane_seed" {
  name      = "${var.control_plane.hostname}-seed.iso"
  user_data = local.cloudinit_cp
}

resource "libvirt_domain" "control_plane" {
  name   = var.control_plane.hostname
  memory = var.control_plane.memory
  vcpu   = var.control_plane.vcpu
  type   = "kvm"

  network_interface {
    network_name   = var.network_name
    wait_for_lease = false
  }

  disk {
    volume_id = libvirt_volume.control_plane_disk.id
  }

  cloudinit = libvirt_cloudinit_disk.control_plane_seed.id
}

resource "time_sleep" "wait_for_join" {
  depends_on = [libvirt_domain.control_plane]
  create_duration = "60s"
}

data "http" "join_token" {
  url = "http://${var.control_plane.ip}:${var.join_http_port}/join-token.txt"
  depends_on = [time_sleep.wait_for_join]
}

data "http" "ca_hash" {
  url = "http://${var.control_plane.ip}:${var.join_http_port}/ca-hash.txt"
  depends_on = [time_sleep.wait_for_join]
}

resource "libvirt_volume" "worker_disk" {
  for_each       = var.worker_nodes
  name           = "${each.key}.qcow2"
  pool           = var.storage_pool
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = each.value.disk_gb * 1024 * 1024 * 1024
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "worker_seed" {
  for_each = var.worker_nodes
  name     = "${each.key}-seed.iso"
  user_data = local.worker_user_data[each.key]
}

resource "libvirt_domain" "worker" {
  for_each = var.worker_nodes

  name   = each.key
  memory = each.value.memory
  vcpu   = each.value.vcpu
  type   = "kvm"

  network_interface {
    network_name   = var.network_name
    wait_for_lease = false
  }

  disk {
    volume_id = libvirt_volume.worker_disk[each.key].id
  }

  cloudinit = libvirt_cloudinit_disk.worker_seed[each.key].id
}
