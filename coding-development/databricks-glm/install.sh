#!/usr/bin/env bash
# Install Databricks GLM package for Grok, Claude Code, Codex, OpenCode, Cursor, agents.
# Usage: ./install.sh [--auto-start] [--skip-grok-config] [--skip-hooks]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_START=0
SKIP_GROK_CONFIG=0
SKIP_HOOKS=0
for arg in "$@"; do
  case "$arg" in
    --auto-start) AUTO_START=1 ;;
    --skip-grok-config) SKIP_GROK_CONFIG=1 ;;
    --skip-hooks) SKIP_HOOKS=1 ;;
  esac
done

echo "=== Databricks GLM install ==="

PROXY_DIR="${HOME}/.grok/proxies"
mkdir -p "$PROXY_DIR"
cp -f "$ROOT/scripts/databricks_glm_proxy.py" "$PROXY_DIR/"
cp -f "$ROOT/scripts/ensure-proxy.sh" "$PROXY_DIR/"
cp -f "$ROOT/scripts/start-proxy.sh" "$PROXY_DIR/"
chmod +x "$PROXY_DIR/ensure-proxy.sh" "$PROXY_DIR/start-proxy.sh"
echo "  proxy -> $PROXY_DIR"

copy_skill() {
  local dest="$1"
  mkdir -p "$dest/scripts" "$dest/configs"
  cp -f "$ROOT/SKILL.md" "$ROOT/AGENTS.md" "$ROOT/CLAUDE.md" "$ROOT/README.md" "$dest/"
  cp -f "$ROOT/scripts/"* "$dest/scripts/" 2>/dev/null || true
  cp -f "$ROOT/configs/"* "$dest/configs/" 2>/dev/null || true
  chmod +x "$dest/scripts/"*.sh 2>/dev/null || true
  echo "  skill -> $dest"
}

for d in \
  "${HOME}/.grok/skills/glm" \
  "${HOME}/.claude/skills/glm" \
  "${HOME}/.agents/skills/glm" \
  "${HOME}/.codex/skills/glm" \
  "${HOME}/.config/opencode/skills/glm" \
  "${HOME}/.cursor/skills/glm" \
  "${HOME}/.windsurf/skills/glm"
do
  copy_skill "$d"
done

mkdir -p "${HOME}/.grok/commands"
cat > "${HOME}/.grok/commands/glm.md" <<'EOF'
---
description: Start/check Databricks GLM proxy and switch to databricks-glm
---

Run the **glm** skill. Ensure `DATABRICKS_TOKEN`, start proxy via
`~/.grok/proxies/ensure-proxy.sh` if port 8787 is down, then `/model databricks-glm`.
EOF
echo "  slash -> ~/.grok/commands/glm.md"

upsert_rules() {
  local path="$1"
  local marker="$2"
  local body_file="$3"
  mkdir -p "$(dirname "$path")"
  local start="<!-- BEGIN ${marker} -->"
  local end="<!-- END ${marker} -->"
  local block
  block=$(printf '%s\n%s\n%s\n' "$start" "$(cat "$body_file")" "$end")
  if [[ -f "$path" ]] && grep -qF "$start" "$path"; then
    # replace existing block with python for portability
    python3 - "$path" "$start" "$end" "$body_file" <<'PY'
import sys
from pathlib import Path
path, start, end, body_file = sys.argv[1:5]
text = Path(path).read_text(encoding="utf-8")
body = Path(body_file).read_text(encoding="utf-8")
block = f"{start}\n{body.rstrip()}\n{end}"
s, e = text.find(start), text.find(end)
if s >= 0 and e >= 0:
    text = text[:s] + block + text[e + len(end):]
else:
    text = text.rstrip() + "\n\n" + block + "\n"
Path(path).write_text(text, encoding="utf-8")
PY
  elif [[ -f "$path" ]]; then
    printf '\n\n%s\n' "$block" >> "$path"
  else
    printf '%s\n' "$block" > "$path"
  fi
  echo "  rules -> $path"
}

