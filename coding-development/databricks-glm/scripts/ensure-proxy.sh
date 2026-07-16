#!/usr/bin/env bash
# Idempotent start; sources glm.env first.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/glm.env"
PROXY_PY="${SCRIPT_DIR}/databricks_glm_proxy.py"
[[ -f "$PROXY_PY" ]] || PROXY_PY="${HOME}/.grok/proxies/databricks_glm_proxy.py"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

PORT="${PROXY_PORT:-8787}"

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
  echo "glm-proxy: DATABRICKS_TOKEN not set (run change-config.sh /glm change)"
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
