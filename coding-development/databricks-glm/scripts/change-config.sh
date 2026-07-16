#!/usr/bin/env bash
# Interactive or env-flag config for Databricks GLM.
# Usage:
#   ./change-config.sh
#   DATABRICKS_TOKEN=... DATABRICKS_UPSTREAM=... ./change-config.sh --non-interactive --restart
set -euo pipefail

PROXY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${PROXY_DIR}/glm.env"
CONFIG_TOML="${HOME}/.grok/config.toml"
NON_INTERACTIVE=0
RESTART=1
SET_USER_PROFILE=0

for arg in "$@"; do
  case "$arg" in
    --non-interactive|-y) NON_INTERACTIVE=1 ;;
    --restart) RESTART=1 ;;
    --no-restart) RESTART=0 ;;
    --set-profile) SET_USER_PROFILE=1 ;;
  esac
done

mask() {
  local s="${1:-}"
  if [[ -z "$s" ]]; then echo "(empty)"; return; fi
  local n=${#s}
  if (( n <= 8 )); then printf '%*s' "$n" '' | tr ' ' '*'; echo " (len=$n)"; return; fi
  echo "${s:0:4}...${s: -4} (len=$n)"
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

prompt_keep() {
  local label="$1" current="$2" secret="${3:-0}"
  local disp
  if [[ "$secret" == "1" ]]; then disp="$(mask "$current")"; else disp="${current:-(empty)}"; fi
  echo ""
  echo "$label"
  echo "  current: $disp"
  echo "  enter new value, Enter=keep, '-'=clear:"
  local raw
  read -r -p "  > " raw || true
  if [[ -z "${raw}" ]]; then echo "$current"; return; fi
  if [[ "$raw" == "-" ]]; then echo ""; return; fi
  echo "$raw"
}

load_env

TOKEN="${DATABRICKS_TOKEN:-}"
UPSTREAM="${DATABRICKS_UPSTREAM:-https://dbc-3bbcd3f6-452e.cloud.databricks.com/ai-gateway/mlflow/v1}"
MODEL="${DATABRICKS_DEFAULT_MODEL:-system.ai.glm-5-2}"
PHOST="${PROXY_HOST:-127.0.0.1}"
PPORT="${PROXY_PORT:-8787}"
GROK_URL="${GROK_LOCAL_BASE_URL:-http://${PHOST}:${PPORT}}"

echo "=== /glm change — Databricks GLM config ==="
echo "Config file: $ENV_FILE"

if [[ "$NON_INTERACTIVE" -eq 0 ]]; then
  TOKEN="$(prompt_keep "1) Access token (DATABRICKS_TOKEN)" "$TOKEN" 1)"
  UPSTREAM="$(prompt_keep "2) Upstream base URL" "$UPSTREAM" 0)"
  MODEL="$(prompt_keep "3) API model id" "$MODEL" 0)"
  PHOST="$(prompt_keep "4) Local proxy host" "$PHOST" 0)"
  PPORT="$(prompt_keep "5) Local proxy port" "$PPORT" 0)"
  GROK_URL="$(prompt_keep "6) Grok base_url (local proxy)" "${GROK_URL:-http://${PHOST}:${PPORT}}" 0)"
fi

UPSTREAM="${UPSTREAM%/}"
GROK_URL="${GROK_URL:-http://${PHOST}:${PPORT}}"
GROK_URL="${GROK_URL%/}"

cat > "$ENV_FILE" <<EOF
# Databricks GLM proxy config — DO NOT COMMIT
# Updated $(date -Iseconds 2>/dev/null || date)
DATABRICKS_TOKEN=${TOKEN}
DATABRICKS_UPSTREAM=${UPSTREAM}
DATABRICKS_DEFAULT_MODEL=${MODEL}
PROXY_HOST=${PHOST}
PROXY_PORT=${PPORT}
GROK_LOCAL_BASE_URL=${GROK_URL}
EOF
chmod 600 "$ENV_FILE" 2>/dev/null || true

export DATABRICKS_TOKEN="$TOKEN"
export DATABRICKS_UPSTREAM="$UPSTREAM"
export DATABRICKS_DEFAULT_MODEL="$MODEL"
export PROXY_HOST="$PHOST"
export PROXY_PORT="$PPORT"

echo ""
echo "Saved $ENV_FILE"
echo "  token:    $(mask "$TOKEN")"
echo "  upstream: $UPSTREAM"
echo "  model:    $MODEL"
echo "  proxy:    ${PHOST}:${PPORT}"
echo "  grok url: $GROK_URL"

if [[ "$SET_USER_PROFILE" -eq 1 ]]; then
  for f in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
    [[ -f "$f" ]] || continue
    if ! grep -q 'glm.env' "$f" 2>/dev/null; then
      echo "[ -f \"\$HOME/.grok/proxies/glm.env\" ] && set -a && . \"\$HOME/.grok/proxies/glm.env\" && set +a" >> "$f"
      echo "  hooked $f to source glm.env"
    fi
  done
fi

if [[ -f "$CONFIG_TOML" ]] && grep -q '\[model.databricks-glm\]' "$CONFIG_TOML"; then
  python3 - "$CONFIG_TOML" "$MODEL" "$GROK_URL" <<'PY'
import sys
from pathlib import Path
path, model, base = sys.argv[1:4]
lines = Path(path).read_text(encoding="utf-8").splitlines()
out, in_sec = [], False
for line in lines:
    if line.strip() == "[model.databricks-glm]":
        in_sec = True
        out.append(line)
        continue
    if in_sec and line.strip().startswith("["):
        in_sec = False
    if in_sec:
        if line.strip().startswith("model " ) or line.strip().startswith("model="):
            out.append(f'model = "{model}"')
            continue
        if line.strip().startswith("base_url"):
            out.append(f'base_url = "{base}"')
            continue
    out.append(line)
Path(path).write_text("\n".join(out) + "\n", encoding="utf-8")
print(f"Updated {path}")
PY
fi

if [[ "$RESTART" -eq 1 ]]; then
  if command -v lsof >/dev/null 2>&1; then
    pids=$(lsof -tiTCP:"$PPORT" -sTCP:LISTEN 2>/dev/null || true)
    if [[ -n "${pids}" ]]; then kill $pids 2>/dev/null || true; fi
  fi
  sleep 0.5
  bash "${PROXY_DIR}/ensure-proxy.sh" || true
fi

echo "Done. Grok: /model databricks-glm"
