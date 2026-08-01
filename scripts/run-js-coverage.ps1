# run-js-coverage.ps1
#
# Runs the JS unit tests with V8 coverage enabled, then prints a per-file
# coverage report. The preload script makes vm-loaded browser modules show up
# under their real file paths.
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run-js-coverage.ps1

$ErrorActionPreference = 'Stop'
$coverageDir = Join-Path $env:TEMP 'js-v8cov'

if (Test-Path $coverageDir) {
    Remove-Item -Recurse -Force -LiteralPath $coverageDir
}
New-Item -ItemType Directory -Force -Path $coverageDir | Out-Null

$env:NODE_V8_COVERAGE = $coverageDir
node --require ./scripts/js-coverage-preload.js --test "tests/unit/*.test.js"
if ($LASTEXITCODE -ne 0) {
    Write-Host "JS tests failed; coverage report may be incomplete." -ForegroundColor Red
    exit $LASTEXITCODE
}

node scripts/js-coverage-report.js
exit $LASTEXITCODE
