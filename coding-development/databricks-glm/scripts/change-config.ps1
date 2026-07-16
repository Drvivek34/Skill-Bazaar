# Interactive or flagged config update for Databricks GLM proxy + Grok model.
#
# Interactive:
#   powershell -ExecutionPolicy Bypass -File change-config.ps1
#
# Non-interactive (agent after collecting answers):
#   powershell -ExecutionPolicy Bypass -File change-config.ps1 -NonInteractive -RestartProxy -SetUserEnv `
#     -Token "dapi..." -Upstream "https://.../v1" -ApiModel "system.ai.glm-5-2"
#
# Never prints full token. Writes ~/.grok/proxies/glm.env

param(
    [string]$Token,
    [string]$Upstream,
    [string]$ApiModel,
    [string]$ProxyHost,
    [string]$ProxyPort,
    [string]$GrokLocalBaseUrl,
    [switch]$SetUserEnv,
    [switch]$NonInteractive,
    [switch]$RestartProxy,
    [switch]$SkipRestart,
    [switch]$StatusOnly
)

$ErrorActionPreference = "Stop"
$ProxyDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ProxyDir) { $ProxyDir = Join-Path $env:USERPROFILE ".grok\proxies" }
$EnvFile = Join-Path $ProxyDir "glm.env"
$ConfigToml = Join-Path $env:USERPROFILE ".grok\config.toml"

function Read-EnvFile([string]$path) {
    $map = [ordered]@{}
    if (-not (Test-Path $path)) { return $map }
    Get-Content $path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        $i = $line.IndexOf("=")
        if ($i -lt 1) { return }
        $k = $line.Substring(0, $i).Trim()
        $v = $line.Substring($i + 1).Trim().Trim('"').Trim("'")
        $map[$k] = $v
    }
    return $map
}

function Write-EnvFile([string]$path, $map) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Databricks GLM proxy config - DO NOT COMMIT") | Out-Null
    $lines.Add("# Updated $(Get-Date -Format o)") | Out-Null
    foreach ($k in @("DATABRICKS_TOKEN","DATABRICKS_UPSTREAM","DATABRICKS_DEFAULT_MODEL","PROXY_HOST","PROXY_PORT","GROK_LOCAL_BASE_URL")) {
        if ($map.Contains($k) -and $map[$k]) {
            $lines.Add("$k=$($map[$k])") | Out-Null
        }
    }
    Set-Content -Path $path -Value $lines -Encoding UTF8
}

function Mask-Secret([string]$s) {
    if (-not $s) { return "(empty)" }
    if ($s.Length -le 8) { return (("*" * $s.Length) + " (len=$($s.Length))") }
    return ($s.Substring(0, 4) + "..." + $s.Substring($s.Length - 4) + " (len=$($s.Length))")
}

function Prompt-OrKeep([string]$label, [string]$current, [switch]$Secret) {
    $disp = if ($Secret) { Mask-Secret $current } elseif ($current) { $current } else { "(empty)" }
    Write-Host ""
    Write-Host $label
    Write-Host "  current: $disp"
    Write-Host "  new value | Enter=keep | dash(-)=clear"
    $raw = Read-Host "  >"
    if ($null -eq $raw -or $raw -eq "") { return $current }
    if ($raw -eq "-") { return "" }
    return $raw
}

$cfg = Read-EnvFile $EnvFile
if (-not $cfg["DATABRICKS_TOKEN"] -and $env:DATABRICKS_TOKEN) { $cfg["DATABRICKS_TOKEN"] = $env:DATABRICKS_TOKEN }
if (-not $cfg["DATABRICKS_UPSTREAM"]) {
    if ($env:DATABRICKS_UPSTREAM) { $cfg["DATABRICKS_UPSTREAM"] = $env:DATABRICKS_UPSTREAM }
    else { $cfg["DATABRICKS_UPSTREAM"] = "https://dbc-3bbcd3f6-452e.cloud.databricks.com/ai-gateway/mlflow/v1" }
}
if (-not $cfg["DATABRICKS_DEFAULT_MODEL"]) {
    if ($env:DATABRICKS_DEFAULT_MODEL) { $cfg["DATABRICKS_DEFAULT_MODEL"] = $env:DATABRICKS_DEFAULT_MODEL }
    else { $cfg["DATABRICKS_DEFAULT_MODEL"] = "system.ai.glm-5-2" }
}
if (-not $cfg["PROXY_HOST"]) {
    if ($env:PROXY_HOST) { $cfg["PROXY_HOST"] = $env:PROXY_HOST } else { $cfg["PROXY_HOST"] = "127.0.0.1" }
}
if (-not $cfg["PROXY_PORT"]) {
    if ($env:PROXY_PORT) { $cfg["PROXY_PORT"] = $env:PROXY_PORT } else { $cfg["PROXY_PORT"] = "8787" }
}
if (-not $cfg["GROK_LOCAL_BASE_URL"]) {
    $cfg["GROK_LOCAL_BASE_URL"] = "http://$($cfg['PROXY_HOST']):$($cfg['PROXY_PORT'])"
}

