#cloud-config
hostname: ${hostname}
timezone: Europe/Belgrade
ssh_pwauth: false
users:
  - name: ampere
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - "${key}"
%{ endfor ~}

package_update: false
package_upgrade: false

write_files:
  - path: /etc/netplan/99-netcfg.yaml
    permissions: '0600'
    content: |
      network:
        version: 2
        ethernets:
          ${interface}:
            dhcp4: no
            addresses:
              - ${ip}/${prefix}
            routes:
              - to: default
                via: ${gateway}
            nameservers:
              addresses:
%{ for addr in dns ~}
                - ${addr}
%{ endfor ~}

  - path: /etc/containerd/certs.d/docker.io/hosts.toml
    permissions: '0644'
    content: |
      server = "https://docker.io"

      [host."https://registry-1.docker.io"]
        capabilities = ["pull", "resolve"]

        [host."https://registry-1.docker.io".auth]
          username = ${dockerhub_username}
          password = ${dockerhub_password}


  - path: /usr/local/bin/wait-for-join.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      LOG_FILE="/var/log/kubeadm-join.log"
      exec >>"$LOG_FILE" 2>&1
      echo "[INFO] $(date -Iseconds) starting kubeadm join attempts"
      for i in {1..180}; do
        if curl -fs http://${control_plane_ip}:${join_port}/join.sh -o /tmp/join.sh; then
          chmod +x /tmp/join.sh
          if bash /tmp/join.sh; then
            echo "[INFO] $(date -Iseconds) join succeeded on attempt $i"
            exit 0
          else
            echo "[WARN] $(date -Iseconds) join.sh failed on attempt $i"
          fi
        else
          echo "[WARN] $(date -Iseconds) join.sh not yet available (attempt $i)"
        fi
        sleep 5
      done
      echo "[ERROR] $(date -Iseconds) join timed out after 180 attempts"
      exit 1

  - path: /etc/systemd/system/kubeadm-join.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Join node to Kubernetes cluster
      Wants=network-online.target systemd-networkd-wait-online.service containerd.service
      After=network-online.target systemd-networkd-wait-online.service containerd.service

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/wait-for-join.sh
      Restart=on-failure
      RestartSec=10
      StartLimitIntervalSec=0

      [Install]
      WantedBy=multi-user.target
runcmd:
  - netplan apply
  - systemctl enable systemd-networkd-wait-online.service
  - rm -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
  - bash -c 'for i in {1..20}; do ip route | grep -q "^default" && exit 0; echo "[INFO] Waiting for default route..."; sleep 3; done; echo "[WARN] Default route not found, continuing"; exit 0'
  - bash -c 'for i in {1..5}; do apt-get update && exit 0; echo "[WARN] apt-get update failed, retry $i/5..."; sleep 10; done; echo "[ERROR] apt-get update failed after retries, continuing anyway"; exit 0'  
  - bash -c 'DEBIAN_FRONTEND=noninteractive apt-get -y upgrade || echo "[WARN] apt upgrade failed (non-fatal)"'
  - apt-get install -y ca-certificates curl gnupg software-properties-common conntrack
  - sed -i '/ swap / s/^/#/' /etc/fstab
  - swapoff -a
  - modprobe br_netfilter
  - echo 'net.bridge.bridge-nf-call-iptables=1' | tee /etc/sysctl.d/k8s.conf
  - echo 'net.ipv4.ip_forward=1' | tee /etc/sysctl.d/99-kubernetes-ipforward.conf
  - sysctl --system
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - apt-get install -y kubelet kubeadm kubectl containerd conntrack
  - systemctl daemon-reexec
  - systemctl enable kubelet
  - systemctl start kubelet  
  - systemctl enable containerd
  - mkdir -p /etc/containerd
  - systemctl restart containerd
  - systemctl daemon-reload  
  - systemctl enable kubeadm-join.service
  - systemctl start kubeadm-join.service --no-block
