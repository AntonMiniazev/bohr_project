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
      # Configure kubeconfig for project user
      if id ${project_name} &>/dev/null; then
        rm -rf /home/${project_name}/.kube
        install -d -m700 -o ${project_name} -g ${project_name} /home/${project_name}/.kube
        install -m600 -o ${project_name} -g ${project_name} /etc/kubernetes/admin.conf /home/${project_name}/.kube/config
      fi

      # Creating namespace
      kubectl create namespace ${project_name}

      # --- Install Cilium CNI ---

      # Download cilium-cli (pinned)
      curl -L -o /usr/local/bin/cilium \
        "https://github.com/cilium/cilium-cli/releases/download/v${cilium_version}/cilium-linux-amd64"
      chmod +x /usr/local/bin/cilium

      # Install Cilium (kube-proxy remains enabled; simplest path)
      cilium install \
        --version "v${cilium_version}" \
        --set ipam.mode=cluster-pool \
        --set ipam.operator.clusterPoolIPv4PodCIDRList=${pod_network_cidr} \
        --set ipam.operator.clusterPoolIPv4MaskSize="24" \
        --set operator.replicas=${cilium_replicas}

      # Optional: wait until ready (best effort)
      cilium status --wait || true

      # Install local-path-provisioner (Rancher) with RWX support
      kubectl apply -f "${local_path_url}"

      # Wait for namespace
      for i in {1..20}; do
        kubectl get ns local-path-storage &>/dev/null && break
        sleep 3
      done      

      # Patch ConfigMap to enable shared filesystem (RWX)
      kubectl apply -f /opt/bootstrap/local-path-configmap.yaml

      # Ensure shared directory exists on master
      mkdir -p /opt/local-path-provisioner/shared
      chmod 0777 /opt/local-path-provisioner/shared

      # Patch StorageClass to be default (best-effort)
      kubectl patch storageclass local-path \
        -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' \
        || true

      # Generate join materials and restart HTTP server
      /usr/local/bin/write-join.sh
      systemctl restart kubeadm-join-http.service || true