if ($StatusOnly) {
    Write-Host "=== GLM config status ==="
    $exists = if (Test-Path $EnvFile) { "(exists)" } else { "(missing)" }
    Write-Host "file:     $EnvFile $exists"
    Write-Host "token:    $(Mask-Secret $cfg['DATABRICKS_TOKEN'])"
    Write-Host "upstream: $($cfg['DATABRICKS_UPSTREAM'])"
    Write-Host "model:    $($cfg['DATABRICKS_DEFAULT_MODEL'])"
    Write-Host "proxy:    $($cfg['PROXY_HOST']):$($cfg['PROXY_PORT'])"
    Write-Host "grok url: $($cfg['GROK_LOCAL_BASE_URL'])"
    $port = [int]$cfg["PROXY_PORT"]
    $up = $false
    try { $up = [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) } catch {}
    Write-Host "listening: $up"
    exit 0
}

Write-Host "=== /glm change - Databricks GLM config ==="
Write-Host "Config file: $EnvFile"

$hasFlags = $PSBoundParameters.ContainsKey("Token") -or $PSBoundParameters.ContainsKey("Upstream") -or
    $PSBoundParameters.ContainsKey("ApiModel") -or $PSBoundParameters.ContainsKey("ProxyHost") -or
    $PSBoundParameters.ContainsKey("ProxyPort") -or $PSBoundParameters.ContainsKey("GrokLocalBaseUrl")

if (-not $NonInteractive -and -not $hasFlags) {
    Write-Host "Leave blank to keep. Enter - to clear."
    $cfg["DATABRICKS_TOKEN"] = Prompt-OrKeep "1) Access token (DATABRICKS_TOKEN / PAT)" $cfg["DATABRICKS_TOKEN"] -Secret
    $u = Prompt-OrKeep "2) Upstream base URL (Databricks OpenAI root, no /chat/completions)" $cfg["DATABRICKS_UPSTREAM"]
    $cfg["DATABRICKS_UPSTREAM"] = $u.TrimEnd("/")
    $cfg["DATABRICKS_DEFAULT_MODEL"] = Prompt-OrKeep "3) API model id (JSON model field)" $cfg["DATABRICKS_DEFAULT_MODEL"]
    $cfg["PROXY_HOST"] = Prompt-OrKeep "4) Local proxy bind host" $cfg["PROXY_HOST"]
    $cfg["PROXY_PORT"] = Prompt-OrKeep "5) Local proxy port" $cfg["PROXY_PORT"]
    if (-not $cfg["GROK_LOCAL_BASE_URL"]) {
        $cfg["GROK_LOCAL_BASE_URL"] = "http://$($cfg['PROXY_HOST']):$($cfg['PROXY_PORT'])"
    }
    $g = Prompt-OrKeep "6) Grok model base_url (local proxy URL)" $cfg["GROK_LOCAL_BASE_URL"]
    $cfg["GROK_LOCAL_BASE_URL"] = $g.TrimEnd("/")
    if (-not $PSBoundParameters.ContainsKey("SetUserEnv")) {
        $ans = Read-Host "7) Set Windows User env vars so new terminals inherit? [Y/n]"
        if ($ans -eq "" -or $ans -match '^[Yy]') { $SetUserEnv = $true }
    }
    if (-not $SkipRestart) { $RestartProxy = $true }
} else {
    if ($PSBoundParameters.ContainsKey("Token")) { $cfg["DATABRICKS_TOKEN"] = $Token }
    if ($PSBoundParameters.ContainsKey("Upstream")) { $cfg["DATABRICKS_UPSTREAM"] = $Upstream.TrimEnd("/") }
    if ($PSBoundParameters.ContainsKey("ApiModel")) { $cfg["DATABRICKS_DEFAULT_MODEL"] = $ApiModel }
    if ($PSBoundParameters.ContainsKey("ProxyHost")) { $cfg["PROXY_HOST"] = $ProxyHost }
    if ($PSBoundParameters.ContainsKey("ProxyPort")) { $cfg["PROXY_PORT"] = $ProxyPort }
    if ($PSBoundParameters.ContainsKey("GrokLocalBaseUrl")) {
        $cfg["GROK_LOCAL_BASE_URL"] = $GrokLocalBaseUrl.TrimEnd("/")
    } else {
        $cfg["GROK_LOCAL_BASE_URL"] = "http://$($cfg['PROXY_HOST']):$($cfg['PROXY_PORT'])"
    }
    if (-not $SkipRestart -and ($RestartProxy -or $NonInteractive)) { $RestartProxy = $true }
}

