# Install Databricks GLM package for Grok, Claude Code, Codex, OpenCode, Cursor, agents.
# Usage:
#   .\install.ps1
#   .\install.ps1 -AutoStart
#   .\install.ps1 -SkipGrokConfig

param(
    [switch]$AutoStart,
    [switch]$SkipGrokConfig,
    [switch]$SkipHooks
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$HomeDir = $env:USERPROFILE

function Ensure-Dir($p) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
}

function Copy-SkillTree($destRoot) {
    Ensure-Dir $destRoot
    Ensure-Dir (Join-Path $destRoot "scripts")
    Ensure-Dir (Join-Path $destRoot "configs")
    Copy-Item (Join-Path $Root "SKILL.md") (Join-Path $destRoot "SKILL.md") -Force
    Copy-Item (Join-Path $Root "AGENTS.md") (Join-Path $destRoot "AGENTS.md") -Force
    Copy-Item (Join-Path $Root "CLAUDE.md") (Join-Path $destRoot "CLAUDE.md") -Force
    Copy-Item (Join-Path $Root "README.md") (Join-Path $destRoot "README.md") -Force
    Copy-Item (Join-Path $Root "scripts\*") (Join-Path $destRoot "scripts") -Force -Recurse
    if (Test-Path (Join-Path $Root "configs")) {
        Copy-Item (Join-Path $Root "configs\*") (Join-Path $destRoot "configs") -Force -Recurse
    }
    Write-Host "  skill -> $destRoot"
}

Write-Host "=== Databricks GLM install ==="

# 1) Shared proxy home (Grok path is the canonical runtime location)
$ProxyDir = Join-Path $HomeDir ".grok\proxies"
Ensure-Dir $ProxyDir
Copy-Item (Join-Path $Root "scripts\databricks_glm_proxy.py") (Join-Path $ProxyDir "databricks_glm_proxy.py") -Force
Copy-Item (Join-Path $Root "scripts\ensure-proxy.ps1") (Join-Path $ProxyDir "ensure-proxy.ps1") -Force
Copy-Item (Join-Path $Root "scripts\start-proxy.ps1") (Join-Path $ProxyDir "start-databricks-glm-proxy.ps1") -Force
Write-Host "  proxy -> $ProxyDir"

# 2) Skill destinations (create parent if missing so install works even if agent not installed yet)
$skillTargets = @(
    (Join-Path $HomeDir ".grok\skills\glm"),
    (Join-Path $HomeDir ".claude\skills\glm"),
    (Join-Path $HomeDir ".agents\skills\glm"),
    (Join-Path $HomeDir ".codex\skills\glm"),
    (Join-Path $HomeDir ".config\opencode\skills\glm"),
    (Join-Path $HomeDir ".cursor\skills\glm"),
    (Join-Path $HomeDir ".windsurf\skills\glm")
)
foreach ($t in $skillTargets) {
    Copy-SkillTree $t
}

# 3) Grok slash command
$cmdDir = Join-Path $HomeDir ".grok\commands"
Ensure-Dir $cmdDir
@"
---
description: Start/check Databricks GLM proxy and switch to databricks-glm
---

Run the **glm** skill. Ensure ``DATABRICKS_TOKEN``, start proxy via
``~/.grok/proxies/ensure-proxy.ps1`` if port 8787 is down, then ``/model databricks-glm``.
"@ | Set-Content -Path (Join-Path $cmdDir "glm.md") -Encoding UTF8
Write-Host "  slash -> $cmdDir\glm.md"

# 4) Global AGENTS.md / CLAUDE.md merge markers
function Upsert-RulesFile($path, $marker, $body) {
    Ensure-Dir (Split-Path $path)
    $start = "<!-- BEGIN $marker -->"
    $end = "<!-- END $marker -->"
    $block = @"
$start
$body
$end
"@
    if (Test-Path $path) {
        $text = Get-Content $path -Raw -ErrorAction SilentlyContinue
        if ($null -eq $text) { $text = "" }
        if ($text -match [regex]::Escape($start)) {
            $pattern = "(?s)" + [regex]::Escape($start) + ".*?" + [regex]::Escape($end)
            $text = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
        } else {
            $text = $text.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
        }
        Set-Content -Path $path -Value $text -Encoding UTF8 -NoNewline
    } else {
        Set-Content -Path $path -Value ($block + "`r`n") -Encoding UTF8
    }
    Write-Host "  rules -> $path"
}

