# Fetch-Models.ps1
# Dumb fetcher: pulls raw model metadata from models.dev and saves to disk.
# WARNING: models.dev data may contain errors. Run Refresh-Models.ps1 to apply corrections.
#
# Usage: powershell -File Fetch-Models.ps1 [-Output <path>]

param(
    [string]$Output = "$PSScriptRoot\models-dev-raw.json"
)

$ErrorActionPreference = "Stop"

Write-Host "Fetch-Models.ps1 -- Raw models.dev fetcher"
Write-Host "  WARNING: models.dev data may contain errors."
Write-Host "  Run Refresh-Models.ps1 to generate corrected default-settings\DefaultSettings.ahk."
Write-Host ""

try {
    Write-Host "Fetching https://models.dev/api.json..."
    $response = Invoke-RestMethod -Uri "https://models.dev/api.json" -Method Get -TimeoutSec 30
} catch {
    Write-Error "Failed to fetch models.dev: $_"
    exit 1
}

$response | ConvertTo-Json -Depth 10 | Set-Content $Output -Encoding UTF8
Write-Host "Saved raw data to: $Output"
Write-Host ""
Write-Host "Done. Raw data saved. Run Refresh-Models.ps1 to generate corrected default-settings\DefaultSettings.ahk."
