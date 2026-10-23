# AnalyzeRenderLog.ps1 — MARIGOLD UE5 Demo render-log analyzer (Expert #6: Render Error Detector)
# Scans a UE editor/build log for RENDER-specific errors and warnings, categorizes
# them, dedupes repeats, and emits prioritized JSON to stdout.
#
# Usage:  powershell -ExecutionPolicy Bypass -File AnalyzeRenderLog.ps1 <log_file_path>
#
# Design notes:
#   - PowerShell 5.1 compatible (no ternary, no ??, no ?. operators).
#   - Streams the file with [System.IO.File]::ReadLines() — never loads the whole
#     log into memory, safe for 100MB+ logs.
#   - Severity model: critical/high count as ERRORS, medium/low count as WARNINGS
#     in the summary. Priority rules: GPU device faults (887A002B etc.) = critical,
#     HLSL compile errors = high, missing textures = high, Lumen/Nanite warnings =
#     medium, everything else = low.
#   - Paths are sanitized (user folders, machine names stripped) — no PII in output.
#   - Exit code is ALWAYS 0. This is an analyzer, not a gate (PreFlight handles gating).
#
# JSON schema:
#   { "summary": { "total_errors": N, "total_warnings": N, "critical": N,
#                  "total_occurrences": N, "scanned_lines": N, "log_file": "..." },
#     "issues": [ { "severity": "critical|high|medium|low",
#                   "category": "hlsl|texture|material|shader|lumen|nanite|gpu|other",
#                   "message": "...", "source": "filename:linenumber",
#                   "suggestion": "...", "occurrences": N }, ... ] }

param(
    [Parameter(Position = 0)]
    [string]$LogPath = ""
)

$ErrorActionPreference = "Continue"

$MAX_ISSUES  = 500   # cap on unique issues emitted (summary counts are unaffected)
$MAX_MSGLEN  = 500   # max message length
$MAX_LINELEN = 8192  # lines longer than this are truncated before regex matching

# --------------------------------------------------------------------------
# Rule table — evaluated top-down, first match wins for a given log line.
# --------------------------------------------------------------------------
$Rules = @(
    [pscustomobject]@{
        Name       = "gpu"
        Category   = "gpu"
        Severity   = "critical"
        Pattern    = "887A002B|DXGI_ERROR_DEVICE_REMOVED|E_OUTOFMEMORY|device\s+hung|GPU[^\r\n]{0,60}removed|D3D12[^\r\n]{0,40}removed"
        Suggestion = "GPU device removed/hung: update NVIDIA drivers, kill overlay apps (Discord/GeForce Experience/RTSS), check thermals/power, verify TDR and HAGS settings."
    },
    [pscustomobject]@{
        Name       = "hlsl"
        Category   = "hlsl"
        Severity   = "high"
        Pattern    = "error\s+X3\d{3}|X3000|X3017|X3500"
        Suggestion = "Fix the HLSL error at the reported file/line, then delete DerivedDataCache and recompile shaders (restart the editor to flush cached shaders)."
    },
    [pscustomobject]@{
        Name       = "texture"
        Category   = "texture"
        Severity   = "high"
        Pattern    = "failed to load[^\r\n]{0,80}textur|textur[^\r\n]{0,80}(failed to load|not found)|texture not found|missing texture|using default[^\r\n]{0,30}texture|default (gray|grey)[^\r\n]{0,20}texture"
        Suggestion = "Reimport or relink the missing texture; verify the /Game/Content path and the source file exist on disk."
    },
    [pscustomobject]@{
        Name       = "material-null"
        Category   = "material"
        Severity   = "low"
        Pattern    = "null material|default material applied|invalid material"
        Suggestion = "Assign a valid material to the mesh/component slot; check for deleted or uncooked material references."
    },
    [pscustomobject]@{
        Name       = "material-expr"
        Category   = "material"
        Severity   = "low"
        Pattern    = "material expression[^\r\n]{0,60}(error|invalid|failed|unconnected|missing)|invalid input|UMaterialExpression\w+[^\r\n]{0,60}(error|invalid|unconnected)"
        Suggestion = "Check the material expression's input pins — reconnect a valid source or replace the input with a constant."
    },
    [pscustomobject]@{
        Name       = "shader-timeout"
        Category   = "shader"
        Severity   = "low"
        Pattern    = "shader compile[^\r\n]{0,40}(timeout|timed out)|shader compilation failed|ShaderCompileWorker[^\r\n]{0,60}(timeout|crashed|terminated|failed)|exceeded[^\r\n]{0,30}shader[^\r\n]{0,20}(limit|timeout)"
        Suggestion = "Retry the shader compile with fewer workers or a higher timeout (r.ShaderCompiler.Timeout in Engine config); check for runaway shader permutations."
    },
    [pscustomobject]@{
        Name       = "lumen"
        Category   = "lumen"
        Severity   = "medium"
        Pattern    = "lumen[^\r\n]{0,80}(warning|error|failed)"
        Suggestion = "Review the Lumen warning: check surface-cache coverage, emissive limits, and hardware ray-tracing settings."
    },
    [pscustomobject]@{
        Name       = "nanite"
        Category   = "nanite"
        Severity   = "medium"
        Pattern    = "nanite[^\r\n]{0,80}(warning|error|fallback|failed)"
        Suggestion = "Review the Nanite warning: check triangle count and material compatibility; the mesh may fall back to non-Nanite rendering."
    },
    [pscustomobject]@{
        Name       = "other"
        Category   = "other"
        Severity   = "low"
        Pattern    = "Log(D3D1[12]RHI|VulkanRHI|RHI|Renderer|ShaderCompilers?|Material|MaterialShader|Streaming|Texture|StaticMesh|MeshUtils|Lumen|Nanite)\s*:\s*(Error|Warning)\s*:"
        Suggestion = "Investigate this renderer log entry; correlate it with nearby HLSL/texture/GPU findings above."
    }
)