Write-EnvFile $EnvFile $cfg
Write-Host ""
Write-Host "Saved $EnvFile"
Write-Host "  token:    $(Mask-Secret $cfg['DATABRICKS_TOKEN'])"
Write-Host "  upstream: $($cfg['DATABRICKS_UPSTREAM'])"
Write-Host "  model:    $($cfg['DATABRICKS_DEFAULT_MODEL'])"
Write-Host "  proxy:    $($cfg['PROXY_HOST']):$($cfg['PROXY_PORT'])"
Write-Host "  grok url: $($cfg['GROK_LOCAL_BASE_URL'])"

$env:DATABRICKS_TOKEN = $cfg["DATABRICKS_TOKEN"]
$env:DATABRICKS_UPSTREAM = $cfg["DATABRICKS_UPSTREAM"]
$env:DATABRICKS_DEFAULT_MODEL = $cfg["DATABRICKS_DEFAULT_MODEL"]
$env:PROXY_HOST = $cfg["PROXY_HOST"]
$env:PROXY_PORT = $cfg["PROXY_PORT"]

if ($SetUserEnv) {
    [Environment]::SetEnvironmentVariable("DATABRICKS_TOKEN", $cfg["DATABRICKS_TOKEN"], "User")
    [Environment]::SetEnvironmentVariable("DATABRICKS_UPSTREAM", $cfg["DATABRICKS_UPSTREAM"], "User")
    [Environment]::SetEnvironmentVariable("DATABRICKS_DEFAULT_MODEL", $cfg["DATABRICKS_DEFAULT_MODEL"], "User")
    [Environment]::SetEnvironmentVariable("PROXY_PORT", $cfg["PROXY_PORT"], "User")
    Write-Host "User environment variables updated."
}

if (Test-Path $ConfigToml) {
    $apiModel = $cfg["DATABRICKS_DEFAULT_MODEL"]
    $localUrl = $cfg["GROK_LOCAL_BASE_URL"]
    $lines = Get-Content $ConfigToml
    $in = $false
    $found = $false
    $out = foreach ($line in $lines) {
        if ($line -match '^\s*\[model\.databricks-glm\]\s*$') { $in = $true; $found = $true; $line; continue }
        if ($in -and $line -match '^\s*\[') { $in = $false }
        if ($in) {
            if ($line -match '^\s*model\s*=') { "model = `"$apiModel`""; continue }
            if ($line -match '^\s*base_url\s*=') { "base_url = `"$localUrl`""; continue }
        }
        $line
    }
    if ($found) {
        Set-Content -Path $ConfigToml -Value ($out -join "`r`n") -Encoding UTF8
        Write-Host "Updated $ConfigToml model + base_url"
    } else {
        Write-Host "WARN: no [model.databricks-glm] in config.toml"
    }
}

if ($RestartProxy -and -not $SkipRestart) {
    $port = [int]$cfg["PROXY_PORT"]
    try {
        Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.OwningProcess) {
                Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
                Write-Host "Stopped old proxy PID $($_.OwningProcess)"
            }
        }
    } catch {}
    Start-Sleep -Milliseconds 500
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProxyDir "ensure-proxy.ps1")
}

Write-Host ""
Write-Host "Done. Grok: /model databricks-glm (new session if model id changed)"
exit 0
