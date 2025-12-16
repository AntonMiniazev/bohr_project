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

  - path: /etc/kubernetes/kubeadm-init.yaml
    permissions: '0644'
    content: |
${kubeadm_init_yaml}

  - path: /usr/local/bin/write-join.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      mkdir -p /var/lib/kubeadm
      token=$(kubeadm token create --ttl 24h0m0s)
      hash=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \
        | openssl rsa -pubin -outform der 2>/dev/null \
        | openssl dgst -sha256 -hex \
        | sed 's/^.* //')
      echo "$token" > /var/lib/kubeadm/join-token.txt
      echo "$hash" > /var/lib/kubeadm/ca-hash.txt
      echo "kubeadm join ${ip}:6443 --token $token --discovery-token-ca-cert-hash sha256:$hash" > /var/lib/kubeadm/join.sh
      chmod +x /var/lib/kubeadm/join.sh

  - path: /etc/systemd/system/kubeadm-write-join.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Generate kubeadm join materials after init
      After=kubeadm-init.service
      Wants=kubeadm-init.service

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/write-join.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target

  - path: /etc/systemd/system/kubeadm-join-http.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Serve kubeadm join artifacts over HTTP
      After=kubeadm-write-join.service
      Wants=kubeadm-write-join.service

      [Service]
      WorkingDirectory=/var/lib/kubeadm
      ExecStart=/usr/bin/python3 -m http.server ${join_port} --bind ${join_bind}
      Restart=on-failure

      [Install]
      WantedBy=multi-user.target

  - path: /opt/bootstrap/local-path-configmap.yaml
    permissions: '0644'
    content: |
${local_path_configmap_yaml}

  - path: /usr/local/bin/bootstrap-master.sh
    permissions: '0755'
    content: |
${bootstrap_master_script_indented}

  - path: /etc/systemd/system/bootstrap-master.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Bootstrap Kubernetes control plane
      Wants=network-online.target systemd-networkd-wait-online.service containerd.service
      After=network-online.target systemd-networkd-wait-online.service containerd.service
      ConditionPathExists=!/etc/kubernetes/admin.conf

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/bootstrap-master.sh
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target

runcmd:
  - netplan apply
  - systemctl enable systemd-networkd-wait-online.service
  - rm -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg  
  - bash -c 'for i in {1..20}; do ip route | grep -q "^default" && exit 0; echo "[INFO] Waiting for default route..."; sleep 3; done; echo "[WARN] Default route not found, continuing"; exit 0'
  - bash -c 'for i in {1..5}; do apt-get update && exit 0; echo "[WARN] apt-get update failed, retry $i/5..."; sleep 10; done; echo "[ERROR] apt-get update failed after retries, continuing anyway"; exit 0'  
  - bash -c 'DEBIAN_FRONTEND=noninteractive apt-get -y upgrade || echo "[WARN] apt upgrade failed (non-fatal)"'
  - apt-get install -y ca-certificates curl gnupg software-properties-common  
  - sed -i '/ swap / s/^/#/' /etc/fstab
  - swapoff -a
  - modprobe br_netfilter
  - echo 'net.bridge.bridge-nf-call-iptables=1' | tee /etc/sysctl.d/k8s.conf
  - sysctl --system    
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - sh -c 'echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" > /etc/apt/sources.list.d/kubernetes.list'
  - apt-get update
  - apt-get install -y conntrack containerd kubelet kubeadm kubectl gnupg
  - curl -LO https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
  - install -m 0755 sops-v3.11.0.linux.amd64 /usr/local/bin/sops
  - curl -L https://github.com/roboll/helmfile/releases/download/v1.2.2/helmfile_linux_amd64 -o helmfile  
  - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  - helm plugin install https://github.com/jkroepke/helm-secrets --version v4.7.4 --verify=false
  - helm plugin install https://github.com/databus23/helm-diff  
  - echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/99-kubernetes-ipforward.conf
  - sysctl --system
  - systemctl daemon-reexec
  - systemctl enable containerd
  - systemctl restart containerd
  - systemctl enable kubelet
  - systemctl start kubelet
  - until systemctl is-active --quiet systemd-networkd containerd; do sleep 2; done
  - until ping -c1 8.8.8.8 >/dev/null 2>&1; do sleep 2; done
  - kubeadm config images pull --config /etc/kubernetes/kubeadm-init.yaml || true
  - systemctl daemon-reload
  - systemctl enable kubeadm-write-join.service
  - systemctl enable kubeadm-join-http.service
  - systemctl enable bootstrap-master.service
  - systemctl start bootstrap-master.service --no-block