# Pre-compile regexes once (IgnoreCase only — keeps 5.1 JIT overhead minimal).
$rxOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
foreach ($r in $Rules) {
    $r | Add-Member -NotePropertyName "Regex" -NotePropertyValue ([regex]::new($r.Pattern, $rxOptions))
}

# Cheap pre-filter so verbose Display/Log lines skip the rule table entirely.
$TriggerRegex = [regex]::new("error|warn|fail|exception|fatal|X3\d|887A|timeout|not found|null|missing|lumen|nanite|fallback|invalid|removed|hung|outofmemory", $rxOptions)

# --------------------------------------------------------------------------
# Sanitization — strip PII from paths/machine names.
# --------------------------------------------------------------------------
function Sanitize-Text {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $t = $Text
    $t = [regex]::Replace($t, "(?i)[A-Z]:\\Users\\[^\\/:*?""<>|\s]+", "C:\Users\<user>")
    $t = [regex]::Replace($t, "(?i)/Users/[^/\s]+", "/Users/<user>")
    $t = [regex]::Replace($t, "(?i)/home/[^/\s]+", "/home/<user>")
    $t = [regex]::Replace($t, "(?i)ComputerName=[^\s,;]+", "ComputerName=<host>")
    $t = [regex]::Replace($t, "(?i)MachineName=[^\s,;]+", "MachineName=<host>")
    return $t
}

# --------------------------------------------------------------------------
# Message builder — extracts shader/material/asset names per rule.
# --------------------------------------------------------------------------
function Build-Message {
    param(
        [pscustomobject]$Rule,
        [string]$Line
    )
    # Strip the UE timestamp/frame prefix so identical errors dedupe across lines.
    $bare = [regex]::Replace($Line, "^\[\d{4}\.\d{2}\.\d{2}-[\d:.]+\]\[\s*\d+\]", "")
    $flat = Sanitize-Text ($bare.Trim())
    if ($flat.Length -gt $MAX_MSGLEN) { $flat = $flat.Substring(0, $MAX_MSGLEN) + "..." }

    switch ($Rule.Name) {
        "gpu" {
            $token = "GPU fault"
            $tm = [regex]::Match($Line, "887A002B|DXGI_ERROR_DEVICE_REMOVED|E_OUTOFMEMORY", $rxOptions)
            if ($tm.Success) { $token = $tm.Value }
            else {
                $m = $Rule.Regex.Match($Line)
                if ($m.Success) { $token = $m.Value.Trim() }
            }
            return "GPU device fault ($token): $flat"
        }
        "hlsl" {
            $shader = ""; $sl = ""; $sc = ""; $code = ""; $detail = ""
            $fm = [regex]::Match($Line, "([A-Za-z0-9_\-./\\:]+\.(?:usf|ush))\s*\((\d+)(?:\s*,\s*(\d+))?\)", $rxOptions)
            if ($fm.Success) {
                $shader = [System.IO.Path]::GetFileName($fm.Groups[1].Value)
                $sl = $fm.Groups[2].Value
                $sc = $fm.Groups[3].Value
            }
            $cm = [regex]::Match($Line, "error\s*(X3\d{3})\s*:?\s*(.*)$", $rxOptions)
            if ($cm.Success) {
                $code = $cm.Groups[1].Value.ToUpper()
                $detail = Sanitize-Text ($cm.Groups[2].Value.Trim())
                if ($detail.Length -gt 220) { $detail = $detail.Substring(0, 220) + "..." }
            }
            if ($shader -ne "") {
                $loc = $sl
                if ($sc -ne "") { $loc = "$sl,$sc" }
                if ($code -ne "") { return "HLSL error $code in $shader($loc): $detail" }
                return "HLSL error in $shader($loc): $flat"
            }
            $mm = [regex]::Match($Line, "(?i)(?:for |compiling |material\s+)([A-Za-z0-9_\-/\.]+(?:/M_[A-Za-z0-9_]+|Material[A-Za-z0-9_]*)?)", $rxOptions)
            if ($mm.Success -and $code -ne "") {
                return "HLSL error $code compiling $($mm.Groups[1].Value): $detail"
            }
            if ($code -ne "") { return "HLSL error ${code}: $detail" }
            return "HLSL compile failure: $flat"
        }
        "texture" {
            $am = [regex]::Match($Line, "(?i)(/Game/[^\s,""')\]]+)", $rxOptions)
            if ($am.Success) {
                return "Missing texture $(Sanitize-Text $am.Groups[1].Value): $flat"
            }
            return "Missing texture: $flat"
        }
        "material-expr" {
            $em = [regex]::Match($Line, "UMaterialExpression\w+", $rxOptions)
            if ($em.Success) {
                return "Material expression error in $($em.Groups[0].Value): $flat"
            }
            return "Material expression error: $flat"
        }
        default { return $flat }
    }
}

