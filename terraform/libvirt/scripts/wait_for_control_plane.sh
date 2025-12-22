#!/usr/bin/env bash
set -eu

: "${CONTROL_PLANE_HOSTNAME:?}"
: "${CONTROL_PLANE_USER:?}"
: "${KNOWN_HOSTS_PATH:?}"
: "${PROJECT_NAME:?}"

KNOWN_HOSTS_DIR="$(dirname "${KNOWN_HOSTS_PATH}")"
mkdir -p "${KNOWN_HOSTS_DIR}"

ssh-keygen -f "${KNOWN_HOSTS_PATH}" -R "${CONTROL_PLANE_HOSTNAME}" >/dev/null 2>&1 || true

echo "[INFO] Waiting for SSH on ${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME} ..."
for i in $(seq 1 20); do
  if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" -o LogLevel=ERROR \
    "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" "echo ok" >/dev/null 2>&1; then
    echo "[INFO] SSH is ready"
    break
  fi
  echo "[INFO] SSH not ready yet"
  sleep 30
done

if ! ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" -o LogLevel=ERROR \
  "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" "echo ok" >/dev/null 2>&1; then
  echo "[ERROR] SSH did not become ready" >&2
  exit 1
fi

echo "[INFO] Waiting for bootstrap-k8s.service to complete..."
for i in $(seq 1 30); do
  status=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" \
    "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" "systemctl is-active bootstrap-k8s.service || true")

  if [ "${status}" = "active" ]; then
    echo "[INFO] bootstrap-k8s.service still running..."
  elif [ "${status}" = "inactive" ]; then
    echo "[INFO] bootstrap-k8s.service finished successfully"
    break
  else
    echo "[ERROR] bootstrap-k8s.service failed with status=${status}"
    exit 1
  fi
  sleep 20
done

echo "[INFO] Waiting for bootstrap-addons.service to complete..."
for i in $(seq 1 30); do
  status=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" \
    "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" "systemctl is-active bootstrap-addons.service || true")

  if [ "${status}" = "active" ]; then
    echo "[INFO] bootstrap-addons.service still running..."
  elif [ "${status}" = "inactive" ]; then
    echo "[INFO] bootstrap-addons.service finished successfully"
    break
  else
    echo "[ERROR] bootstrap-addons.service failed with status=${status}"
    exit 1
  fi
  sleep 20
done

echo "[INFO] Waiting for cloud-init to reach a final state..."
ci_status=""
for i in $(seq 1 15); do
  ci_line=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" \
    "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" "sudo cloud-init status 2>/dev/null" || true)
  ci_status=$(printf '%s\n' "$ci_line" | cut -d' ' -f2 || true)

  if [ "${ci_status}" = "running" ]; then
    echo "[INFO] cloud-init status is running, waiting..."
  elif [ "${ci_status}" = "done" ]; then
    echo "[INFO] cloud-init finished successfully"
    break
  elif [ "${ci_status}" = "error" ]; then
    echo "[ERROR] cloud-init finished with error:"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" \
      "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" "sudo cloud-init status --long || true"
    exit 1
  else
    echo "[WARN] cloud-init status is '${ci_status}', waiting..."
  fi
  sleep 20
done

if [ "${ci_status}" != "done" ] && [ "${ci_status}" != "error" ]; then
  echo "[ERROR] Timeout waiting for cloud-init to finish (last status: ${ci_status})" >&2
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" \
    "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" "sudo cloud-init status --long || true"
  exit 1
fi

echo "[INFO] Final cloud-init status:"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" \
  "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" "sudo cloud-init status --long || true"

echo "[INFO] Validating cloud-init schema..."
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" \
  "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" "sudo cloud-init schema --system >/dev/null 2>&1"; then
  echo "[INFO] cloud-init schema: OK"
else
  echo "[ERROR] cloud-init schema: FAILED" >&2
  exit 1
fi

echo "[INFO] Waiting for Kubernetes node ${CONTROL_PLANE_HOSTNAME} to be Ready..."
node_ready=false
for i in $(seq 1 20); do
  node_status=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}" \
    "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOSTNAME}" \
    "KUBECONFIG=/home/${CONTROL_PLANE_USER}/.kube/config kubectl get nodes --no-headers 2>/dev/null | grep '^${CONTROL_PLANE_HOSTNAME} ' | awk '{print \$2}'" \
    || true)

  printable_status="${node_status}"
  if [ -z "${printable_status}" ]; then
    printable_status="unknown"
  fi

  if [ "${node_status}" = "Ready" ]; then
    echo "[INFO] Node ${CONTROL_PLANE_HOSTNAME} is Ready"
    node_ready=true
    break
  fi

  echo "[INFO] Node ${CONTROL_PLANE_HOSTNAME} not Ready yet (status: ${printable_status}), waiting..."
  sleep 30
done

if [ "${node_ready}" != "true" ]; then
  printable_status="${node_status}"
  if [ -z "${printable_status}" ]; then
    printable_status="unknown"
  fi

  echo "[ERROR] Node ${CONTROL_PLANE_HOSTNAME} did not reach Ready state in time (last status: ${printable_status})" >&2
  exit 1
fi
