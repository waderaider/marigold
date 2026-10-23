# CrashWatchdog.ps1 — hard-crash watchdog for the MARIGOLD UE5 demo.
#
# Called by MarigoldUpdater.ps1 (and UpdateMarigold.ps1) BEFORE the download /
# extract step, e.g.:
#     & "$PROJECT_DIR\Build\CrashWatchdog.ps1" -ProjectDir $PROJECT_DIR
#
# What it does:
#   1. Reads <ProjectDir>\Saved\Logs\MarigoldTelemetry\session.json — the heartbeat
#      file the game/editor writes at startup and every 30s while alive.
#   2. If the heartbeat is older than 5 minutes and has no clean-shutdown marker,
#      the process died without shutting down -> inferred hard crash ->
#      POSTs kind="crash-report", event="watchdog-detected" to Brio's relay.
#   3. Flushes any pending crash-*.json files the in-game crash reporter wrote to
#      disk when its own POST failed (sent as kind="crash-report",
#      event="crash-handler", then moved to sent\).
#   4. Dedups via watchdog-state.json so one dead session is reported exactly once.
#
# Rules:
#   - PowerShell 5.1 compatible (no -UseBasicParsing, no PS7-only syntax).
#   - No PII: machine_id comes from the game's own machine_id.txt (random GUID);
#     absolute paths / computer names are sanitized; credential-looking values redacted.
#   - ALWAYS exits 0 — the watchdog must NEVER fail the updater.

param(
    [string]$ProjectDir = ""
)

$ErrorActionPreference = "Continue"

$RelayUrl     = "https://nexus-log-relay.wade-relay.workers.dev/report"
$StaleMinutes = 5
$TimeOutSec   = 20

if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
    # This script lives in <ProjectDir>\Build\ -> the project root is the parent.
    $ProjectDir = Split-Path $PSScriptRoot -Parent
}

$TelemetryDir = Join-Path $ProjectDir "Saved\Logs\MarigoldTelemetry"
$SessionFile  = Join-Path $TelemetryDir "session.json"
$StateFile    = Join-Path $TelemetryDir "watchdog-state.json"
$MachineFile  = Join-Path $TelemetryDir "machine_id.txt"
$SentDir      = Join-Path $TelemetryDir "sent"
$VersionFile  = Join-Path $ProjectDir "VERSION"

# ---------------- helpers ----------------

function Get-IsoUtcNow {
    return (Get-Date).ToUniversalTime().ToString("o")
}

function Get-ProjectVersion {
    try {
        if (Test-Path $VersionFile) {
            $v = (Get-Content $VersionFile -Raw -ErrorAction Stop).Trim()
            if ($v -ne "") { return $v }
        }
    } catch { }
    return "unknown"
}

function Get-MachineId {
    # Prefer the game's own machine_id.txt (random GUID, no PII).
    try {
        if (Test-Path $MachineFile) {
            $id = (Get-Content $MachineFile -Raw -ErrorAction Stop).Trim()
            if ($id.Length -ge 8) { return $id }
        }
    } catch { }
    # Fallback: stable SHA256 hash (hostname never leaves the PC).
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($env:COMPUTERNAME + "|" + $env:USERDOMAIN)
            $hash = $sha.ComputeHash($bytes)
            return (([System.BitConverter]::ToString($hash) -replace "-", "").Substring(0, 32).ToLower())
        } finally { $sha.Dispose() }
    } catch { }
    return "unknown"
}

# Replace absolute paths / PII / secrets with placeholders.
function Sanitize-Text([string]$Text) {
    $s = [string]$Text
    try {
        if ($ProjectDir -ne "") {
            $s = [regex]::Replace($s, [regex]::Escape($ProjectDir), "<PROJECT>", "IgnoreCase")
        }
        if ($env:USERPROFILE -ne "") {
            $s = [regex]::Replace($s, [regex]::Escape($env:USERPROFILE), "<USERPROFILE>", "IgnoreCase")
        }
        if ($env:COMPUTERNAME -ne "") {
            $s = [regex]::Replace($s, [regex]::Escape($env:COMPUTERNAME), "<PC>", "IgnoreCase")
        }
        $s = [regex]::Replace($s, "(?i)(token|password|passwd|secret|api[_-]?key|bearer|access[_-]?key)[=:`""'\s]+[^\s&""']+",
                              '$1=<REDACTED>')
    } catch { }
    return $s
}

function Read-JsonFile($Path) {
    try {
        if (Test-Path $Path) {
            return (Get-Content $Path -Raw -ErrorAction Stop) | ConvertFrom-Json
        }
    } catch { }
    return $null
}

