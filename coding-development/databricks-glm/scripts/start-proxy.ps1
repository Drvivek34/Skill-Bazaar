# Start the Databricks GLM patch proxy (required for Grok + tool calls).
# Usage: powershell -File $env:USERPROFILE\.grok\proxies\start-databricks-glm-proxy.ps1

$ErrorActionPreference = "Stop"
$proxy = Join-Path $PSScriptRoot "databricks_glm_proxy.py"
$port = if ($env:PROXY_PORT) { [int]$env:PROXY_PORT } else { 8787 }

if (-not $env:DATABRICKS_TOKEN) {
    Write-Error "DATABRICKS_TOKEN is not set. Set it first, then re-run."
}

# Already listening?
$existing = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Proxy already listening on port $port (PID $($existing.OwningProcess))."
    exit 0
}

Write-Host "Starting Databricks GLM proxy on 127.0.0.1:$port ..."
Write-Host "Keep this window open while using /model databricks-glm in Grok."
python $proxy
