      #!/bin/bash
      set -euo pipefail
  
      # --- Environment for kubectl / cilium ---
      export HOME=/root
      export XDG_CACHE_HOME=/root/.cache
      export KUBECONFIG=/etc/kubernetes/admin.conf
  
      echo "[DIAG] bootstrap-addons started at $(date)"

      # --- Idempotency guard ---
      if [ -f /var/lib/${identity.project_name}/ADDONS_DONE ]; then
        echo "[DIAG] ADDONS_DONE marker found, skipping"
        exit 0
      fi

      # --- Gate: control-plane marker ---
      if [ ! -f /var/lib/${identity.project_name}/CONTROL_PLANE_CREATED ]; then
        echo "[DIAG - FATAL] CONTROL_PLANE_CREATED marker not found"
        exit 1
      fi
  
      # --- Gate: kubeconfig ---
      echo "[DIAG] Waiting for kubeconfig..."
      for i in {1..60}; do
        [ -f /etc/kubernetes/admin.conf ] && break
        sleep 2
      done
  
      if [ ! -f /etc/kubernetes/admin.conf ]; then
        echo "[DIAG - FATAL] kubeconfig not found"
        exit 1
      fi
  
      # --- Gate: API reachable (NO NodeReady checks) ---
      echo "[DIAG] Waiting for API /readyz..."
      for i in {1..90}; do
        if kubectl get --raw=/readyz >/dev/null 2>&1; then
          echo "[DIAG] API is ready"
          break
        fi
        sleep 4
      done
  
      if ! kubectl get --raw=/readyz >/dev/null 2>&1; then
        echo "[DIAG - FATAL] API did not become ready"
        exit 1
      fi
  
      # -------------------------------------------------------------------
      # CNI: Cilium
      # -------------------------------------------------------------------
  
      echo "[DIAG] Installing Cilium CLI"
  
      curl -L --fail -o /tmp/cilium.tar.gz \
        https://github.com/cilium/cilium-cli/releases/download/${packages.cilium.version_cli}/cilium-linux-amd64.tar.gz
  
      tar -xzf /tmp/cilium.tar.gz -C /usr/local/bin
      rm -f /tmp/cilium.tar.gz
  
      echo "[DIAG] Installing Cilium CNI"
  
      cilium install \
        --version "${packages.cilium.version_operator}" \
        --set kubeProxyReplacement=true \
        --set routingMode=native \
        --set autoDirectNodeRoutes=true \
        --set devices=${network.network_interface} \
        --set k8sServiceHost=${control_plane.ip} \
        --set k8sServicePort=6443 \
        --set ipam.mode=cluster-pool \
        --set ipam.operator.clusterPoolIPv4PodCIDRList=${packages.cilium.pod_network_cidr} \
        --set ipam.operator.clusterPoolIPv4MaskSize="24" \
        --set ipv4NativeRoutingCIDR=${packages.cilium.pod_network_cidr} \
        --set operator.replicas=${packages.cilium.operator_replicas}
  
      echo "[DIAG] Waiting for Cilium to become ready..."
      cilium status --wait
  
      echo "[DIAG] Cilium is Ready"
  
      # -------------------------------------------------------------------
      # Storage: local-path provisioner
      # -------------------------------------------------------------------
  
      echo "[DIAG] Installing local-path-provisioner"
  
      kubectl apply --validate=false -f "${addons.local_path_url}"
  
      echo "[DIAG] Waiting for local-path-storage namespace..."
      for i in {1..30}; do
        kubectl get ns local-path-storage >/dev/null 2>&1 && break
        sleep 3
      done
  
      kubectl apply --validate=false -f /opt/bootstrap/local-path-configmap.yaml
      kubectl apply --validate=false -f /opt/bootstrap/local-path-shared-storageclass.yaml

      kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || echo "[DIAG - WARN] StorageClass patch failed"
  
      # -------------------------------------------------------------------
      # Tooling (Helm / Helmfile / SOPS)
      # -------------------------------------------------------------------

      kubectl create namespace ${identity.project_name}

      echo "[DIAG] Installing helm, helmfile, sops"
  
      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -- --version "${packages.helm.version}"
  
      curl -L -o /usr/local/bin/helmfile \
        https://github.com/roboll/helmfile/releases/download/${packages.helmfile.version}/helmfile_linux_amd64
      chmod +x /usr/local/bin/helmfile
  
      curl -L -o /usr/local/bin/sops \
        https://github.com/getsops/sops/releases/download/${packages.sops.version}/sops-${packages.sops.version}.linux.amd64
      chmod +x /usr/local/bin/sops
  
      helm plugin install https://github.com/jkroepke/helm-secrets --version ${packages.helm_plugins.helm_secrets_version} || true
      helm plugin install https://github.com/databus23/helm-diff || true
  
      echo "$(date -Iseconds)" > /var/lib/${identity.project_name}/ADDONS_DONE
      sync

      echo "[DIAG] bootstrap-addons finished at $(date)"
