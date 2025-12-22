#!/usr/bin/env bash
set -eu

: "${CONTROL_PLANE_HOSTNAME:?}"
: "${CONTROL_PLANE_USER:?}"
: "${KNOWN_HOSTS_PATH:?}"
: "${WORKER_NODES:?}"

KNOWN_HOSTS_DIR="$(dirname "${KNOWN_HOSTS_PATH}")"
mkdir -p "${KNOWN_HOSTS_DIR}"

echo "[DEBUG] kh_path is ${KNOWN_HOSTS_PATH}"

echo "[INFO] Waiting for worker nodes to be Ready..."
for i in $(seq 1 10); do
  ready_nodes=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" \
    "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" \
    "KUBECONFIG=/home/${CONTROL_PLANE_USER}/.kube/config kubectl get nodes --no-headers 2>/dev/null | awk '\$2==\"Ready\" {print \$1}'" \
    | tr '\n' ' ')

  all_ready=true
  for node in ${WORKER_NODES}; do
    if ! echo "${ready_nodes}" | grep -q "\\b${node}\\b"; then
      all_ready=false
      echo "[INFO] ${node} not Ready yet"
    fi
  done

  if [ "${all_ready}" = true ]; then
    echo "[INFO] All worker nodes are Ready"
    exit 0
  fi

  sleep 60
done

echo "[ERROR] Worker nodes did not reach Ready state in time" >&2
exit 1
