# Sync-Pi-Corrections.ps1
# Dev tool: clones/updates pi repo, runs model generator, updates models-corrections.json.
# Requires: Node.js, git
# First run: ~60s (clone + npm install). Subsequent: ~15s (git pull + regenerate).
#
# Usage: powershell -File Sync-Pi-Corrections.ps1

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$piCacheDir = Join-Path $scriptDir ".pi-cache"
$piOutputDir = Join-Path $piCacheDir "temp-output"
$correctionsFile = Join-Path $scriptDir "models-corrections.json"
$piRepoUrl = "https://github.com/pi-ai/pi.git"

Write-Host "Sync-Pi-Corrections.ps1 -- Sync pi model corrections"
Write-Host "  Cached in: $piCacheDir"
Write-Host ""

# Check prerequisites
if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Error "git not found. Install git and try again."
    exit 1
}
if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js not found. Install Node.js and try again."
    exit 1
}

# Clone or update pi repo
if (-not (Test-Path (Join-Path $piCacheDir ".git"))) {
    Write-Host "Cloning pi repo (first time, ~30 MB)..."
    git clone --depth 1 $piRepoUrl $piCacheDir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git clone failed. Check network and try again."
        exit 1
    }
} else {
    Write-Host "Updating pi repo (git pull)..."
    Push-Location $piCacheDir
    git pull --depth 1 2>&1 | Out-Null
    Pop-Location
}

# Install dependencies (cached after first run)
if (-not (Test-Path (Join-Path $piCacheDir "node_modules"))) {
    Write-Host "Installing npm dependencies (first time, ~300 MB)..."
    Push-Location $piCacheDir
    npm install --no-audit --no-fund --ignore-scripts 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "npm install failed."
        Pop-Location
        exit 1
    }
    Pop-Location
}

# Run pi's model generator
Write-Host "Running pi model generator..."
$genScript = Join-Path $piCacheDir "packages\ai\scripts\generate-models.ts"
if (-not (Test-Path $genScript)) {
    Write-Error "generate-models.ts not found at $genScript"
    exit 1
}

# Clean previous output
if (Test-Path $piOutputDir) { Remove-Item -Recurse -Force $piOutputDir }

Push-Location $piCacheDir
$result = npx tsx $genScript --json-only --json-output $piOutputDir 2>&1
Pop-Location

if ($LASTEXITCODE -ne 0) {
    Write-Error "Model generator failed: $result"
    exit 1
}
Write-Host "  Done. Output: $piOutputDir"

# Extract DeepSeek corrections
Write-Host "Extracting corrections..."
$deepseekFile = Join-Path $piOutputDir "providers\deepseek.json"
if (Test-Path $deepseekFile) {
    $piModels = Get-Content $deepseekFile -Raw | ConvertFrom-Json

    # Load existing corrections
    $corrections = @{}
    if (Test-Path $correctionsFile) {
        $corrections = Get-Content $correctionsFile -Raw | ConvertFrom-Json
    }

    # Ensure models key exists
    if (-not $corrections.PSObject.Properties["models"]) {
        $corrections | Add-Member -NotePropertyName "models" -NotePropertyValue @{}
    }

    # For each pi model with corrections, update our file (don't overwrite manual edits)
    $updated = $false
    foreach ($prop in $piModels.PSObject.Properties) {
        $modelId = $prop.Name
        $model = $prop.Value

        # Skip if we already have manual corrections for this model
        $existingManual = $null
        try { $existingManual = $corrections.models.$modelId } catch {}

        if ($model.thinkingLevelMap) {
            $hasNonNull = $false
            $tlm = $model.thinkingLevelMap
            if ($tlm -is [PSCustomObject]) {
                foreach ($kv in $tlm.PSObject.Properties) {
                    if ($kv.Value -ne $null -and $kv.Value -ne "") { $hasNonNull = $true; break }
                }
            }
            if ($hasNonNull -and -not $existingManual) {
                # Convert pi's thinkingLevelMap to reasoning_options format for our script
                $values = @()
                foreach ($kv in $tlm.PSObject.Properties) {
                    $values += $kv.Name
                }
                $corrections.models | Add-Member -NotePropertyName $modelId -NotePropertyValue @{
                    reasoning_options = @(
                        @{ type = "effort"; values = $values }
                    )
                } -Force
                $updated = $true
                Write-Host "  + $modelId : thinkingLevelMap synced"
            }
        }
    }

    if ($updated) {
        $corrections | ConvertTo-Json -Depth 10 | Set-Content $correctionsFile -Encoding UTF8
        Write-Host "  Corrections file updated: $correctionsFile"
    } else {
        Write-Host "  No new corrections found (all models already covered)."
    }
} else {
    Write-Warning "deepseek.json not found in pi output."
}

# Summary
Write-Host ""
Write-Host "Sync complete. Corrections file: $correctionsFile"
Write-Host "Run Refresh-Models.ps1 to regenerate DefaultSettings.ahk."