upsert_rules "${HOME}/.grok/AGENTS.md" "DATABRICKS-GLM" "$ROOT/AGENTS.md"
upsert_rules "${HOME}/.grok/CLAUDE.md" "DATABRICKS-GLM" "$ROOT/CLAUDE.md"
upsert_rules "${HOME}/AGENTS.md" "DATABRICKS-GLM" "$ROOT/AGENTS.md"
upsert_rules "${HOME}/CLAUDE.md" "DATABRICKS-GLM" "$ROOT/CLAUDE.md"
upsert_rules "${HOME}/.claude/CLAUDE.md" "DATABRICKS-GLM" "$ROOT/CLAUDE.md"

mkdir -p "${HOME}/.grok/memory"
MEM="${HOME}/.grok/memory/MEMORY.md"
if [[ ! -f "$MEM" ]]; then
  cat > "$MEM" <<'EOF'
# Global memory

## Models / Databricks GLM

- Grok model id: `databricks-glm` (API: `system.ai.glm-5-2`).
- Local proxy `http://127.0.0.1:8787` required for tool calls.
- Scripts: `~/.grok/proxies/`; skill `/glm`.
- Auth: env `DATABRICKS_TOKEN` only.
EOF
elif ! grep -q "Databricks GLM" "$MEM"; then
  cat >> "$MEM" <<'EOF'

## Models / Databricks GLM

- Grok model id: `databricks-glm` (API: `system.ai.glm-5-2`).
- Local proxy `http://127.0.0.1:8787` required for tool calls.
- Scripts: `~/.grok/proxies/`; skill `/glm`.
- Auth: env `DATABRICKS_TOKEN` only.
EOF
fi
echo "  memory -> $MEM"

if [[ "$SKIP_GROK_CONFIG" -eq 0 ]]; then
  CFG="${HOME}/.grok/config.toml"
  mkdir -p "$(dirname "$CFG")"
  if [[ ! -f "$CFG" ]]; then
    cp "$ROOT/configs/grok.model.toml.snippet" "$CFG"
    echo "  config created"
  elif ! grep -q '\[model.databricks-glm\]' "$CFG"; then
    printf '\n' >> "$CFG"
    cat "$ROOT/configs/grok.model.toml.snippet" >> "$CFG"
    echo "  config appended"
  else
    echo "  config already has model (left unchanged)"
  fi
  if ! grep -q '\[memory\]' "$CFG" 2>/dev/null; then
    printf '\n[memory]\nenabled = true\n' >> "$CFG"
  fi
fi

if [[ "$SKIP_HOOKS" -eq 0 ]]; then
  mkdir -p "${HOME}/.grok/hooks"
  cat > "${HOME}/.grok/hooks/databricks-glm-session-start.json" <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${HOME}/.grok/proxies/ensure-proxy.sh"
          }
        ]
      }
    ]
  }
}
EOF
  echo "  hook -> SessionStart ensure-proxy"
fi

if [[ "$AUTO_START" -eq 1 ]]; then
  mkdir -p "${HOME}/.config/systemd/user"
  cat > "${HOME}/.config/systemd/user/databricks-glm-proxy.service" <<EOF
[Unit]
Description=Databricks GLM local patch proxy
After=network.target

[Service]
Type=simple
Environment=DATABRICKS_TOKEN=%h/.config/databricks-token-placeholder
# Prefer user environment; override with EnvironmentFile=
EnvironmentFile=-%h/.config/databricks-glm.env
ExecStart=/usr/bin/env python3 %h/.grok/proxies/databricks_glm_proxy.py
Restart=on-failure

[Install]
WantedBy=default.target
EOF
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
    systemctl --user enable --now databricks-glm-proxy.service || true
    echo "  autostart -> systemd user unit (set DATABRICKS_TOKEN in ~/.config/databricks-glm.env)"
  else
    echo "  autostart unit written; systemctl not available"
  fi
  bash "$PROXY_DIR/ensure-proxy.sh" || true
else
  echo "  autostart skipped (pass --auto-start)"
fi

echo ""
echo "Done. Set DATABRICKS_TOKEN, run /glm or ensure-proxy.sh, Grok: /model databricks-glm"
echo "Restart agent sessions so skills/hooks reload."
