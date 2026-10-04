#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
local_terraform_dir="${script_dir}"
local_tfvars="${local_terraform_dir}/libvirt/terraform.tfvars"

remote_host="${TF_REMOTE_HOST:-oppie@oppie-server}"
remote_root="${TF_REMOTE_ROOT:-/home/oppie/projects/bohr_project}"
ssh_port="${TF_SSH_PORT:-22}"
ssh_identity="${TF_SSH_IDENTITY:-}"

do_sync=true
do_validate=false
do_plan=false
do_apply=false
interactive=true
action_was_selected=false

usage() {
  cat <<'EOF'
Usage: bash terraform/remote-run.sh [options]

Synchronize the local terraform/ tree to the Ubuntu KVM host, then optionally
validate, plan, or apply the libvirt module on that host. Terraform state,
provider cache, local overrides, and state backups are preserved. The tracked
provider lock file is synchronized with the configuration.
The SOPS-encrypted local terraform.tfvars is decrypted directly into the SSH
stream; no plaintext copy is written on the local machine.

Connection options:
  --host USER@HOST       Ubuntu host (default: TF_REMOTE_HOST or oppie@oppie-server)
  --remote-root PATH     Remote repository root (default: TF_REMOTE_ROOT or
                         /home/oppie/projects/bohr_project)
  --port PORT            SSH port (default: TF_SSH_PORT or 22)
  --identity PATH        SSH private key (default: TF_SSH_IDENTITY)

Action options:
  --sync-only            Sync and stop
  --no-sync              Do not synchronize before the selected action
  --validate             Run terraform fmt -check, init, and validate
  --plan                 Validate and create/show a saved Terraform plan
  --apply                Validate, plan, and apply the saved plan
  --non-interactive      Do not ask questions; actions must be supplied as flags
  -h, --help             Show this help

With no action flags, the script asks which actions to run. Apply is always
opt-in and requires typing APPLY in interactive mode.

Examples:
  bash terraform/remote-run.sh
  bash terraform/remote-run.sh --validate --plan
  TF_REMOTE_HOST=oppie@192.168.1.29 bash terraform/remote-run.sh --sync-only
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

ask_yes_no() {
  local prompt="$1"
  local default_answer="$2"
  local answer
  local suffix='[y/N]'

  if [[ "${default_answer}" == "yes" ]]; then
    suffix='[Y/n]'
  fi

  read -r -p "${prompt} ${suffix} " answer
  answer="${answer:-${default_answer}}"
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

while (($# > 0)); do
  case "$1" in
    --host)
      (($# >= 2)) || die '--host requires a value'
      remote_host="$2"
      shift 2
      ;;
    --remote-root)
      (($# >= 2)) || die '--remote-root requires a value'
      remote_root="$2"
      shift 2
      ;;
    --port)
      (($# >= 2)) || die '--port requires a value'
      ssh_port="$2"
      shift 2
      ;;
    --identity)
      (($# >= 2)) || die '--identity requires a value'
      ssh_identity="$2"
      shift 2
      ;;
    --sync-only)
      action_was_selected=true
      shift
      ;;
    --no-sync)
      do_sync=false
      shift
      ;;
    --validate)
      do_validate=true
      action_was_selected=true
      shift
      ;;
    --plan)
      do_validate=true
      do_plan=true
      action_was_selected=true
      shift
      ;;
    --apply)
      do_validate=true
      do_plan=true
      do_apply=true
      action_was_selected=true
      shift
      ;;
    --non-interactive)
      interactive=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ "${remote_host}" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$ ]] || \
  die "--host must look like USER@HOST: ${remote_host}"
[[ "${remote_root}" =~ ^/[A-Za-z0-9._/-]+$ && "${remote_root}" != "/" ]] || \
  die "--remote-root must be a safe absolute path without spaces"
[[ "${ssh_port}" =~ ^[0-9]+$ ]] || die '--port must be numeric'
[[ -f "${repo_root}/.sops.yaml" ]] || die "missing ${repo_root}/.sops.yaml"
[[ -f "${local_tfvars}" ]] || die "missing ${local_tfvars}"

for command_name in ssh tar sops; do
  command -v "${command_name}" >/dev/null 2>&1 || die "required local command not found: ${command_name}"
done

ssh_options=(-o BatchMode=yes -o ConnectTimeout=10 -p "${ssh_port}")
if [[ -n "${ssh_identity}" ]]; then
  [[ -f "${ssh_identity}" ]] || die "SSH identity not found: ${ssh_identity}"
  ssh_options+=(-i "${ssh_identity}")
fi

remote_terraform_dir="${remote_root%/}/terraform"
remote_module_dir="${remote_terraform_dir}/libvirt"
remote_plan_file="${remote_module_dir}/.terraform/bohr-remote.tfplan"

if [[ "${interactive}" == true && "${action_was_selected}" == false ]]; then
  ask_yes_no 'Synchronize Terraform configuration to the Ubuntu host?' yes || do_sync=false
  ask_yes_no 'Run Terraform formatting and validation?' yes && do_validate=true
  if ask_yes_no 'Create and show a Terraform plan?' no; then
    do_validate=true
    do_plan=true
  fi
  if [[ "${do_plan}" == true ]] && ask_yes_no 'Offer to apply the saved plan after review?' no; then
    do_apply=true
  fi