function Post-JsonBody([string]$JsonBody) {
    $body = Sanitize-Text $JsonBody
    try {
        # NOTE: no -UseBasicParsing (throws on PS 5.1); -TimeoutSec keeps us bounded.
        $resp = Invoke-RestMethod -Uri $RelayUrl -Method Post -Body $body `
            -ContentType "application/json" -TimeoutSec $TimeOutSec
        $rid = $null
        if ($resp -ne $null -and $resp.id -ne $null) { $rid = $resp.id }
        return @{ ok = $true; id = $rid }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Write-WatchdogState([string]$SessionId) {
    try {
        if (-not (Test-Path $TelemetryDir)) { New-Item -ItemType Directory -Path $TelemetryDir -Force | Out-Null }
        @{ last_reported_session = $SessionId; last_reported_utc = (Get-IsoUtcNow) } |
            ConvertTo-Json -Compress | Out-File $StateFile -Encoding utf8 -Force
    } catch { }
}

# ---------------- 1) watchdog: stale heartbeat -> inferred hard crash ----------------

$Version   = Get-ProjectVersion
$MachineId = Get-MachineId
$NowUtc    = (Get-Date).ToUniversalTime()

$Session = Read-JsonFile $SessionFile
if ($Session -ne $null) {
    $SessionId = [string]$Session.session_id
    if ([string]::IsNullOrWhiteSpace($SessionId)) { $SessionId = "unknown" }

    $HeartbeatUtc = $null
    $HbRaw = [string]$Session.last_heartbeat_utc
    if (-not [string]::IsNullOrWhiteSpace($HbRaw)) {
        try { $HeartbeatUtc = ([datetime]$HbRaw).ToUniversalTime() } catch { }
    }
    if ($HeartbeatUtc -eq $null) {
        # Unparsable heartbeat: fall back to the file's own write time.
        try { $HeartbeatUtc = (Get-Item $SessionFile -ErrorAction Stop).LastWriteTimeUtc } catch { }
    }
    $CleanShutdown = ($Session.clean_shutdown -eq $true)

    $State = Read-JsonFile $StateFile
    $AlreadyReported = ($State -ne $null -and [string]$State.last_reported_session -eq $SessionId)

    if ($HeartbeatUtc -ne $null) {
        $AgeMin = ($NowUtc - $HeartbeatUtc).TotalMinutes
        if ($AgeMin -gt $StaleMinutes -and -not $CleanShutdown -and -not $AlreadyReported) {
            $Payload = @{
                app                   = "marigold-build"
                kind                  = "crash-report"
                event                 = "watchdog-detected"
                timestamp             = (Get-IsoUtcNow)
                version               = $Version
                machine_id            = $MachineId
                session_id            = $SessionId
                detected_by           = "CrashWatchdog.ps1"
                heartbeat_age_minutes = [math]::Round($AgeMin, 1)
                note                  = "Hard crash inferred: session heartbeat is stale (> $StaleMinutes min) with no clean-shutdown marker. The game/editor process died without running its crash handler."
                heartbeat             = $Session
            }
            $r = Post-JsonBody ($Payload | ConvertTo-Json -Depth 8 -Compress)
            if ($r.ok) {
                Write-Host ("[Watchdog] Hard crash inferred for session {0} (heartbeat {1} min old) — reported (id {2})." -f $SessionId, [math]::Round($AgeMin, 1), $r.id)
                Write-WatchdogState $SessionId
            } else {
                Write-Host ("[Watchdog] Hard crash inferred for session {0} but relay POST failed: {1}" -f $SessionId, $r.error)
            }
        } else {
            Write-Host ("[Watchdog] Heartbeat OK (age {0} min, clean_shutdown={1})." -f [math]::Round($AgeMin, 1), $CleanShutdown)
        }
    } else {
        Write-Host "[Watchdog] Could not determine heartbeat time — skipping."
    }
} else {
    Write-Host "[Watchdog] No session.json heartbeat found — nothing to check."
}

# ---------------- 2) flush pending crash-*.json (in-game reporter POST failed) ----------------

try {
    $Pending = @(Get-ChildItem -Path $TelemetryDir -Filter "crash-*.json" -File -ErrorAction Stop)
} catch {
    $Pending = @()
}

foreach ($File in $Pending) {
    try {
        $Raw = Get-Content $File.FullName -Raw -ErrorAction Stop
        $r = Post-JsonBody $Raw
        if ($r.ok) {
            if (-not (Test-Path $SentDir)) { New-Item -ItemType Directory -Path $SentDir -Force | Out-Null }
            Move-Item -Path $File.FullName -Destination (Join-Path $SentDir $File.Name) -Force -ErrorAction Stop
            Write-Host ("[Watchdog] Flushed pending crash report {0}." -f $File.Name)
        } else {
            Write-Host ("[Watchdog] Could not flush {0}: {1}" -f $File.Name, $r.error)
        }
    } catch {
        Write-Host ("[Watchdog] Could not flush {0}: {1}" -f $File.Name, $_.Exception.Message)
    }
}

# Never fail the updater because the watchdog failed.
exit 0
