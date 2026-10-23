# SendBuildLog.ps1 -- called by BuildDemo.bat after the UBT build finishes.
# Sends TWO reports to Brio's relay for auto-diagnosis:
#   kind="build-log"      -- error summary (legacy format, preserved)
#   kind="build-log-full" -- FULL build log: MSVC output, UHT output, shader
#                           compile results, warning/error counts, duration.
# Usage: SendBuildLog.ps1 <success|failed> [build_log_path] [session_id] [build_duration_sec]
#
# Rules:
#   - PowerShell 5.1 compatible (no -UseBasicParsing, no PS7-only syntax).
#   - No PII: hostname is replaced by a stable SHA256 machine_id; absolute
#     paths outside the project are sanitized to relative placeholders;
#     credential-looking tokens are redacted.
#   - ALWAYS exits 0 -- logging must NEVER fail the build.

param(
    [string]$Status = "unknown",
    [string]$BuildLogPath = "",
    [string]$SessionId = "",
    [int]$BuildDurationSec = -1
)

$RelayUrl = "https://nexus-log-relay.wade-relay.workers.dev/report"

# --- Hard size limits (protect the relay from 413s) ---
$MaxLogBytes   = 500 * 1024   # truncate the raw log text above this
$MaxBodyBytes  = 400 * 1024   # shrink tail lines until the final JSON is under this
$HeadKeep      = 60           # head lines kept when truncating
$TailKeepStart = 2000         # tail lines kept when truncating (shrinks if needed)

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $SessionId = [guid]::NewGuid().ToString()
}

$TimeStamp = (Get-Date).ToUniversalTime().ToString("o")
$ProjectRoot = Split-Path $PSScriptRoot -Parent

# ---------------- helpers ----------------

function Get-ProjectVersion {
    $verFile = Join-Path $ProjectRoot "VERSION"
    if (Test-Path $verFile) {
        try {
            $v = (Get-Content $verFile -Raw -ErrorAction Stop).Trim()
            if ($v -ne "") { return $v }
        } catch { }
    }
    return "unknown"
}

# Stable, non-PII machine identifier (SHA256 hash, hostname never leaves the PC).
function Get-MachineId {
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $raw = $env:COMPUTERNAME + "|" + $env:USERDOMAIN
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
            $hash = $sha.ComputeHash($bytes)
            return ([System.BitConverter]::ToString($hash) -replace "-", "").Substring(0, 32).ToLower()
        } finally {
            $sha.Dispose()
        }
    } catch {
        return "unknown"
    }
}

# Replace absolute paths / PII / secrets with placeholders.
function Sanitize-Line([string]$Line) {
    $s = $Line
    try {
        # NOTE: use IsNullOrEmpty guards — an empty pattern would match at
        # every character position and shred the log (found in testing).
        if (-not [string]::IsNullOrEmpty($ProjectRoot)) {
            $s = [regex]::Replace($s, [regex]::Escape($ProjectRoot), "<PROJECT>", "IgnoreCase")
        }
        # UE_ROOT is set by BuildDemo.bat and inherited by this process
        if (-not [string]::IsNullOrEmpty($env:UE_ROOT)) {
            $s = [regex]::Replace($s, [regex]::Escape($env:UE_ROOT), "<UE>", "IgnoreCase")
        }
        # Common UE install roots
        $s = [regex]::Replace($s, "C:\\Program Files( \(x86\))?\\Epic Games\\UE_[\d.]+", "<UE>", "IgnoreCase")
        $s = [regex]::Replace($s, "D:\\Program Files( \(x86\))?\\Epic Games\\UE_[\d.]+", "<UE>", "IgnoreCase")
        # User profile (contains the Windows username) -> <USERPROFILE>
        if (-not [string]::IsNullOrEmpty($env:USERPROFILE)) {
            $s = [regex]::Replace($s, [regex]::Escape($env:USERPROFILE), "<USERPROFILE>", "IgnoreCase")
        }
        # Any Windows user-profile path (covers logs where the name differs) -> <USERPROFILE>
        $s = [regex]::Replace($s, "(?i)[A-Z]:\\Users\\[^\\/:*?`"\`"<>|\\s]+", "<USERPROFILE>")
        # Credential-looking values -> redacted
        $s = [regex]::Replace($s, "(?i)(token|password|passwd|secret|api[_-]?key|bearer|access[_-]?key)[=:`"'\s]+[^\s&""']+",
                              '$1=<REDACTED>')
    } catch { }
    return $s
}

function Get-Utf8ByteCount([string]$Text) {
    return [System.Text.Encoding]::UTF8.GetByteCount($Text)
}

