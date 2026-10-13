param([Parameter(Mandatory=$true)][string]$OutputPath)

# Metadata-only RPC: never starts a thread or inference turn.
$ErrorActionPreference = 'Stop'
$process = $null
$started = $false
try {
    $executable = if ($env:CODEX_CLI_PATH) { $env:CODEX_CLI_PATH } else {
        (Get-Command codex.exe, codex.cmd -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    }
    if (-not $executable) { throw 'Codex CLI executable was not found on PATH.' }
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $executable
    $start.Arguments = 'app-server --config model_provider="openai" --config forced_login_method="chatgpt" --config mcp_servers={} --config hooks={} --disable apps --disable plugins'
    if ([IO.Path]::GetExtension($executable) -in @('.cmd', '.bat')) {
        if ($executable -match '[%"\r\n]') { throw 'Unsupported characters in Codex CLI wrapper path.' }
        $start.FileName = $env:ComSpec
        $start.Arguments = '/d /s /c ""' + $executable + '" ' + $start.Arguments + '"'
    }
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($key in @('OPENAI_API_KEY', 'AZURE_OPENAI_API_KEY', 'CODEX_API_KEY')) {
        $start.EnvironmentVariables.Remove($key)
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $null = $process.Start()
    $started = $true
    $errorRead = $process.StandardError.ReadToEndAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    function Read-RpcResponse($requestId) {
        while ([DateTime]::UtcNow -lt $deadline) {
            $read = $process.StandardOutput.ReadLineAsync()
            $remaining = [Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
            if (-not $read.Wait($remaining)) { throw 'Codex model discovery timed out.' }
            if ($null -eq $read.Result) { throw ('Codex exited before returning its model catalog. ' + $errorRead.Result) }
            $message = $read.Result | ConvertFrom-Json
            if ($message.id -ne $requestId) { continue }
            if ($message.error) { throw $message.error.message }
            return $message.result
        }
        throw 'Codex model discovery timed out.'
    }
    $process.StandardInput.WriteLine('{"id":1,"method":"initialize","params":{"clientInfo":{"name":"ahkllm","title":"AhkLLM","version":"1.5.0"}}}')
    $null = Read-RpcResponse 1
    $process.StandardInput.WriteLine('{"method":"initialized","params":{}}')
    $models = @()
    $cursor = $null
    $seenCursors = @{}
    do {
        $request = @{ id = 2; method = 'model/list'; params = @{ limit = 100; includeHidden = $false; cursor = $cursor } }
        $process.StandardInput.WriteLine(($request | ConvertTo-Json -Depth 10 -Compress))
        $page = Read-RpcResponse 2
        if ($null -eq $page.data) { throw 'Codex returned an invalid model catalog.' }
        $models += @($page.data)
        $cursor = $page.nextCursor
        if ($cursor) {
            if ($seenCursors.ContainsKey($cursor)) { throw 'Codex returned a repeated catalog cursor.' }
            $seenCursors[$cursor] = $true
        }
    } while ($cursor)
    ConvertTo-Json -InputObject @($models) -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    if ($process) {
        if ($started -and -not $process.HasExited) {
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(1000)) {
                & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
                $process.WaitForExit(3000) | Out-Null
            }
        }
        $process.Dispose()
    }
}
