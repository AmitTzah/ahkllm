# Refresh-ModelPricing.ps1
# Fetches model pricing from models.dev and outputs AHK-ready format.
# Run manually: right-click "Run with PowerShell", or from terminal:
#   powershell -ExecutionPolicy Bypass -File "Refresh-ModelPricing.ps1"
#
# Output: models_pricing.txt
#   Copy models := Map(...) into DefaultSettings.ahk's models map.
#   Open DefaultSettings.ahk, search for "models := Map", and replace the entire
#   block from "models := Map(" to the closing ")" with the new output.

$ErrorActionPreference = "Stop"
$outFile = Join-Path $PSScriptRoot "models_pricing.txt"

function Write-Color($text, $color) {
    Write-Host $text -ForegroundColor $color
}

function SafeGet($obj, $path) {
    # Walk a dotted property path safely (e.g. "cost.input")
    $result = $obj
    foreach ($part in $path.Split('.')) {
        if ($null -eq $result) { return $null }
        if ($result.PSObject.Properties.Name -notcontains $part) { return $null }
        $result = $result.$part
    }
    return $result
}

function NumberOrZero($val) {
    if ($null -eq $val) { return 0 }
    if ($val -is [int] -or $val -is [float] -or $val -is [double] -or $val -is [decimal]) { return $val }
    return 0
}

Write-Color "Fetching models from models.dev..." "Cyan"

try {
    $response = Invoke-RestMethod -Uri "https://models.dev/api.json" -TimeoutSec 30
} catch {
    Write-Color "ERROR: Failed to fetch models.dev -- $_" "Red"
    exit 1
}

$targetProviders = @("openai", "google", "deepseek")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("; ============================================================================")
$lines.Add("; Auto-generated model pricing from models.dev")
$lines.Add("; Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("; ============================================================================")
$lines.Add(";")
$lines.Add("; HOW TO USE:")
$lines.Add(";  1. Open UserConfig.ahk (find the models := Map(...) block, around line 170)")
$lines.Add(";  2. Replace the ENTIRE block from:")
$lines.Add(";       models := Map(")
$lines.Add(";     through its closing")
$lines.Add(";       )")
$lines.Add(";     with the block below.")
$lines.Add(";  3. Save UserConfig.ahk -- AHK auto-reloads to pick up the new pricing.")
$lines.Add(";  4. Keep only the models you actually use. Delete unused lines.")
$lines.Add(";")
$lines.Add("; If you prefer: paste the whole block and comment out unused models with")
$lines.Add("; a semicolon at the start of each line you don't need.")
$lines.Add(";")
$lines.Add("; ============================================================================")
$lines.Add("")
$lines.Add("models := Map(")

$totalModels = 0
$foundDeepseek = $false

foreach ($providerKey in $targetProviders) {
    $providerData = $response.$providerKey
    if ($null -eq $providerData -or $null -eq $providerData.models) {
        Write-Color "  $providerKey : NOT FOUND" "Yellow"
        continue
    }

    $models = $providerData.models
    $count = 0

    foreach ($modelId in ($models.PSObject.Properties.Name | Sort-Object)) {
        $m = $models.$modelId
        if ($m.tool_call -ne $true) { continue }

        $inputCost    = NumberOrZero(SafeGet $m "cost.input")
        $outputCost   = NumberOrZero(SafeGet $m "cost.output")
        $cacheRead    = NumberOrZero(SafeGet $m "cost.cache_read")
        $contextWin   = NumberOrZero(SafeGet $m "limit.context")
        if ($contextWin -eq 0) { $contextWin = 4096 }
        $hasReasoning = if ($m.reasoning -eq $true) { "true" } else { "false" }
        $hasVision    = "false"
        $modalities   = SafeGet $m "modalities.input"
        if ($null -ne $modalities -and $modalities -contains "image") { $hasVision = "true" }

        $fullId = "$providerKey/$modelId"
        $line = '    "' + $fullId + '", { provider: "' + $providerKey + '", input: ' + $inputCost + ', cachedInput: ' + $cacheRead + ', output: ' + $outputCost + ', context: ' + $contextWin + ', reasoning: ' + $hasReasoning + ', vision: ' + $hasVision + ' },'
        $lines.Add($line)
        $count++
        $totalModels++

        if ($providerKey -eq "deepseek") { $foundDeepseek = $true }
    }

    Write-Color "  $providerKey : $count models" "Green"
}

$lines.Add(")")
$lines.Add("")

if (-not $foundDeepseek) {
    $lines.Add("; NOTE: DeepSeek models not found in models.dev API.")
    $lines.Add("; Manually add DeepSeek V4 models from hardcoded data below:")
    $lines.Add(";")
    $lines.Add(";     ""deepseek/deepseek-v4-pro"",   { provider: ""deepseek"", input: 0.435, cachedInput: 0.003625, output: 0.87,  context: 1000000, reasoning: true, vision: false },")
    $lines.Add(";     ""deepseek/deepseek-v4-flash"", { provider: ""deepseek"", input: 0.14,  cachedInput: 0.0028,   output: 0.28,  context: 1000000, reasoning: true, vision: false },")
    $lines.Add("")
}

$lines.Add("; ============================================================================")
$lines.Add("; Summary: $totalModels models exported from $($targetProviders.Count) providers")
$lines.Add("; ============================================================================")

$lines -join "`r`n" | Out-File -FilePath $outFile -Encoding utf8

Write-Color "" "White"
Write-Color "Done! $totalModels models written to:" "Cyan"
Write-Color "  $outFile" "White"
Write-Color "" "White"
Write-Color "Next steps:" "Yellow"
Write-Color "  1. Open $outFile" "White"
Write-Color "  2. Copy the models := Map(...) block" "White"
Write-Color "  3. Paste it into UserConfig.ahk, replacing the old models map" "White"

if (-not $foundDeepseek) {
    Write-Color "" "White"
    Write-Color "NOTE: DeepSeek models not found in models.dev." "Magenta"
    Write-Color "The script includes hardcoded fallback values in the output file." "Magenta"
}