function Post-ToRelay($Payload) {
    $json = $Payload | ConvertTo-Json -Depth 8 -Compress
    try {
        # NOTE: no -UseBasicParsing (throws on PS 5.1); -TimeoutSec keeps us bounded.
        $resp = Invoke-RestMethod -Uri $RelayUrl -Method Post -Body $json `
            -ContentType "application/json" -TimeoutSec 45
        $rid = $null
        if ($resp -ne $null -and $resp.id -ne $null) { $rid = $resp.id }
        return @{ ok = $true; id = $rid; bytes = (Get-Utf8ByteCount $json) }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Save-FailedReport($Payloads, $MetaNote) {
    try {
        $dir = Join-Path $PSScriptRoot "FailedReports"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
        $file = Join-Path $dir ("build-report-" + $ts + ".json")
        $record = @{
            timestamp  = $TimeStamp
            status     = $Status
            session_id = $SessionId
            note       = $MetaNote
            payloads   = $Payloads
        }
        ($record | ConvertTo-Json -Depth 8) | Out-File $file -Encoding utf8
        Write-Host "[WARN] Relay unreachable -- report saved to: $file"
    } catch {
        Write-Host "[WARN] Could not save failed report: $($_.Exception.Message)"
    }
}

# ---------------- read + analyze the build log ----------------

$LogLines = @()
$LogReadNote = ""
if ($BuildLogPath -ne "" -and (Test-Path $BuildLogPath)) {
    try {
        $LogLines = @(Get-Content $BuildLogPath -ErrorAction Stop)
    } catch {
        $LogReadNote = "Could not read build log: $($_.Exception.Message)"
    }
} else {
    $LogReadNote = "No build log found at '$BuildLogPath'"
}

$Sanitized = @()
foreach ($ln in $LogLines) { $Sanitized += (Sanitize-Line ([string]$ln)) }

# Error / warning counting (MSVC Cxxxx / LNKxxxx / MSBxxxx + UBT "error:" styles)
$ErrRe  = '(?i)(^|[\s:])(error|fatal error)([\s:]|$)|error\s+C\d+|error\s+LNK\d+|error\s+MSB\d+'
$WarnRe = '(?i)(^|[\s:])warning([\s:]|$)|warning\s+C\d+|warning\s+MSB\d+'
$ErrorCount = 0
$WarningCount = 0
foreach ($ln in $Sanitized) {
    if ($ln -match $ErrRe)  { $ErrorCount++ }
    elseif ($ln -match $WarnRe) { $WarningCount++ }
}

# Section detection (for the summary; the full text is in `log` anyway)
$UhtLines    = @($Sanitized | Where-Object { $_ -match 'UnrealHeaderTool|\bUHT\b' })
$ShaderLines = @($Sanitized | Where-Object { $_ -match '(?i)shader' })
$MsvcLines   = @($Sanitized | Where-Object { $_ -match 'cl\.exe|link\.exe|\.cpp\(\d+' })

function Get-Tail([array]$Lines, [int]$Count) {
    if ($Lines.Count -eq 0) { return @() }
    if ($Lines.Count -le $Count) { return $Lines }
    return $Lines[($Lines.Count - $Count)..($Lines.Count - 1)]
}

# ---------------- kind="build-log" : legacy error summary (preserved) ----------------

$ErrorLines = @()
if ($LogReadNote -eq "") {
    $ErrorLines = @($Sanitized | Where-Object { $_ -match $ErrRe } |
        Select-Object -First 200 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" })
    if ($ErrorLines.Count -eq 0) {
        $ErrorLines = @("--- No error lines in build log, sending tail ---") +
                      (Get-Tail $Sanitized 50)
    }
} else {
    # Priority 2 (legacy fallback): UBT's internal Log.txt
    $UbtLog = $null
    if (-not [string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
        $UbtLog = Join-Path $env:LOCALAPPDATA "UnrealBuildTool\Log.txt"
    }
    if ($UbtLog -ne $null -and (Test-Path $UbtLog)) {
        try {
            $ErrorLines = @(Get-Content $UbtLog -ErrorAction Stop) |
                Where-Object { (Sanitize-Line ([string]$_)) -match $ErrRe } |
                Select-Object -First 200 |
                ForEach-Object { (Sanitize-Line ([string]$_)).Trim() } |
                Where-Object { $_ -ne "" }
        } catch {
            $ErrorLines = @("Could not read UBT Log.txt: $($_.Exception.Message)")
        }
    }
    if ($ErrorLines.Count -eq 0) {
        $ErrorLines = @($LogReadNote, "UBT Log.txt: not used / not found")
    }
}

$Summary = @(
    "Build status: $Status",
    "Error lines found: $($ErrorLines.Count)"
    ""
) + $ErrorLines

$LegacyPayload = @{
    app        = "marigold-build"
    kind       = "build-log"
    status     = $Status
    timestamp  = $TimeStamp
    version    = (Get-ProjectVersion)
    machine_id = (Get-MachineId)
    session_id = $SessionId
    errors     = ($Summary -join "`n")
}

# ---------------- kind="build-log-full" : full log + analysis ----------------

$FullText  = ($Sanitized -join "`n")
$OrigBytes = Get-Utf8ByteCount $FullText
$Truncated = $false
$TailKeep  = $TailKeepStart

if ($OrigBytes -gt $MaxLogBytes -and $Sanitized.Count -gt 0) {
    $Truncated = $true
    $omit = $Sanitized.Count - $HeadKeep - $TailKeep
    if ($omit -lt 0) { $omit = 0 }
    $head = $Sanitized[0..([Math]::Min($HeadKeep, $Sanitized.Count) - 1)]
    $tail = Get-Tail $Sanitized $TailKeep
    $FullText = ($head -join "`n") + "`n`n... [TRUNCATED: $omit middle lines omitted, " +
                "$OrigBytes bytes total; head $HeadKeep + tail $TailKeep lines kept] ...`n`n" +
                ($tail -join "`n")
}

function Build-FullPayload($LogText, $TailLines) {
    return @{
        app               = "marigold-build"
        kind              = "build-log-full"
        status            = $Status
        timestamp         = $TimeStamp
        version           = (Get-ProjectVersion)
        machine_id        = (Get-MachineId)
        session_id        = $SessionId
        build_duration_s  = $BuildDurationSec
        error_count       = $ErrorCount
        warning_count     = $WarningCount
        log_lines         = $Sanitized.Count
        log_bytes         = $OrigBytes
        truncated         = $Truncated
        tail_lines_kept   = $TailLines
        uht_lines         = $UhtLines.Count
        msvc_lines        = $MsvcLines.Count
        shader_lines      = $ShaderLines.Count
        uht_tail          = ((Get-Tail $UhtLines 40) -join "`n")
        shader_tail       = ((Get-Tail $ShaderLines 40) -join "`n")
        log_read_note     = $LogReadNote
        log               = $LogText
    }
}

$FullPayload = Build-FullPayload $FullText $TailKeep

# Final size guard: shrink the tail until the JSON body fits under $MaxBodyBytes.
# Never let a 413 kill the report.
while ((Get-Utf8ByteCount ($FullPayload | ConvertTo-Json -Depth 8 -Compress)) -gt $MaxBodyBytes -and $TailKeep -gt 25) {
    $TailKeep = [int]([Math]::Floor($TailKeep / 2))
    $Truncated = $true
    $omit = $Sanitized.Count - $HeadKeep - $TailKeep
    if ($omit -lt 0) { $omit = 0 }
    $head = $Sanitized[0..([Math]::Min($HeadKeep, $Sanitized.Count) - 1)]
    $tail = Get-Tail $Sanitized $TailKeep
    $FullText = ($head -join "`n") + "`n`n... [TRUNCATED: $omit middle lines omitted; tail shrunk to $TailKeep lines to fit relay limits] ...`n`n" +
                ($tail -join "`n")
    $FullPayload = Build-FullPayload $FullText $TailKeep
}

# Last resort: if the body is STILL over the limit (pathological line lengths),
# hard-trim the log text by characters so the report always fits.
$FinalJson = $FullPayload | ConvertTo-Json -Depth 8 -Compress
if ((Get-Utf8ByteCount $FinalJson) -gt $MaxBodyBytes) {
    $probe = $FullPayload.Clone()
    $probe["log"] = ""
    $overhead = Get-Utf8ByteCount ($probe | ConvertTo-Json -Depth 8 -Compress)
    $maxLogChars = $MaxBodyBytes - $overhead - 2048
    if ($maxLogChars -lt 1000) { $maxLogChars = 1000 }
    $lt = [string]$FullPayload["log"]
    if ($lt.Length -gt $maxLogChars) {
        $FullPayload["log"] = "... [HARD-TRUNCATED to fit relay limits] ...`n" +
                              $lt.Substring($lt.Length - $maxLogChars)
        $FullPayload["truncated"] = $true
    }
}

# ---------------- send both reports ----------------

$FailedAny = $false
$Note = ""

$r1 = Post-ToRelay $LegacyPayload
if ($r1.ok) {
    Write-Host ("[OK] Error summary sent (kind=build-log, id " + $r1.id + ").")
} else {
    $FailedAny = $true
    $Note += "build-log failed: " + $r1.error + " "
    Write-Host ("[WARN] Could not send error summary: " + $r1.error)
}

$r2 = Post-ToRelay $FullPayload
if ($r2.ok) {
    $dur = ""
    if ($BuildDurationSec -ge 0) { $dur = ", duration ${BuildDurationSec}s" }
    Write-Host ("[OK] Full build log sent (kind=build-log-full, id " + $r2.id +
                ", errors=$ErrorCount, warnings=$WarningCount$dur).")
    Write-Host "     Brio will message you with the fix."
} else {
    $FailedAny = $true
    $Note += "build-log-full failed: " + $r2.error
    Write-Host ("[WARN] Could not send full build log: " + $r2.error)
}

if ($FailedAny) {
    Save-FailedReport @($LegacyPayload, $FullPayload) $Note.Trim()
}

# Never fail the build because logging failed.
exit 0
