# Databricks GLM proxy + `/glm` skill

Cross-agent package so **Claude Code, Codex, OpenCode, Grok, Cursor**, and other SKILL.md-compatible tools can use **Databricks-hosted GLM-5-2** with **full tool calling**.

Part of **[Custom Instruction Bazaar](https://github.com/Drvivek34/Custom-Instruction-Bazaar)** / **[Skill Bazaar](https://github.com/Drvivek34/Skill-Bazaar)** Â· [Mega AI Bazaar](https://drvivek34.github.io/Mega-AI-Bazaar/)

## Problem

Databricks AI Gateway OpenAI-compatible streams sometimes omit `"model"` on SSE chunks (especially `tool_calls`). Strict clients (Grok Build) fail:

```text
serialization error: missing field `model`
```

## Solution

1. Tiny local proxy on `127.0.0.1:8787` that injects `"model"` when missing.
2. Portable **`/glm`** skill + **AGENTS.md** / **CLAUDE.md**.
3. **Install script** copies skill into every common agent skill path and can enable **auto-start**.

## One-time install

### Windows (PowerShell)

```powershell
# From this folder:
.\install.ps1
# Options:
#   .\install.ps1 -AutoStart          # logon scheduled task
#   .\install.ps1 -SkipGrokConfig     # don't patch ~/.grok/config.toml
```

Requires:

- Python 3.10+
- Env var **`DATABRICKS_TOKEN`** (Databricks PAT)
- Optional: `DATABRICKS_UPSTREAM` (default is AI Gateway MLflow `/v1` URL)

### macOS / Linux

```bash
chmod +x install.sh scripts/*.sh
./install.sh --auto-start   # optional user systemd unit
```

## Daily use

```text
/glm          # ensure proxy + switch instructions
/glm status
/glm stop
```

Grok: `/model databricks-glm`  
Other agents: `base_url=http://127.0.0.1:8787`, model `system.ai.glm-5-2`

## Automatic modes

| Mode | What |
|------|------|
| **`/glm` skill** | Agent starts proxy if down (all agents that load SKILL.md) |
| **Grok SessionStart hook** | `ensure-proxy` on every Grok session |
| **`-AutoStart` install** | Windows logon task / user systemd so proxy is always up |

## Files

| File | Role |
|------|------|
| `SKILL.md` | Portable agent skill (`/glm`) |
| `AGENTS.md` | Global agent rules fragment |
| `CLAUDE.md` | Claude / multi-agent instructions |
| `scripts/databricks_glm_proxy.py` | Proxy |
| `scripts/ensure-proxy.ps1` / `.sh` | Idempotent start |
| `scripts/start-proxy.ps1` | Foreground start helper |
| `install.ps1` / `install.sh` | Multi-agent install + optional auto-start |
| `configs/grok.model.toml.snippet` | Grok `[model.databricks-glm]` example |

## Security

- Never commit tokens.
- Proxy binds **localhost only** by default.
- Upstream URL is configurable; review before production use.

## License

MIT (same as Mega AI Bazaar collections unless noted).

## Change config (/glm change)

`powershell
# Interactive prompts (token, upstream URL, model, port):
powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\.grok\proxies\change-config.ps1

# Or in any agent: /glm change  (agent asks you, then runs non-interactive flags)
powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\.grok\proxies\change-config.ps1 -StatusOnly
`

Settings are saved to `~/.grok/proxies/glm.env` (gitignored / never commit tokens).
