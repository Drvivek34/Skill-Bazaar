# Idempotent: start Databricks GLM proxy if not already listening.
# Safe to call from SessionStart hooks and /glm skill.

$ErrorActionPreference = "Stop"
$Port = if ($env:PROXY_PORT) { [int]$env:PROXY_PORT } else { 8787 }
$ProxyPy = Join-Path $PSScriptRoot "databricks_glm_proxy.py"
if (-not (Test-Path $ProxyPy)) {
    $ProxyPy = Join-Path $env:USERPROFILE ".grok\proxies\databricks_glm_proxy.py"
}

function Test-Listening {
    try {
        $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        return [bool]$c
    } catch {
        # Fallback for older shells
        $line = netstat -ano | Select-String ":$Port\s+.*LISTENING"
        return [bool]$line
    }
}

if (Test-Listening) {
    Write-Output "glm-proxy: already up on port $Port"
    exit 0
}

if (-not $env:DATABRICKS_TOKEN) {
    Write-Output "glm-proxy: DATABRICKS_TOKEN not set; not starting"
    exit 2
}

if (-not (Test-Path $ProxyPy)) {
    Write-Output "glm-proxy: missing $ProxyPy"
    exit 3
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Output "glm-proxy: python not on PATH"
    exit 4
}

$logDir = Join-Path $env:USERPROFILE ".grok\proxies"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$outLog = Join-Path $logDir "proxy.stdout.log"
$errLog = Join-Path $logDir "proxy.stderr.log"

Start-Process -FilePath $python.Source `
    -ArgumentList "`"$ProxyPy`"" `
    -WorkingDirectory (Split-Path $ProxyPy) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog | Out-Null

Start-Sleep -Milliseconds 800
if (Test-Listening) {
    Write-Output "glm-proxy: started on port $Port"
    exit 0
}

Write-Output "glm-proxy: failed to bind port $Port (see $errLog)"
exit 1
