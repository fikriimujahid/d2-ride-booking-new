#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# DEV INFRASTRUCTURE DIAGRAM (INFRAMAP)
# ============================================================================
# This script generates a human-readable architecture diagram for the DEV
# environment only. It uses Terraform inputs/state and Inframap to create
# a DOT file and then renders SVG + PNG via Graphviz.
#
# VALIDATION CHECKLIST (COMMENTS):
# - Diagram shows VPC, subnets, RDS, EC2 roles, security groups
# - Diagram generation is repeatable
# - No infrastructure changes occur
# - Diagram is suitable for README or presentation
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$ROOT_DIR/infra/terraform/envs/dev"
OUT_DIR="$ROOT_DIR/docs/diagrams"
DOT_OUT="$OUT_DIR/dev-infra.dot"
SVG_OUT="$OUT_DIR/dev-infra.svg"
PNG_OUT="$OUT_DIR/dev-infra.png"

mkdir -p "$OUT_DIR"

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v inframap >/dev/null 2>&1; then
  if command -v go >/dev/null 2>&1; then
    GO_BIN="$(go env GOPATH)/bin"
    if [ -x "$GO_BIN/inframap" ]; then
      INFRAMAP_BIN="$GO_BIN/inframap"
    elif [ -x "$GO_BIN/inframap.exe" ]; then
      INFRAMAP_BIN="$GO_BIN/inframap.exe"
    else
      echo "Error: inframap is not installed or not in PATH." >&2
      exit 1
    fi
  else
    echo "Error: inframap is not installed or not in PATH." >&2
    exit 1
  fi
else
  INFRAMAP_BIN="$(command -v inframap)"
fi

if command -v dot >/dev/null 2>&1; then
  DOT_BIN="$(command -v dot)"
elif [ -x "/c/Program Files/Graphviz/bin/dot.exe" ]; then
  DOT_BIN="/c/Program Files/Graphviz/bin/dot.exe"
else
  DOT_BIN=""
fi

# Terraform init: safe, no apply, no AWS credentials required.
terraform -chdir="$TF_DIR" init -backend=false -input=false

# Generate diagram using Inframap from tfstate with provider-specific visualization
# Official docs: inframap generate state.tfstate | dot -Tpng > graph.png
# Using --clean=false to show all nodes including unconnected ones (with icons)
TF_STATE_FILE="$TF_DIR/terraform.tfstate"
if [ -f "$TF_STATE_FILE" ]; then
  if "$INFRAMAP_BIN" generate "$TF_STATE_FILE" --clean=false > "$DOT_OUT"; then
    echo "Generated DOT from TFState with icons: $DOT_OUT"
  else
    echo "Error: Failed to generate diagram from tfstate." >&2
    exit 1
  fi
else
  echo "Error: No terraform.tfstate found at $TF_STATE_FILE. Please run 'terraform apply' first." >&2
  echo "  Alternative: Use 'inframap generate <directory>' for HCL files (requires module init)" >&2
  exit 1
fi

if [ -n "$DOT_BIN" ]; then
  "$DOT_BIN" -Tsvg "$DOT_OUT" -o "$SVG_OUT"
  "$DOT_BIN" -Tpng "$DOT_OUT" -o "$PNG_OUT"
  echo "Rendered SVG: $SVG_OUT"
  echo "Rendered PNG: $PNG_OUT"
else
  echo "Warning: Graphviz 'dot' not found. SVG/PNG not generated." >&2
fi
