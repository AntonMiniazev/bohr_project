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

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }    

  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.project_name
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = var.project_name
  load_config_file = true
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
            start = var.dchp_addresses_range.dhcp_start
            end   = var.dchp_addresses_range.dhcp_end
          }]
          hosts = concat(
            [
              {
                mac  = var.control_plane.mac
                ip   = var.control_plane.ip
                name = var.control_plane.hostname
              }
            ],
            [
              for hostname, node in var.worker_nodes : {
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
  name   = "${var.project_name}-ubuntu-base.qcow2"
  pool   = libvirt_pool.ampere_pool.name
  format = "qcow2"

  create = {
    content = {
      # Prefer local path; fall back to URL if left blank
      url = var.base_image_path != "" ? var.base_image_path : var.base_image_url
    }
  }
}

locals {
  kubeadm_init_raw = templatefile(
    "${path.module}/templates/kubeadm/kubeadm-init.yaml.tpl",
    {
      control_plane_ip  = var.control_plane.ip
      pod_network_cidr  = var.cilium.pod_network_cidr
      service_subnet    = var.service_subnet
      k8s_version       = var.k8s_version
    }
  )

  bootstrap_master_script = templatefile(
    "${path.module}/templates/bootstrap/bootstrap.sh.tpl",
    {
      local_path_url    = var.local_path_url
      project_name      = var.project_name
      pod_network_cidr  = var.cilium.pod_network_cidr
      cilium_version    = var.cilium.version
      cilium_replicas   = var.cilium.operator_replicas      
    }
  )

  local_path_configmap_yaml = indent(6, file("${path.module}/templates/bootstrap/k8s/local-path-configmap.yaml.tpl"))

  kubeadm_init_indented = indent(6, local.kubeadm_init_raw)
  bootstrap_master_script_indented = indent(6, local.bootstrap_master_script)
  dockerhub_basic_auth = base64encode("${var.dockerhub_username}:${var.dockerhub_token}")

}

locals {
  cloudinit_cp = templatefile(
    "${path.module}/templates/cloud-init/control-plane.tpl",
    {
      hostname                          = var.control_plane.hostname
      ip                                = var.control_plane.ip
      interface                         = var.network_interface
      ssh_keys                          = var.ssh_public_keys
      gateway                           = var.network_gateway
      dns                               = var.network_dns
      prefix                            = var.network_prefix
      join_bind                         = var.join_http_bind_address
      join_port                         = var.join_http_port
      kubeadm_init_yaml                 = local.kubeadm_init_indented
      bootstrap_master_script_indented  = local.bootstrap_master_script_indented
      local_path_configmap_yaml         = local.local_path_configmap_yaml
      dockerhub_username                = var.dockerhub_username
      dockerhub_password                = var.dockerhub_token
    }
  )
}

locals {
  worker_user_data = {
    for name, cfg in var.worker_nodes :
    name => templatefile("${path.module}/templates/cloud-init/worker.tpl", {
      hostname                = name
      ip                      = cfg.ip
      ssh_keys                = var.ssh_public_keys
      gateway                 = var.network_gateway
      dns                     = var.network_dns
      prefix                  = var.network_prefix
      interface               = var.network_interface
      control_plane_ip        = var.control_plane.ip
      join_port               = var.join_http_port
      dockerhub_username      = var.dockerhub_username
      dockerhub_password      = var.dockerhub_token
    })
  }
}

resource "libvirt_volume" "control_plane_disk" {
  depends_on = [null_resource.ampere_pool_path]
  name           = "${var.control_plane.hostname}.qcow2"
  pool           = libvirt_pool.ampere_pool.name
  format         = "qcow2"
  capacity       = var.control_plane.disk_gb * 1024 * 1024 * 1024

  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = "qcow2"
  }
}

resource "libvirt_cloudinit_disk" "control_plane_seed" {
  name           = "${var.control_plane.hostname}-seed.iso"
  user_data      = local.cloudinit_cp
  meta_data      = yamlencode({
    "instance-id"    = var.control_plane.hostname
    "local-hostname" = var.control_plane.hostname
  })
}

resource "libvirt_domain" "control_plane" {
  name   = var.control_plane.hostname
  memory = var.control_plane.memory
  unit   = "MiB"
  vcpu   = var.control_plane.vcpu
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

      hostname=${var.control_plane.hostname}
      user=${var.control_plane_ssh_user}
      kh_dir=${var.ssh_known_hosts_dir}
      kh_file=${var.ssh_known_hosts_file}
      kh_path="$${kh_dir%/}/$${kh_file}"

      mkdir -p "$${kh_dir}"
      echo "[DEBUG] kh_path is $${kh_path} and hostname is $${hostname}"
      ssh-keygen -f "$${kh_path}" -R "$${hostname}" >/dev/null 2>&1 || true

      echo "[INFO] Waiting for SSH on $${user}@$${hostname} ..."
      for i in $(seq 1 20); do
        if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile="$${kh_path}" -o LogLevel=ERROR "$${user}@$${hostname}" "echo ok" >/dev/null 2>&1; then

          echo "[INFO] SSH is ready"
          break
        fi
        echo "[INFO] SSH not ready yet"
        sleep 30
      done

      if ! ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile="$${kh_path}" -o LogLevel=ERROR "$${user}@$${hostname}" "echo ok" >/dev/null 2>&1; then
        echo "[ERROR] SSH did not become ready" >&2
        exit 1
      fi

      echo "[INFO] Waiting for bootstrap-master.service to complete..."
      for i in $(seq 1 30); do
        status=$(ssh -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile="$${kh_path}" \
                    "$${user}@$${hostname}" "systemctl is-active bootstrap-master.service || true")

        if [ "$${status}" = "active" ]; then
          echo "[INFO] bootstrap-master.service still running..."
        elif [ "$${status}" = "inactive" ]; then
          echo "[INFO] bootstrap-master.service finished successfully"
          break
        else
          echo "[ERROR] bootstrap-master.service failed with status=$${status}"
          exit 1
        fi
        sleep 20
      done

      echo "[INFO] Waiting for cloud-init to reach a final state..."
      ci_status=""
      for i in $(seq 1 15); do
        ci_line=$(ssh -o StrictHostKeyChecking=no \
                       -o UserKnownHostsFile="$${kh_path}" \
                       "$${user}@$${hostname}" "sudo cloud-init status 2>/dev/null" || true)
        ci_status=$(printf '%s\n' "$ci_line" | cut -d' ' -f2 || true)

        if [ "$ci_status" = "running" ]; then
          echo "[INFO] cloud-init status is running, waiting..."
        elif [ "$ci_status" = "done" ]; then
          echo "[INFO] cloud-init finished successfully"
          break
        elif [ "$ci_status" = "error" ]; then
          echo "[ERROR] cloud-init finished with error:"
          ssh -o StrictHostKeyChecking=no \
              -o UserKnownHostsFile="$${kh_path}" \
              "$${user}@$${hostname}" "sudo cloud-init status --long || true"
          exit 1
        else
          echo "[WARN] cloud-init status is '$ci_status', waiting..."
        fi
        sleep 20
      done

      if [ "$ci_status" != "done" ] && [ "$ci_status" != "error" ]; then
        echo "[ERROR] Timeout waiting for cloud-init to finish (last status: $ci_status)" >&2
        ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile="$${kh_path}" \
            "$${user}@$${hostname}" "sudo cloud-init status --long || true"
        exit 1
      fi

      echo "[INFO] Final cloud-init status:"
      ssh -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile="$${kh_path}" \
          "$${user}@$${hostname}" "sudo cloud-init status --long || true"

      echo "[INFO] Validating cloud-init schema..."
      if ssh -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile="$${kh_path}" \
             "$${user}@$${hostname}" "sudo cloud-init schema --system >/dev/null 2>&1"; then
        echo "[INFO] cloud-init schema: OK"
      else
        echo "[ERROR] cloud-init schema: FAILED" >&2
        exit 1
      fi      

      echo "[INFO] Waiting for Kubernetes node $${hostname} to be Ready..."

      for i in $(seq 1 20); do
        node_status=$(ssh -o StrictHostKeyChecking=no \
                           -o UserKnownHostsFile="$${kh_path}" \
                           "$${user}@$${hostname}" \
                           "KUBECONFIG=/home/$${user}/.kube/config kubectl get nodes --no-headers 2>/dev/null | grep '^$${hostname} ' | awk '{print \$2}'" \
                           || true)

        printable_status="$node_status"
        if [ -z "$printable_status" ]; then
          printable_status="unknown"
        fi

        if [ "$node_status" = "Ready" ]; then
          echo "[INFO] Node $${hostname} is Ready"
          exit 0
        fi

        echo "[INFO] Node $${hostname} not Ready yet (status: $printable_status), waiting..."
        sleep 30
      done

      printable_status="$node_status"
      if [ -z "$printable_status" ]; then
        printable_status="unknown"
      fi

      echo "[ERROR] Node $${hostname} did not reach Ready state in time (last status: $printable_status)" >&2
      exit 1

    EOT
  }
}

resource "libvirt_volume" "worker_disk" {
  for_each = var.worker_nodes
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
  for_each = var.worker_nodes

  name           = "${each.key}-seed.iso"
  user_data      = local.worker_user_data[each.key]
  meta_data      = yamlencode({
    "instance-id"    = each.key
    "local-hostname" = each.key
  })
}

resource "libvirt_domain" "worker" {
  for_each = var.worker_nodes

  name   = each.key
  memory = each.value.memory
  unit   = "MiB"
  vcpu   = each.value.vcpu
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
      }
    ]
  }
  depends_on = [null_resource.wait_for_control_plane]
}