# --------------------------------------------------------------------------
# Emit-Json — always valid JSON, always exit 0.
# --------------------------------------------------------------------------
function Emit-Result {
    param(
        [System.Collections.ArrayList]$Issues,
        [long]$ScannedLines,
        [long]$TotalOccurrences,
        [string]$LogFileName
    )
    $err = 0; $warn = 0; $crit = 0
    foreach ($i in $Issues) {
        if ($i.severity -eq "critical" -or $i.severity -eq "high") { $err++ } else { $warn++ }
        if ($i.severity -eq "critical") { $crit++ }
    }
    $summary = [pscustomobject]@{
        total_errors      = $err
        total_warnings    = $warn
        critical          = $crit
        total_occurrences = $TotalOccurrences
        scanned_lines     = $ScannedLines
        log_file          = $LogFileName
    }
    $result = [pscustomobject]@{
        summary = $summary
        issues  = @($Issues)
    }
    $json = $result | ConvertTo-Json -Depth 4
    [System.Console]::WriteLine($json)
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
$Issues      = New-Object System.Collections.ArrayList
$Dedup       = @{}          # dedup key -> index in $Issues
$Scanned     = [long]0
$Occurrences = [long]0
$FileName    = ""

if ([string]::IsNullOrWhiteSpace($LogPath) -or -not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    $shortName = "unknown"
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        try { $shortName = [System.IO.Path]::GetFileName($LogPath) } catch { $shortName = "unknown" }
    }
    $note = [pscustomobject]@{
        severity    = "low"
        category    = "other"
        message     = "Log file not found or unreadable: $shortName"
        source      = "AnalyzeRenderLog.ps1:0"
        suggestion  = "Verify the log file path exists and is readable, then re-run."
        occurrences = 1
    }
    [void]$Issues.Add($note)
    Emit-Result -Issues $Issues -ScannedLines 0 -TotalOccurrences 0 -LogFileName $shortName
    exit 0
}

$FileName = [System.IO.Path]::GetFileName($LogPath)

try {
    $lineNo = [long]0
    foreach ($raw in [System.IO.File]::ReadLines($LogPath)) {
        $lineNo++
        $Scanned = $lineNo
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        if (-not $TriggerRegex.IsMatch($raw)) { continue }

        $line = $raw
        if ($line.Length -gt $MAX_LINELEN) { $line = $line.Substring(0, $MAX_LINELEN) }

        foreach ($rule in $Rules) {
            if (-not $rule.Regex.IsMatch($line)) { continue }

            $msg = Build-Message -Rule $rule -Line $line
            $key = "$($rule.Name)|$msg"
            if ($Dedup.ContainsKey($key)) {
                $idx = $Dedup[$key]
                $Issues[$idx].occurrences = [int]$Issues[$idx].occurrences + 1
            }
            else {
                if ($Issues.Count -ge $MAX_ISSUES) { break }
                $issue = [pscustomobject]@{
                    severity    = $rule.Severity
                    category    = $rule.Category
                    message     = $msg
                    source      = "${FileName}:$lineNo"
                    suggestion  = $rule.Suggestion
                    occurrences = 1
                }
                $Dedup[$key] = $Issues.Count
                [void]$Issues.Add($issue)
            }
            $Occurrences++
            break   # first matching rule wins per line
        }
    }
}
catch {
    $note = [pscustomobject]@{
        severity    = "low"
        category    = "other"
        message     = "Error while reading log: $(Sanitize-Text $_.Exception.Message)"
        source      = "${FileName}:0"
        suggestion  = "Verify the log file is not locked or corrupted, then re-run."
        occurrences = 1
    }
    [void]$Issues.Add($note)
}

Emit-Result -Issues $Issues -ScannedLines $Scanned -TotalOccurrences $Occurrences -LogFileName $FileName
exit 0
