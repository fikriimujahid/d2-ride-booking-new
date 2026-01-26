#!/usr/bin/env bash
set -euo pipefail

# Infracost cost estimation helper.
# - CI/CD friendly (GitHub Actions / GitLab CI)
# - No static AWS access keys (Terraform may still require OIDC/role auth for data sources/backends)
# - Read-only: does NOT apply changes

usage() {
  cat <<'EOF'
Usage:
  infra/scripts/infracost-estimate.sh [--env dev|prod] [--mode hcl|plan-json|state] [--path <path>]

Modes:
  hcl       : Estimate from Terraform HCL directory (recommended; no Terraform plan required)
  plan-json : Estimate from a Terraform plan JSON file (e.g. terraform show -json plan.tfplan > plan.json)
  state     : Estimate from Terraform state (read-only). Requires access to the backend/state.

Args:
  --env   : Environment name (used only for defaults). Default: dev
  --mode  : Default: plan-json if a plan JSON is present, else hcl
  --path  : Path to Terraform directory or plan.json depending on mode.
            Defaults:
              hcl       -> infra/terraform/envs/<env>
              plan-json -> infra/terraform/envs/<env>/plan.json
              state     -> infra/terraform/envs/<env> (Terraform backend must be accessible)

Required env vars:
  INFRACOST_API_KEY  : Infracost Cloud Pricing API key (store as CI secret)

Optional env vars:
  INFRACOST_CURRENCY : e.g. USD, SGD

Output:
  - Prints a readable table to stdout
  - Writes JSON output to: infra/terraform/envs/<env>/infracost-breakdown.json

EOF
}

log() { echo "[infracost] $*"; }
err() { echo "[infracost] ERROR: $*" >&2; }

detect_ci() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "github"
  elif [[ -n "${GITLAB_CI:-}" ]]; then
    echo "gitlab"
  else
    echo "local"
  fi
}

install_infracost() {
  if command -v infracost >/dev/null 2>&1; then
    return 0
  fi

  local ci
  ci="$(detect_ci)"

  # Official methods:
  # - macOS: brew install infracost
  # - Windows: choco install infracost
  # - Linux/macOS manual: GitHub release
  # In CI (Linux runners), we use the official install script from the Infracost repo.
  if [[ "$(uname -s)" == "Linux" || "$(uname -s)" == "Darwin" ]]; then
    log "Installing Infracost (ci=${ci})"
    curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh \
      | sh -s -- -b /usr/local/bin
  else
    err "Unsupported OS for this installer. Install Infracost manually: https://www.infracost.io/docs/#quick-start"
    exit 2
  fi
}

require_api_key() {
  if [[ -z "${INFRACOST_API_KEY:-}" ]]; then
    err "INFRACOST_API_KEY is not set"
    err "Set it via your CI secret store (GitHub Actions secrets / GitLab CI variables)"
    exit 1
  fi
}

ENV_NAME="dev"
MODE=""
PATH_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_NAME="$2"; shift 2 ;;
    --mode)
      MODE="$2"; shift 2 ;;
    --path)
      PATH_ARG="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      err "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_ENV_DIR="${REPO_ROOT}/infra/terraform/envs/${ENV_NAME}"
DEFAULT_PLAN_JSON="${TF_ENV_DIR}/plan.json"

if [[ -z "${MODE}" ]]; then
  if [[ -f "${DEFAULT_PLAN_JSON}" ]]; then
    MODE="plan-json"
  else
    MODE="hcl"
  fi
fi

if [[ -z "${PATH_ARG}" ]]; then
  case "${MODE}" in
    hcl) PATH_ARG="${TF_ENV_DIR}";;
    plan-json) PATH_ARG="${DEFAULT_PLAN_JSON}";;
    state) PATH_ARG="${TF_ENV_DIR}";;
    *) err "Invalid mode: ${MODE}"; usage; exit 2;;
  esac
fi

log "CI: $(detect_ci)"
log "Env: ${ENV_NAME}"
log "Mode: ${MODE}"
log "Path: ${PATH_ARG}"

require_api_key
install_infracost
infracost --version

OUT_JSON="${TF_ENV_DIR}/infracost-breakdown.json"

case "${MODE}" in
  hcl)
    infracost breakdown --path "${PATH_ARG}" --format table --show-skipped
    infracost breakdown --path "${PATH_ARG}" --format json --out-file "${OUT_JSON}"
    ;;
  plan-json)
    if [[ ! -f "${PATH_ARG}" ]]; then
      err "Plan JSON not found: ${PATH_ARG}"
      err "Generate it with: terraform plan -out plan.tfplan && terraform show -json plan.tfplan > plan.json"
      exit 1
    fi
    infracost breakdown --path "${PATH_ARG}" --format table --show-skipped
    infracost breakdown --path "${PATH_ARG}" --format json --out-file "${OUT_JSON}"
    ;;
  state)
    # Uses terraform state via the Terraform directory. This is read-only but requires backend access.
    # Note: this may require AWS auth (OIDC/assumed role) for the backend (e.g. S3) and any data sources.
    infracost breakdown --path "${PATH_ARG}" --terraform-use-state --format table --show-skipped
    infracost breakdown --path "${PATH_ARG}" --terraform-use-state --format json --out-file "${OUT_JSON}"
    ;;
  *)
    err "Invalid mode: ${MODE}"; usage; exit 2 ;;
 esac

log "Wrote JSON output: ${OUT_JSON}"
