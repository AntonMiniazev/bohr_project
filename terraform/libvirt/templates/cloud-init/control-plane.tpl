#cloud-config
hostname: ${control_plane.hostname}
timezone: Europe/Belgrade
ssh_pwauth: false
users:
  - name: ${identity.project_name}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    ssh_authorized_keys:
%{ for key in ssh.ssh_public_keys ~}
      - "${key}"
%{ endfor ~}

package_update: false
package_upgrade: false

write_files:

  - path: /etc/containerd/certs.d/docker.io/hosts.toml
    permissions: '0644'
    content: |
      server = "https://docker.io"

      [host."https://registry-1.docker.io"]
        capabilities = ["pull", "resolve"]

        [host."https://registry-1.docker.io".auth]
          username = ${registry.dockerhub_username}
          password = ${registry.dockerhub_token}

  # --- Stage 1 bootstrap script ---
  - path: /usr/local/bin/bootstrap-init.sh
    permissions: '0755'
    content: |
${bootstrap_init_script_indented}

  # --- Stage 1 systemd unit ---
  - path: /etc/systemd/system/bootstrap-init.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Stage 1 - OS ready (network + container runtime)
      Wants=network-online.target systemd-networkd-wait-online.service
      After=network-online.target systemd-networkd-wait-online.service
      ConditionPathExists=!/var/lib/${identity.project_name}/OS_READY

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/bootstrap-init.sh
      ExecStartPost=/bin/systemctl start --no-block bootstrap-k8s.service
      RemainAfterExit=yes
      Restart=no

      [Install]
      WantedBy=multi-user.target


  # --- bpffs mount unit (required by Cilium) ---
  - path: /etc/systemd/system/sys-fs-bpf.mount
    permissions: '0644'
    content: |
      [Unit]
      Description=BPF filesystem
      DefaultDependencies=no
      Before=local-fs.target

      [Mount]
      What=bpf
      Where=/sys/fs/bpf
      Type=bpf
      Options=rw,nosuid,nodev,noexec,relatime

      [Install]
      WantedBy=multi-user.target      

  # --- Stage 2 Kubernetes control plane setup ---
  
  - path: /etc/kubernetes/kubeadm-init.yaml
    permissions: '0644'
    content: |
${kubeadm_init_indented}

  - path: /usr/local/bin/bootstrap-k8s.sh
    permissions: '0755'
    content: |
${bootstrap_master_script_indented}

  - path: /etc/systemd/system/bootstrap-k8s.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Stage 2 - Bootstrap Kubernetes control plane
      Wants=network-online.target systemd-networkd-wait-online.service
      After=network-online.target systemd-networkd-wait-online.service bootstrap-init.service
      Requires=bootstrap-init.service
      ConditionPathExists=/var/lib/${identity.project_name}/OS_READY
      ConditionPathExists=!/etc/kubernetes/admin.conf

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/bootstrap-k8s.sh
      ExecStartPost=/bin/systemctl start --no-block bootstrap-addons.service
      RemainAfterExit=yes
      Restart=no

      [Install]
      WantedBy=multi-user.target

  # --- Stage 3 CNI, local-path, addons and joins ---

  - path: /opt/bootstrap/local-path-configmap.yaml
    permissions: '0644'
    content: |
${local_path_configmap_indented}

  - path: /opt/bootstrap/local-path-shared-storageclass.yaml
    permissions: '0644'
    content: |
${local_path_shared_storageclass_indented}

  - path: /usr/local/bin/bootstrap-addons.sh
    permissions: '0755'
    content: |
${bootstrap_addons_script_indented}

  - path: /etc/systemd/system/bootstrap-addons.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Stage 3 - Install CNI and cluster addons
      Requires=bootstrap-k8s.service
      After=bootstrap-k8s.service
      ConditionPathExists=/var/lib/${identity.project_name}/CONTROL_PLANE_CREATED
      ConditionPathExists=!/var/lib/${identity.project_name}/ADDONS_DONE

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/bootstrap-addons.sh
      ExecStartPost=/bin/systemctl start --no-block kubeadm-write-join.service
      RemainAfterExit=yes
      Restart=no

      [Install]
      WantedBy=multi-user.target

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
      echo "kubeadm join ${control_plane.ip}:6443 --token $token --discovery-token-ca-cert-hash sha256:$hash" > /var/lib/kubeadm/join.sh
      chmod +x /var/lib/kubeadm/join.sh

  - path: /etc/systemd/system/kubeadm-write-join.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Generate kubeadm join materials (post-CNI)
      Requires=bootstrap-addons.service
      After=bootstrap-addons.service
      ConditionPathExists=/var/lib/${identity.project_name}/CONTROL_PLANE_CREATED

      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/write-join.sh
      ExecStartPost=/bin/systemctl start --no-block kubeadm-join-http.service
      RemainAfterExit=yes
      Restart=no

  - path: /etc/systemd/system/kubeadm-join-http.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Serve kubeadm join artifacts over HTTP
      After=kubeadm-write-join.service
      ConditionPathExists=/var/lib/kubeadm/join.sh

      [Service]
      WorkingDirectory=/var/lib/kubeadm
      ExecStart=/usr/bin/python3 -m http.server ${join.join_http_port} --bind ${join.join_http_bind_address}
      Restart=on-failure
      RestartSec=2

      [Install]
      WantedBy=multi-user.target

runcmd:
  - mkdir -p /sys/fs/bpf
  - sed -i 's/\r$//' /etc/systemd/system/sys-fs-bpf.mount || true
  - systemctl daemon-reload
  - systemctl enable --now sys-fs-bpf.mount
  - systemctl enable bootstrap-init.service
  - systemctl enable bootstrap-k8s.service
  - systemctl start bootstrap-init.service --no-block