fi

if [[ "${interactive}" == false && "${action_was_selected}" == false ]]; then
  die '--non-interactive requires an action flag such as --sync-only, --validate, --plan, or --apply'
fi

printf 'Ubuntu host:       %s\n' "${remote_host}"
printf 'Remote Terraform:  %s\n' "${remote_terraform_dir}"
printf 'Actions:           sync=%s validate=%s plan=%s apply=%s\n' \
  "${do_sync}" "${do_validate}" "${do_plan}" "${do_apply}"

ssh "${ssh_options[@]}" "${remote_host}" \
  "command -v terraform >/dev/null && command -v rsync >/dev/null && command -v tar >/dev/null" || \
  die 'remote host is unreachable or is missing terraform, rsync, or tar'

if [[ "${do_sync}" == true ]]; then
  printf '\nSynchronizing Terraform configuration...\n'
  remote_stage="$({ ssh "${ssh_options[@]}" "${remote_host}" \
    "mktemp -d /tmp/bohr-terraform-sync.XXXXXX"; } | tr -d '\r\n')"
  [[ "${remote_stage}" =~ ^/tmp/bohr-terraform-sync\.[A-Za-z0-9]+$ ]] || \
    die "remote host returned an unsafe staging path: ${remote_stage}"

  cleanup_stage() {
    ssh "${ssh_options[@]}" "${remote_host}" "rm -rf -- '${remote_stage}'" >/dev/null 2>&1 || true
  }
  trap cleanup_stage EXIT

  tar \
    --exclude='./libvirt/.terraform' \
    --exclude='./libvirt/terraform.tfvars' \
    --exclude='./libvirt/terraform.local.tfvars' \
    --exclude='./libvirt/terraform.tfstate' \
    --exclude='./libvirt/terraform.tfstate.*' \
    --exclude='./libvirt/crash.log' \
    --exclude='./libvirt/crash.*.log' \
    -C "${local_terraform_dir}" -czf - . | \
    ssh "${ssh_options[@]}" "${remote_host}" "tar -xzf - -C '${remote_stage}'"

  sops --config "${repo_root}/.sops.yaml" --decrypt "${local_tfvars}" | \
    ssh "${ssh_options[@]}" "${remote_host}" \
      "umask 077; cat > '${remote_stage}/libvirt/terraform.tfvars'"

  ssh "${ssh_options[@]}" "${remote_host}" "set -eu
    mkdir -p '${remote_terraform_dir}'
    rsync -a --delete \
      --exclude='.terraform/' \
      --exclude='terraform.local.tfvars' \
      --exclude='terraform.tfstate' \
      --exclude='terraform.tfstate.*' \
      --exclude='terraform.tfvars.bak*' \
      --exclude='crash.log' \
      --exclude='crash.*.log' \
      '${remote_stage}/' '${remote_terraform_dir}/'
    chmod 600 '${remote_module_dir}/terraform.tfvars'
    rm -rf -- '${remote_stage}'"

  trap - EXIT
  printf 'Synchronization complete. Remote state and runtime files were preserved.\n'
fi

if [[ "${do_validate}" == true ]]; then
  printf '\nRunning Terraform validation on the Ubuntu host...\n'
  ssh -t "${ssh_options[@]}" "${remote_host}" "set -eu
    terraform -chdir='${remote_module_dir}' fmt -check -recursive
    terraform -chdir='${remote_module_dir}' init -input=false
    terraform -chdir='${remote_module_dir}' validate"
fi

plan_has_changes=false
if [[ "${do_plan}" == true ]]; then
  printf '\nCreating a saved Terraform plan on the Ubuntu host...\n'
  set +e
  ssh -t "${ssh_options[@]}" "${remote_host}" \
    "terraform -chdir='${remote_module_dir}' plan -input=false -detailed-exitcode -out='${remote_plan_file}'"
  plan_exit=$?
  set -e

  case "${plan_exit}" in
    0)
      printf 'Terraform reports no infrastructure changes.\n'
      ;;
    2)
      plan_has_changes=true
      printf 'Terraform plan contains changes. Review them above before applying.\n'
      ;;
    *)
      die "terraform plan failed with exit code ${plan_exit}"
      ;;
  esac
fi

if [[ "${do_apply}" == true ]]; then
  if [[ "${plan_has_changes}" != true ]]; then
    printf 'Nothing to apply.\n'
    exit 0
  fi

  if [[ "${interactive}" == true ]]; then
    printf '\nApplying Terraform can replace virtual machines.\n'
    read -r -p 'Type APPLY to execute the saved plan: ' apply_confirmation
    [[ "${apply_confirmation}" == 'APPLY' ]] || die 'apply cancelled'
  else
    printf 'Non-interactive --apply was explicitly selected; applying the saved plan.\n'
  fi

  ssh -t "${ssh_options[@]}" "${remote_host}" \
    "terraform -chdir='${remote_module_dir}' apply '${remote_plan_file}'"
fi

printf '\nDone.\n'