$agentsBody = Get-Content (Join-Path $Root "AGENTS.md") -Raw
$claudeBody = Get-Content (Join-Path $Root "CLAUDE.md") -Raw
Upsert-RulesFile (Join-Path $HomeDir ".grok\AGENTS.md") "DATABRICKS-GLM" $agentsBody
Upsert-RulesFile (Join-Path $HomeDir ".grok\CLAUDE.md") "DATABRICKS-GLM" $claudeBody
Upsert-RulesFile (Join-Path $HomeDir "AGENTS.md") "DATABRICKS-GLM" $agentsBody
Upsert-RulesFile (Join-Path $HomeDir "CLAUDE.md") "DATABRICKS-GLM" $claudeBody
Upsert-RulesFile (Join-Path $HomeDir ".claude\CLAUDE.md") "DATABRICKS-GLM" $claudeBody

# 5) Memory
$memDir = Join-Path $HomeDir ".grok\memory"
Ensure-Dir $memDir
$memPath = Join-Path $memDir "MEMORY.md"
$memBlock = @"
## Models / Databricks GLM

- Grok model id: ``databricks-glm`` (API: ``system.ai.glm-5-2``).
- Local proxy ``http://127.0.0.1:8787`` required for tool calls (Databricks omits ``model`` on tool_calls stream chunks).
- Scripts: ``~/.grok/proxies/``; skill ``/glm``; ensure with ``ensure-proxy.ps1``.
- Auth: env ``DATABRICKS_TOKEN`` only.
"@
if (-not (Test-Path $memPath)) {
    Set-Content $memPath ("# Global memory`r`n`r`n" + $memBlock) -Encoding UTF8
} elseif ((Get-Content $memPath -Raw) -notmatch "Databricks GLM") {
    Add-Content $memPath ("`r`n" + $memBlock)
}
Write-Host "  memory -> $memPath"

# 6) Grok config snippet
if (-not $SkipGrokConfig) {
    $cfg = Join-Path $HomeDir ".grok\config.toml"
    Ensure-Dir (Split-Path $cfg)
    $snippet = Get-Content (Join-Path $Root "configs\grok.model.toml.snippet") -Raw
    if (-not (Test-Path $cfg)) {
        Set-Content $cfg $snippet -Encoding UTF8
        Write-Host "  config created $cfg"
    } elseif ((Get-Content $cfg -Raw) -notmatch "\[model\.databricks-glm\]") {
        Add-Content $cfg ("`r`n" + $snippet)
        Write-Host "  config appended [model.databricks-glm]"
    } else {
        Write-Host "  config already has [model.databricks-glm] (left unchanged)"
    }
    # enable memory if missing
    $cfgText = Get-Content $cfg -Raw
    if ($cfgText -notmatch "\[memory\]") {
        Add-Content $cfg "`r`n[memory]`r`nenabled = true`r`n"
        Write-Host "  config enabled [memory]"
    }
}

# 7) Grok SessionStart hook (automatic ensure-proxy)
if (-not $SkipHooks) {
    $hooksDir = Join-Path $HomeDir ".grok\hooks"
    Ensure-Dir $hooksDir
    $ensure = (Join-Path $ProxyDir "ensure-proxy.ps1") -replace '\\', '\\'
    $hook = @{
        hooks = @{
            SessionStart = @(
                @{
                    hooks = @(
                        @{
                            type = "command"
                            command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$HomeDir\.grok\proxies\ensure-proxy.ps1`""
                        }
                    )
                }
            )
        }
    } | ConvertTo-Json -Depth 8
    Set-Content -Path (Join-Path $hooksDir "databricks-glm-session-start.json") -Value $hook -Encoding UTF8
    Write-Host "  hook -> SessionStart ensure-proxy"
}

# 8) Optional Windows logon auto-start
if ($AutoStart) {
    $taskName = "DatabricksGlmProxy"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HomeDir\.grok\proxies\ensure-proxy.ps1`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host "  autostart -> scheduled task '$taskName' at logon"
    # start now
    & (Join-Path $ProxyDir "ensure-proxy.ps1")
} else {
    Write-Host "  autostart skipped (re-run with -AutoStart for logon task)"
}

Write-Host ""
Write-Host "Done. Next:"
Write-Host "  1. Set env DATABRICKS_TOKEN (user or system)"
Write-Host "  2. /glm   or   powershell -File $ProxyDir\ensure-proxy.ps1"
Write-Host "  3. Grok: /model databricks-glm"
Write-Host "Restart agent sessions so skills/hooks reload."
