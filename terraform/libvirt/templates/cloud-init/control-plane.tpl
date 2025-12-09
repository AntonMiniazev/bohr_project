#cloud-config
hostname: ${hostname}
timezone: Europe/Belgrade
users:
  - name: ampere
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - "${key}"
%{ endfor ~}
package_update: true
package_upgrade: true
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - software-properties-common
write_files:
  - path: /etc/netplan/01-netcfg.yaml
    permissions: '0644'
    content: |
      network:
        version: 2
        ethernets:
          ens3:
            dhcp4: no
            addresses: [${ip}/${prefix}]
            gateway4: ${gateway}
            nameservers:
              addresses: [${join(", ", dns)}]
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
  - path: /etc/systemd/system/kubeadm-init.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Run kubeadm init on first boot
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/bin/kubeadm init --config /etc/kubernetes/kubeadm-init.yaml
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target
runcmd:
  - netplan apply
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  - modprobe br_netfilter
  - echo 'net.bridge.bridge-nf-call-iptables=1' | tee /etc/sysctl.d/k8s.conf
  - sysctl --system
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - apt-get install -y kubelet kubeadm kubectl containerd.io
  - systemctl enable containerd
  - containerd config default | tee /etc/containerd/config.toml
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - systemctl restart containerd
  - systemctl enable kubeadm-init.service
  - systemctl start kubeadm-init.service
  - systemctl enable kubeadm-write-join.service
  - systemctl enable kubeadm-join-http.service
  - systemctl start kubeadm-write-join.service
  - systemctl start kubeadm-join-http.service
