      #!/bin/bash
      set -euo pipefail
  
      mkdir -p /var/lib/${identity.project_name}
  
      echo "[DIAG] bootstrap-init started at $(date)"
  
      # --- Network ---
      echo "[DIAG] Applying netplan"
      netplan apply
  
      systemctl enable systemd-networkd-wait-online.service
      rm -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
      systemctl start systemd-networkd-wait-online.service
    
      echo "[DIAG] Waiting for default route"
      for i in {1..20}; do
      if ip route | grep -q "^default"; then
          echo "[DIAG] Default route detected"
          break
      fi
      sleep 3
      done
  
      if ! ip route | grep -q "^default"; then
      echo "[FATAL] Default route not found"
      exit 1
      fi
  
      # --- Package system sanity ---
      echo "[DIAG] Updating package index (best-effort)"
      for i in {1..5}; do
      if apt-get update; then
          break
      fi
      sleep 10
      done
  
      echo "[DIAG] Upgrading packages (non-fatal)"
      DEBIAN_FRONTEND=noninteractive apt-get -y upgrade || true
  
      apt-get install -y ca-certificates curl gnupg software-properties-common
  
      # --- Kernel / sysctl ---
      echo "[DIAG] Configuring kernel parameters"
  
      printf "%s\n" \
      "overlay" \
      "br_netfilter" \
      | tee /etc/modules-load.d/99-kubernetes.conf >/dev/null
  
      modprobe overlay
      modprobe br_netfilter
  
      printf "%s\n" \
        "net.ipv4.ip_forward = 1" \
        "net.ipv6.conf.all.forwarding = 1" \
        "net.bridge.bridge-nf-call-ip6tables = 1" \
        "net.bridge.bridge-nf-call-iptables = 1" \
      | tee /etc/sysctl.d/99-kubernetes.conf >/dev/null

      # Cilium-required sysctl (must be applied before kubelet)
      printf "%s\n" \
        "net.ipv4.conf.all.rp_filter=0" \
        "net.ipv4.conf.default.rp_filter=0" \
        "net.ipv4.conf.all.forwarding=1" \
        "net.ipv4.conf.${network.network_interface}.rp_filter=0" \
        "kernel.unprivileged_bpf_disabled = 0" \
      | tee /etc/sysctl.d/99-cilium.conf >/dev/null       

      sysctl --system

      # --- OS READY MARKER ---
      echo "[DIAG] Writing OS_READY marker"
      echo "$(date -Iseconds)" > /var/lib/${identity.project_name}/OS_READY
 
      sync
      echo "[DIAG] OS_READY emitted"
  
      exit 0
