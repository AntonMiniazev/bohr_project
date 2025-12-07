      #!/bin/bash
      set -euo pipefail
  
      echo "[DIAG] bootstrap-k8s started at $(date)"
  
      # --- Kubernetes host preparation ---
      echo "[DIAG] Disabling swap for Kubernetes"
      swapoff -a
      sed -i '/ swap / s/^/#/' /etc/fstab
      
  
      # --- Idempotency guard ---
      if [ -f /etc/kubernetes/admin.conf ]; then
        echo "[DIAG] admin.conf already exists, skipping kubeadm init"
      else
        echo "[DIAG] Installing Kubernetes packages"
  
        install -d -m 0755 /etc/apt/keyrings
        curl -fsSL https://pkgs.k8s.io/core:/stable:/${packages.kubernetes.repo_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${packages.kubernetes.repo_version}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  
        for i in {1..5}; do
          if apt-get update; then break; fi
          echo "[DIAG - WARN] apt-get update failed, retry $i/5"
          sleep 10
        done
      # Containers
        DEBIAN_FRONTEND=noninteractive apt-get install -y conntrack containerd kubelet kubeadm kubectl
  
        echo "[DIAG] Configuring containerd for Kubernetes"

        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

        echo "[DIAG] Enabling and starting containerd"
        systemctl daemon-reexec
        systemctl enable --now containerd.service
        systemctl restart containerd.service

        for i in {1..60}; do
          if systemctl is-active --quiet containerd; then break; fi
          sleep 2
        done
  
        if ! systemctl is-active --quiet containerd; then
          echo "[DIAG - FATAL] containerd did not become active"
          exit 1
        fi
        # kubelet kubeadm kubectl
        DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
        echo "[DIAG] Enabling kubelet"
        systemctl enable --now kubelet.service
        systemctl start kubelet || true
  
        echo "[DIAG] Pre-pulling control-plane images (best-effort)"
        kubeadm config images pull --config /etc/kubernetes/kubeadm-init.yaml || true
  
        if [ -d /var/lib/etcd/member ]; then
          echo "[DIAG - FATAL] /var/lib/etcd/member exists before init (dirty control-plane)"
          exit 1
        fi
  
        echo "[DIAG] Running kubeadm init"
        kubeadm init --config /etc/kubernetes/kubeadm-init.yaml
        echo "[DIAG] kubeadm init completed"
      fi
  
      # --- kubeconfig for root ---
      echo "[DIAG] Configuring kubeconfig for root"
      mkdir -p /root/.kube
      cp /etc/kubernetes/admin.conf /root/.kube/config
      chmod 600 /root/.kube/config
  
      # --- kubeconfig for project user ---
      if id "${identity.project_name}" >/dev/null 2>&1; then
        echo "[DIAG] Configuring kubeconfig for user ${identity.project_name}"
        rm -rf "/home/${identity.project_name}/.kube"
        install -d -m700 -o "${identity.project_name}" -g "${identity.project_name}" "/home/${identity.project_name}/.kube"
        install -m600 -o "${identity.project_name}" -g "${identity.project_name}" /etc/kubernetes/admin.conf "/home/${identity.project_name}/.kube/config"
      else
        echo "[DIAG] User ${identity.project_name} does not exist, skipping user kubeconfig"
      fi
  
      # --- API_STABLE gate ---
      echo "[DIAG] Waiting for apiserver port 6443"
      for i in {1..60}; do
        if ss -lnt | grep -q ':6443'; then break; fi
        sleep 2
      done
  
      if ! ss -lnt | grep -q ':6443'; then
        echo "[DIAG - FATAL] kube-apiserver is not listening on 6443"
        exit 1
      fi
  
      echo "[DIAG] Waiting for API /readyz"
      for i in {1..90}; do
        if curl -kfs https://${control_plane.ip}:6443/readyz >/dev/null 2>&1; then
          echo "[DIAG] API /readyz is OK"
          break
        fi
        sleep 2
      done
  
      if ! curl -kfs https://${control_plane.ip}:6443/readyz >/dev/null 2>&1; then
        echo "[DIAG - FATAL] API /readyz did not become ready"
        exit 1
      fi
  
      # --- CONTROL_PLANE_CREATED marker ---
      echo "[DIAG] Writing CONTROL_PLANE_CREATED marker"
      echo "$(date -Iseconds)" > /var/lib/${identity.project_name}/CONTROL_PLANE_CREATED
      sync
  
      echo "[DIAG] bootstrap-k8s finished at $(date)"
