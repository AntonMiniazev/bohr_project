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
  - path: /etc/kubernetes/kubeadm-join.yaml
    permissions: '0644'
    content: |
${kubeadm_join_yaml}
  - path: /usr/local/bin/kubeadm-join-retry.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      # If already joined, exit
      if [ -f /etc/kubernetes/kubelet.conf ]; then
        exit 0
      fi
      for i in {1..30}; do
        if kubeadm join --config /etc/kubernetes/kubeadm-join.yaml; then
          exit 0
        fi
        sleep 10
      done
      exit 1
  - path: /etc/systemd/system/kubeadm-join.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Run kubeadm join on first boot
      After=network-online.target containerd.service
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/kubeadm-join-retry.sh
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
  - systemctl enable kubeadm-join.service
  - systemctl start kubeadm-join.service
