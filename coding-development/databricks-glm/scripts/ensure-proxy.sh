#!/usr/bin/env bash
# Idempotent: start Databricks GLM proxy if not already listening.
set -euo pipefail

PORT="${PROXY_PORT:-8787}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_PY="${SCRIPT_DIR}/databricks_glm_proxy.py"
if [[ ! -f "$PROXY_PY" ]]; then
  PROXY_PY="${HOME}/.grok/proxies/databricks_glm_proxy.py"
fi

listening() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -q ":${PORT} "
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1
  else
    netstat -an 2>/dev/null | grep -E "[:.]${PORT} .*LISTEN" >/dev/null
  fi
}

if listening; then
  echo "glm-proxy: already up on port ${PORT}"
  exit 0
fi

if [[ -z "${DATABRICKS_TOKEN:-}" ]]; then
  echo "glm-proxy: DATABRICKS_TOKEN not set; not starting"
  exit 2
fi

if [[ ! -f "$PROXY_PY" ]]; then
  echo "glm-proxy: missing ${PROXY_PY}"
  exit 3
fi

LOG_DIR="${HOME}/.grok/proxies"
mkdir -p "$LOG_DIR"
nohup python3 "$PROXY_PY" >>"${LOG_DIR}/proxy.stdout.log" 2>>"${LOG_DIR}/proxy.stderr.log" &
sleep 0.8

if listening; then
  echo "glm-proxy: started on port ${PORT}"
  exit 0
fi

echo "glm-proxy: failed to bind port ${PORT}"
exit 1
