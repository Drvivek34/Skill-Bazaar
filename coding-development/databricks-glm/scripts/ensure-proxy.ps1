# Idempotent: start Databricks GLM proxy if not already listening.
# Loads ~/.grok/proxies/glm.env first so token/upstream persist across restarts.

$ErrorActionPreference = "Stop"
$ProxyDir = $PSScriptRoot
if (-not $ProxyDir) { $ProxyDir = Join-Path $env:USERPROFILE ".grok\proxies" }
$EnvFile = Join-Path $ProxyDir "glm.env"
$ProxyPy = Join-Path $ProxyDir "databricks_glm_proxy.py"
if (-not (Test-Path $ProxyPy)) {
    $ProxyPy = Join-Path $env:USERPROFILE ".grok\proxies\databricks_glm_proxy.py"
}

# Load glm.env into process (file wins for empty process vars; process non-empty wins)
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#") -or $line -notmatch "=") { return }
        $i = $line.IndexOf("=")
        $k = $line.Substring(0, $i).Trim()
        $v = $line.Substring($i + 1).Trim().Trim('"').Trim("'")
        if (-not $k) { return }
        $existing = [Environment]::GetEnvironmentVariable($k, "Process")
        if (-not $existing) {
            Set-Item -Path "Env:$k" -Value $v
        }
    }
}

$Port = if ($env:PROXY_PORT) { [int]$env:PROXY_PORT } else { 8787 }

function Test-Listening {
    try {
        $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        return [bool]$c
    } catch {
        $line = netstat -ano | Select-String ":$Port\s+.*LISTENING"
        return [bool]$line
    }
}

if (Test-Listening) {
    Write-Output "glm-proxy: already up on port $Port"
    exit 0
}

if (-not $env:DATABRICKS_TOKEN) {
    Write-Output "glm-proxy: DATABRICKS_TOKEN not set (set env or run change-config.ps1 /glm change)"
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

$logDir = $ProxyDir
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$outLog = Join-Path $logDir "proxy.stdout.log"
$errLog = Join-Path $logDir "proxy.stderr.log"

# Start with env inherited (includes glm.env we loaded)
Start-Process -FilePath $python.Source `
    -ArgumentList "`"$ProxyPy`"" `
    -WorkingDirectory (Split-Path $ProxyPy) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog | Out-Null

for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Listening) {
        Write-Output "glm-proxy: started on port $Port"
        exit 0
    }
}

Write-Output "glm-proxy: failed to bind port $Port (see $errLog)"
if (Test-Path $errLog) {
    Get-Content $errLog -Tail 15 | ForEach-Object { Write-Output "  $_" }
}
exit 1
