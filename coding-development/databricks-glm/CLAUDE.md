# Databricks GLM + coding agents

## Quick facts

| | |
|--|--|
| Grok model id | `databricks-glm` |
| API model | `system.ai.glm-5-2` |
| Proxy | `http://127.0.0.1:8787` |
| Auth | env `DATABRICKS_TOKEN` only |
| Slash / skill | `/glm` → `SKILL.md` in this package |

## Auto setup

After `install.ps1` / `install.sh`:

- Skill installed into Claude Code, Grok, Codex/agents, OpenCode, Cursor paths when present.
- Proxy scripts under `~/.grok/proxies/`.
- Optional logon auto-start (Windows scheduled task / user systemd).
- Grok `SessionStart` hook runs `ensure-proxy` so proxy comes up with each session.

## Why

Databricks AI Gateway tool-call stream chunks sometimes omit JSON field `model`. Grok errors: `serialization error: missing field model`. Proxy injects the field.

## Agent behavior

On `/glm` or "use glm": check token → ensure proxy → instruct model switch. Never write secrets into repo files.
