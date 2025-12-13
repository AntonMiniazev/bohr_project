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

  - path: /usr/local/bin/bootstrap-master.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e

      # Wait for runtime and network
      until systemctl is-active --quiet containerd; do sleep 2; done
      until ping -c1 8.8.8.8 >/dev/null 2>&1; do sleep 2; done

      # Pre-pull control plane images to avoid timeouts
      kubeadm config images pull --config /etc/kubernetes/kubeadm-init.yaml || true

      # Run kubeadm init if not already initialized
      if [ ! -f /etc/kubernetes/admin.conf ]; then
        kubeadm init --config /etc/kubernetes/kubeadm-init.yaml
      fi

      # Configure kubeconfig for root
      mkdir -p /root/.kube
      cp /etc/kubernetes/admin.conf /root/.kube/config
      chown root:root /root/.kube/config
      export KUBECONFIG=/etc/kubernetes/admin.conf
      # Configure kubeconfig for ampere user
      if id ampere &>/dev/null; then
        rm -rf /home/ampere/.kube
        install -d -m700 -o ampere -g ampere /home/ampere/.kube
        install -m600 -o ampere -g ampere /etc/kubernetes/admin.conf /home/ampere/.kube/config
      fi

      # Apply Calico (operator + custom resources) with custom CIDR and interface autodetection
      kubectl apply --validate=false -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/tigera-operator.yaml
      # Wait for CRDs to be established
      for i in {1..30}; do
        kubectl get crd installations.operator.tigera.io &>/dev/null && break
        sleep 5
      done
      # Wait for operator availability (best effort)
      kubectl wait --for=condition=Available deployment/tigera-operator -n tigera-operator --timeout=180s || true
      curl -LO https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/custom-resources.yaml
      sed -i "s#cidr: 192.168.0.0/16#cidr: ${pod_network_cidr}#g" custom-resources.yaml
      sed -i "/nodeSelector: all()/a\    nodeAddressAutodetectionV4:\n      interface: ${calico_interface}" custom-resources.yaml
      kubectl apply --validate=false -f custom-resources.yaml
      rm -f custom-resources.yaml

      # Generate join materials and restart HTTP server
      /usr/local/bin/write-join.sh
      systemctl restart kubeadm-join-http.service || true

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
  - systemctl restart systemd-networkd
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
  - curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  - helm plugin install https://github.com/jkroepke/helm-secrets --version v4.6.0 || true  
  - systemctl enable kubelet  
  - echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/99-kubernetes-ipforward.conf
  - sysctl --system
  - systemctl enable containerd
  - mkdir -p /etc/containerd
  - containerd config default | tee /etc/containerd/config.toml
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - systemctl restart containerd
  - until systemctl is-active --quiet systemd-networkd containerd; do sleep 2; done
  - until ping -c1 8.8.8.8 >/dev/null 2>&1; do sleep 2; done
  - kubeadm config images pull --config /etc/kubernetes/kubeadm-init.yaml || true
  - systemctl daemon-reload
  - systemctl enable kubeadm-write-join.service
  - systemctl enable kubeadm-join-http.service
  - systemctl enable bootstrap-master.service
  - systemctl start bootstrap-master.service --no-block
