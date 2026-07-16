#!/usr/bin/env bash
# Foreground proxy (for debugging). Prefer ensure-proxy.sh for auto-start.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${DATABRICKS_TOKEN:-}" ]]; then
  echo "Set DATABRICKS_TOKEN first" >&2
  exit 1
fi
exec python3 "${SCRIPT_DIR}/databricks_glm_proxy.py"
