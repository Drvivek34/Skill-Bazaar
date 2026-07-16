---
name: glm
description: >
  Start/check/change Databricks GLM-5-2 local patch proxy and switch agents to
  databricks-glm. Use when user says /glm, /glm change, /glm config, "use glm",
  "start glm", "databricks glm", "glm proxy", "change glm token", "glm base url",
  "switch to glm", or hits serialization error missing field `model` with GLM.
user-invocable: true
argument-hint: "[start|status|stop|switch|change|config|install]"
metadata:
  short-description: "GLM proxy: start/status/change token & URL"
  author: Drvivek34
  platforms: "Grok, Claude Code, Codex, OpenCode, Cursor, Windsurf, agents"
---

# Databricks GLM (`/glm`)

Make coding agents use **Databricks-hosted GLM** with **full tool calling** via a local patch proxy.

## Why a proxy

Databricks SSE often omits `"model"` on **tool_calls** chunks. Strict clients fail with `serialization error: missing field model`. Proxy on `127.0.0.1:8787` injects `model`.

## Paths

| Item | Path |
|------|------|
| Proxy | `~/.grok/proxies/databricks_glm_proxy.py` |
| Durable config | `~/.grok/proxies/glm.env` (tokens — **never commit**) |
| Ensure | `~/.grok/proxies/ensure-proxy.ps1` / `ensure-proxy.sh` |
| **Change config** | `~/.grok/proxies/change-config.ps1` / `change-config.sh` |
| Grok model id | `databricks-glm` |
| Auth | `DATABRICKS_TOKEN` + `glm.env` |

---

## Arguments

| Arg | Action |
|-----|--------|
| (none) / `start` | Ensure proxy + remind `/model databricks-glm` |
| `status` | Show masked token, upstream, model, port, listening? |
| `stop` | Kill listener on proxy port (confirm first) |
| `switch` | Remind model switch only |
| **`change` / `config`** | **Interactive: ask user for token, URLs, model; save + restart proxy** |
| `install` | Re-run package install |

---

## `/glm change` (or `/glm config`) — REQUIRED FLOW

When user runs **`/glm change`**, **`/glm config`**, or asks to change token / base URL / model:

### A. Collect settings (ask the user — do not invent secrets)

Ask **one field at a time** (chat or structured questions). Show **current** values first via status (mask token).

1. **Access token** (`DATABRICKS_TOKEN`) — Databricks PAT / bearer. User may say "keep" to leave unchanged.
2. **Upstream base URL** (`DATABRICKS_UPSTREAM`) — Databricks OpenAI-compatible root, e.g. `https://dbc-XXXX.cloud.databricks.com/ai-gateway/mlflow/v1` (no `/chat/completions` suffix).
3. **API model id** (`DATABRICKS_DEFAULT_MODEL`) — e.g. `system.ai.glm-5-2` (sent as JSON `"model"`).
4. **Local proxy host** (default `127.0.0.1`).
5. **Local proxy port** (default `8787`).
6. **Grok local base_url** (default `http://127.0.0.1:8787` — must point at **proxy**, not Databricks direct).
7. **Persist to User env?** Yes/No (Windows User env / shell profile).

If user only wants one field changed, only ask that field; pass only those flags to the script.

### B. Apply (Windows)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $env:USERPROFILE\.grok\proxies\change-config.ps1 `
  -NonInteractive -RestartProxy -SetUserEnv `
  -Token "<from user or omit to keep>" `
  -Upstream "<url>" `
  -ApiModel "<model id>" `
  -ProxyHost "127.0.0.1" `
  -ProxyPort "8787" `
  -GrokLocalBaseUrl "http://127.0.0.1:8787"
```

**Rules for flags:**

- Only pass `-Token` if user provided a **new** token (never log full token).
- If user said keep token: omit `-Token` entirely.
- Always pass fields they changed.
- Prefer `-SetUserEnv` when user wants persistence across terminals.
- Always `-RestartProxy` after URL/token change so proxy reloads `glm.env`.

Status only:

```powershell
powershell -NoProfile -File $env:USERPROFILE\.grok\proxies\change-config.ps1 -StatusOnly
```

Interactive terminal (user runs themselves):

```powershell
powershell -NoProfile -File $env:USERPROFILE\.grok\proxies\change-config.ps1
```

### C. Apply (Unix)

```bash
# Interactive:
bash ~/.grok/proxies/change-config.sh

# Or export vars then:
DATABRICKS_TOKEN='...' DATABRICKS_UPSTREAM='...' DATABRICKS_DEFAULT_MODEL='...' \
  bash ~/.grok/proxies/change-config.sh --non-interactive --restart --set-profile
```

### D. After change

1. Confirm status (masked).
2. Tell user: Grok **`/model databricks-glm`**; **new session** if API model id changed.
3. Never write tokens into git, SKILL.md, AGENTS.md, chat logs if avoidable.

---

## `/glm start` / default

1. Status / token check (`change-config.ps1 -StatusOnly` or env).
2. `ensure-proxy.ps1` / `ensure-proxy.sh`.
3. `/model databricks-glm`.

## `/glm status`

```powershell
powershell -NoProfile -File $env:USERPROFILE\.grok\proxies\change-config.ps1 -StatusOnly
```

## `/glm stop`

Confirm, then kill process listening on `PROXY_PORT` (default 8787).

---

## Failures

| Symptom | Fix |
|---------|-----|
| `missing field model` | Proxy down or Grok `base_url` is Databricks direct → `/glm change` fix local base_url + start |
| 401 | Bad token → `/glm change` |
| Wrong model | `/glm change` API model id |
| Connection refused | `/glm start` |

## Do not

- Store tokens in repos.
- Point Grok `base_url` at Databricks direct for tool-heavy turns.
- Print full access tokens in replies (mask: first/last 4 chars only).
