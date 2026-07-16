---
name: glm
description: >
  Start/check the Databricks GLM-5-2 local patch proxy and switch agents to
  use databricks-glm / system.ai.glm-5-2 so full tool calling works. Use when
  user says /glm, "use glm", "start glm", "databricks glm", "glm proxy",
  "switch to glm", or hits serialization error missing field `model` with GLM.
user-invocable: true
argument-hint: "[start|status|stop|switch|install]"
metadata:
  short-description: "Start GLM proxy + use databricks-glm with full tools"
  author: Drvivek34
  platforms: "Grok, Claude Code, Codex, OpenCode, Cursor, Windsurf, agents"
---

# Databricks GLM (`/glm`)

Make coding agents use **Databricks-hosted GLM-5-2** with **full tool calling**.

## Why a proxy

Databricks AI Gateway SSE omits `"model"` on some chunks (especially **tool_calls** finish). Strict clients (Grok) fail:

```text
serialization error: missing field `model`
```

Local proxy (`http://127.0.0.1:8787`) injects missing `model`. Plain chat may work without it; **tool turns need the proxy**.

## Paths after install

| Item | Location |
|------|----------|
| Proxy | `~/.grok/proxies/databricks_glm_proxy.py` (or package `scripts/`) |
| Ensure/start | `~/.grok/proxies/ensure-proxy.ps1` |
| Install | package `install.ps1` / `install.sh` |
| Grok model id | `databricks-glm` |
| API model | `system.ai.glm-5-2` |
| Auth | env `DATABRICKS_TOKEN` only (never commit tokens) |
| Upstream default | `DATABRICKS_UPSTREAM` or Databricks AI Gateway MLflow `/v1` |

## When invoked (`/glm` or natural language)

### 1. Token

```powershell
if ($env:DATABRICKS_TOKEN) { "TOKEN ok" } else { "TOKEN MISSING — set DATABRICKS_TOKEN" }
```

Stop and tell user to set a Databricks PAT if missing. Do not invent tokens.

### 2. Ensure proxy (automatic)

Run ensure script (idempotent — starts only if port free):

```powershell
powershell -NoProfile -File $env:USERPROFILE\.grok\proxies\ensure-proxy.ps1
```

Unix:

```bash
bash ~/.grok/proxies/ensure-proxy.sh
```

Or inline: if port **8787** not listening, start proxy in background:

```powershell
Start-Process -WindowStyle Hidden python -ArgumentList "$env:USERPROFILE\.grok\proxies\databricks_glm_proxy.py"
```

### 3. Switch model (Grok)

```text
/model databricks-glm
```

Prefer a **new session** after prior serialization failures.

Other agents: point OpenAI-compatible `base_url` at `http://127.0.0.1:8787` and model `system.ai.glm-5-2`.

### 4. Tools

With proxy up, client-side tools work (shell, files, grep, MCP, web_search client tool, subagents). Server-side backend search may stay on native models.

## Arguments

| Arg | Action |
|-----|--------|
| (none) / `start` | Ensure proxy + switch instructions |
| `status` | Token? Port 8787? base_url? |
| `stop` | Kill listener on 8787 (confirm first) |
| `switch` | Model switch only |
| `install` | Run package install for multi-agent paths + auto-start |

## Failures

| Symptom | Fix |
|---------|-----|
| `missing field model` | Proxy down or base_url still Databricks direct |
| Connection refused 8787 | `/glm start` or ensure-proxy |
| 401 | Bad/missing `DATABRICKS_TOKEN` |

## Do not

- Point agents at Databricks direct URL for tool-heavy agent loops.
- Store tokens in git, SKILL.md, AGENTS.md, or CLAUDE.md.
