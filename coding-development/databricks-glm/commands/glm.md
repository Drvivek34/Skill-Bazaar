---
description: Start/check Databricks GLM proxy and switch to databricks-glm (full tools)
argument-hint: "[start|status|stop|switch|install]"
---

# /glm

Run the **glm** skill from this package (or `~/.grok/skills/glm/SKILL.md`).

1. Check `DATABRICKS_TOKEN`.
2. Ensure proxy: `~/.grok/proxies/ensure-proxy.ps1` (Windows) or `ensure-proxy.sh` (Unix).
3. Grok: `/model databricks-glm`. Others: base_url `http://127.0.0.1:8787`, model `system.ai.glm-5-2`.

Without the proxy, tool turns fail with `serialization error: missing field model`.
