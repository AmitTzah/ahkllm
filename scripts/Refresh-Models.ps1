# Refresh-Models.ps1
# Fetches model metadata, applies corrections from models-corrections.json,
# and updates DefaultSettings.ahk in-place.
#
# Pipeline: models.dev (raw) -> models-corrections.json (override) -> DefaultSettings.ahk
#
# Run from terminal: powershell -ExecutionPolicy Bypass -File "scripts\Refresh-Models.ps1"
# Also accessible from Quick Access menu in the app.
#
# See README.md in this directory for the full pipeline explanation.

param([switch]$NoPause)

try {
    $ErrorActionPreference = "Stop"
    $scriptDir = $PSScriptRoot
    $defaultSettingsPath = Join-Path $scriptDir "..\DefaultSettings.ahk"
    $backupFile = Join-Path $scriptDir "models_metadata.txt"
    $correctionsFile = Join-Path $scriptDir "models-corrections.json"

    function Write-Color($text, $color) { Write-Host $text -ForegroundColor $color }
    function SafeGet($obj, $path) {
        $r = $obj; foreach ($p in $path.Split('.')) {
            if ($null -eq $r) { return $null }
            if ($r.PSObject.Properties.Name -notcontains $p) { return $null }
            $r = $r.$p
        }; return $r
    }
    function Num($v) { if ($null -eq $v) { return 0 }; if ($v -is [int] -or $v -is [float] -or $v -is [double] -or $v -is [decimal]) { return $v }; return 0 }

    # --- Provider discovery ---
    function Get-ProvidersFromSettings($path) {
        if (-not (Test-Path $path)) { return @() }
        $inBlock = $false; $result = @()
        foreach ($line in (Get-Content $path)) {
            if ($line -match '^\s*providers\s*:=\s*Map\(') { $inBlock = $true; continue }
            if ($inBlock -and $line -match '^\s*\)') { break }
            if ($inBlock -and $line -match '^\s*"(\w+)"') { $result += $matches[1] }
        }
        return $result
    }

    # --- Load corrections ---
    function Load-Corrections($path) {
        if (-not (Test-Path $path)) { return @{} }
        try {
            $c = Get-Content $path -Raw | ConvertFrom-Json
            $map = @{}
            if ($c.models) {
                foreach ($prop in $c.models.PSObject.Properties) {
                    $map[$prop.Name] = $prop.Value
                }
            }
            return $map
        } catch { return @{} }
    }

    # --- Thinking metadata ---
    function ThinkingFormat($p) { if ($p -eq "deepseek") { "deepseek" } elseif ($p -eq "google") { "google" } else { "openai" } }
    function MaxTokensField($p) { if ($p -eq "openai") { "max_completion_tokens" } else { "max_tokens" } }

    function Get-EffortValues($ro, $modelId, $p, $correctionsMap, $familyFallback) {
        # Priority: corrections file > reasoning_options > family fallback
        if ($correctionsMap[$modelId] -and $correctionsMap[$modelId].reasoning_options) {
            $cro = $correctionsMap[$modelId].reasoning_options
            $vals = @()
            if ($cro) { foreach ($o in $cro) { if ($o.type -eq "effort") { $vals += $o.values } } }
            if ($vals.Count -gt 0) { return $vals }
        }
        # models.dev reasoning_options
        $vals = @()
        if ($ro) { foreach ($o in $ro) { if ($o.type -eq "effort") { $vals += $o.values } } }
        if ($vals.Count -gt 0) { return $vals }
        # Family fallback (same prefix or same provider)
        return Get-FallbackEffort $p $modelId $familyFallback
    }

    function Get-FallbackEffort($prov, $modelId, $familyFallback) {
        $family = $modelId -replace '^(.+?)(-\d+)?(-.*)?$', '$1'
        $key = "$prov|$family"
        if ($familyFallback[$key]) { return $familyFallback[$key] }
        foreach ($k in $familyFallback.Keys) {
            if ($k -match "^$prov\|") { return $familyFallback[$k] }
        }
        return $null
    }

    function ThinkingLevelMap($vals, $prov) {
        if ($null -eq $vals -or $vals.Count -eq 0) { return "Map()" }
        $seen = @{}; $entries = @()
        foreach ($l in $vals) {
            if ($null -eq $l -or $l -eq "default" -or $seen[$l]) { continue }; $seen[$l] = $true
            $pv = if ($prov -eq "google" -and $l -match "^(minimal|low|medium|high|xhigh|max)$") { $l.ToUpper() } else { $l }
            $entries += "`"$l`", `"$pv`""
        }
        if ($entries.Count -eq 0) { return "Map()" }
        return "Map(" + ($entries -join ", ") + ")"
    }

    function ThinkingOff($vals, $prov) {
        if ($null -eq $vals -or $vals.Count -eq 0) { return "" }
        if ($prov -eq "deepseek") { return "disabled" }
        if ($vals -contains "none") { return "none" }
        $order = @{minimal=1;low=2;medium=3;high=4;xhigh=5;max=6}
        $sorted = $vals | Where-Object { $_ -ne $null -and $_ -ne "default" -and $_ -ne "none" } | Sort-Object { $order[$_.ToLower()] }
        if ($sorted.Count -gt 0) { $ml = $sorted[0]; if ($prov -eq "google") { $ml.ToUpper() } else { $ml } } else { "" }
    }

    # --- Main ---
    Write-Color "Refresh-Models.ps1 -- Model metadata pipeline" "Cyan"
    Write-Host ""

    $targetProviders = Get-ProvidersFromSettings $defaultSettingsPath
    if ($targetProviders.Count -eq 0) { $targetProviders = @("openai","google","deepseek"); Write-Color "  No providers found, using defaults" "Yellow" }
    Write-Color "  Providers: $($targetProviders -join ', ')" "Cyan"

    # Load corrections
    $correctionsMap = Load-Corrections $correctionsFile
    if ($correctionsMap.Count -gt 0) {
        Write-Color "  Corrections loaded: $correctionsFile ($($correctionsMap.Count) models)" "DarkGray"
    }

    Write-Color "  Fetching models.dev..." "Cyan"
    $response = Invoke-RestMethod "https://models.dev/api.json" -TimeoutSec 30

    $lines = [System.Collections.Generic.List[string]]::new()
    $totalModels = 0

    # Pre-scan: build fallback map per model-family prefix within each provider
    $familyFallback = @{}
    foreach ($p in $targetProviders) {
        $pd = $response.$p
        if ($null -eq $pd -or $null -eq $pd.models) { continue }
        foreach ($mid in $pd.models.PSObject.Properties.Name) {
            $family = $mid -replace '^(.+?)(-\d+)?(-.*)?$', '$1'
            $ro = SafeGet $pd.models.$mid "reasoning_options"
            if ($ro) {
                foreach ($o in $ro) { if ($o.type -eq "effort") { $familyFallback["$p|$family"] = $o.values; break } }
            }
        }
    }

    foreach ($p in $targetProviders) {
        $pd = $response.$p
        if ($null -eq $pd -or $null -eq $pd.models) { Write-Color "  $p : NOT FOUND" "Yellow"; continue }
        $count = 0
        $dn = if ($p -eq "google") { "Google Gemini" } elseif ($p -eq "openai") { "OpenAI" } elseif ($p -eq "deepseek") { "DeepSeek" } else { $p }
        $lines.Add("    ; -- $dn --")

        foreach ($mid in ($pd.models.PSObject.Properties.Name | Sort-Object)) {
            $m = $pd.models.$mid
            if ($m.tool_call -ne $true) { continue }

            $ic = Num (SafeGet $m "cost.input")
            $oc = Num (SafeGet $m "cost.output")
            $cr = Num (SafeGet $m "cost.cache_read")
            $cw = Num (SafeGet $m "limit.context"); if ($cw -eq 0) { $cw = 4096 }

            # Apply corrections for all overridable fields
            if ($correctionsMap[$mid]) {
                $corr = $correctionsMap[$mid]
                # Pricing
                if ($corr.pricing) {
                    $pc = $corr.pricing
                    if ($pc.input -ne $null) { $ic = $pc.input }
                    if ($pc.output -ne $null) { $oc = $pc.output }
                    if ($pc.cache_read -ne $null) { $cr = $pc.cache_read }
                }
                # Context window
                if ($corr.context -ne $null) { $cw = $corr.context }
                # Toggles
                if ($corr.reasoning -ne $null) { $hr = if ($corr.reasoning) { "true" } else { "false" } }
                if ($corr.vision -ne $null) { $hv = if ($corr.vision) { "true" } else { "false" } }
                # Compat overrides (deep merge: correction fields override, rest kept)
                if ($corr.compat) {
                    # These are handled inline during generation below -- the thinkingFormat
                    # and supportsReasoningEffort are derived, not from corrections.
                    # compat overrides are applied after the derived values.
                }
            }
            $hr = if ($m.reasoning -eq $true) { "true" } else { "false" }
            $hv = "false"; $mod = SafeGet $m "modalities.input"; if ($mod -and $mod -contains "image") { $hv = "true" }

            $tf = ThinkingFormat $p
            $ro = SafeGet $m "reasoning_options"
            $fb = if ($m.reasoning -eq $true) { Get-FallbackEffort $p $mid $familyFallback } else { $null }
            $evals = Get-EffortValues $ro $mid $p $correctionsMap $familyFallback
            if ($null -eq $evals -or $evals.Count -eq 0) { $evals = $fb }
            $tlm = ThinkingLevelMap $evals $p
            $to = ThinkingOff $evals $p
            $mtf = MaxTokensField $p
            $sre = if ($evals -and $evals.Count -gt 0) { "true" } else { "false" }

            $fid = "$p/$mid"
            $lines.Add('    "' + $fid + '", {')
            $lines.Add('        provider: "' + $p + '", api: "openai-completions",')
            $lines.Add('        compat: Map("thinkingFormat", "' + $tf + '", "supportsReasoningEffort", ' + $sre + ', "supportsUsageInStreaming", true, "maxTokensField", "' + $mtf + '"),')
            $lines.Add('        thinkingLevelMap: ' + $tlm + ',')
            $lines.Add('        thinkingOff: "' + $to + '",')
            $lines.Add('        input: ' + $ic + ', cachedInput: ' + $cr + ', output: ' + $oc + ', context: ' + $cw + ', reasoning: ' + $hr + ', vision: ' + $hv)
            $lines.Add('    },')
            $count++; $totalModels++
        }
        Write-Color "  $p : $count models" "Green"
    }

    # Write backup
    $header = @"
; ============================================================================
; Auto-generated model metadata from models.dev
; Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
; $totalModels models from $($targetProviders.Count) providers
; Corrections applied from models-corrections.json
; ============================================================================

"@
    ($header + "models := Map(" + ($lines -join "`r`n") + "`r`n)") | Out-File $backupFile -Encoding utf8

    # Update DefaultSettings.ahk
    if (-not (Test-Path $defaultSettingsPath)) {
        Write-Color "ERROR: DefaultSettings.ahk not found" "Red"
    }
    else {
        $fl = Get-Content $defaultSettingsPath
        $ms = -1; $me = -1
        for ($i = 0; $i -lt $fl.Count; $i++) {
            if ($ms -lt 0 -and $fl[$i] -match '^\s*models\s*:=\s*Map\(') { $ms = $i }
            if ($ms -ge 0 -and $fl[$i] -match '^\s*\)\s*$' -and $i -gt $ms) { $me = $i; break }
        }

        if ($ms -ge 0 -and $me -gt $ms) {
            $blockLines = @("models := Map(") + $lines + @(")")
            $newContent = ($fl[0..($ms - 1)] + $blockLines + $fl[($me + 1)..($fl.Count - 1)]) -join "`r`n"
            Set-Content $defaultSettingsPath $newContent -Encoding UTF8 -NoNewline

            # Clean up common UTF-8 corruption
            $finalContent = Get-Content $defaultSettingsPath -Raw -Encoding UTF8
            $finalContent = $finalContent.Replace([char]0x00E2 + [char]0x201A + [char]0x00AC, '--')
            $finalContent = $finalContent.Replace([char]0x00C2 + [char]0x00A7, 'S')
            $finalContent = $finalContent.Replace([char]0x00E2 + [char]0x2020 + [char]0x2122, '->')
            Set-Content $defaultSettingsPath $finalContent -Encoding UTF8 -NoNewline

            Write-Host ""
            Write-Color "SUCCESS: DefaultSettings.ahk updated with $totalModels models!" "Green"
            Write-Color "  AHK will auto-reload to pick up the changes." "Green"
        } else {
            Write-Host ""
            Write-Color "WARNING: Could not find models := Map(...) block" "Yellow"
            Write-Color "  Copy from: $backupFile" "Yellow"
        }
    }
}
catch {
    Write-Host ""
    Write-Color "ERROR: $_" "Red"
    exit 1
}
finally {
    if (-not $NoPause) {
        Write-Host ""
        Write-Host "Press any key to exit..."
        try {
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        } catch {
            cmd /c pause
        }
    }
}
