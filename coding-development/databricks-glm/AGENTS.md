# Databricks GLM (global agent rules)

When the user wants **GLM**, **Databricks GLM**, **`/glm`**, or hits **`missing field model`** with GLM:

1. Load skill **`glm`** / run slash **`/glm`**.
2. Ensure env **`DATABRICKS_TOKEN`** is set (never commit tokens).
3. Ensure local proxy listens on **`127.0.0.1:8787`**:
   - `python ~/.grok/proxies/databricks_glm_proxy.py`
   - or `~/.grok/proxies/ensure-proxy.ps1` / `ensure-proxy.sh` (idempotent)
4. Grok: **`/model databricks-glm`**. Other agents: OpenAI-compatible base URL `http://127.0.0.1:8787`, model `system.ai.glm-5-2`.
5. **Do not** use the Databricks upstream URL as `base_url` for tool-heavy turns — stream chunks omit `model` on tool_calls and strict clients fail.
6. Tools are client-side; with proxy up, full agent tool surface works.

Install: run package `install.ps1` (Windows) or `install.sh` (macOS/Linux).
