$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$BaseUrl = 'https://raw.githubusercontent.com/AmritSinghGit/ultimate-linux-guide/audio-bridge-bootstrap/tools/audio-bridge'
$Root = Join-Path $env:USERPROFILE 'Downloads\AudioBridge'
$TempRoot = Join-Path $env:TEMP ('AudioBridge-' + [Guid]::NewGuid().ToString('N'))

Write-Host ''
Write-Host 'AudioBridge bootstrap (Windows)'
Write-Host '==============================='

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    foreach ($file in @('SETUP_WINDOWS.ps1','SEND_AUDIO.ps1')) {
        Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/$file" -OutFile (Join-Path $TempRoot $file)
    }

    # Do not delete the directory a shell may currently be standing in. Replace
    # managed files atomically instead.
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $TempRoot 'SETUP_WINDOWS.ps1') -Destination (Join-Path $Root 'SETUP_WINDOWS.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $TempRoot 'SEND_AUDIO.ps1') -Destination (Join-Path $Root 'SEND_AUDIO.ps1') -Force

    Write-Host "Refreshed safely: $Root" -ForegroundColor Green
    Write-Host 'Running setup, then starting the sender...'
    Write-Host ''

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'SETUP_WINDOWS.ps1')
    $setupCode = $LASTEXITCODE
    if ($setupCode -ne 0) {
        throw "Windows setup exited with code $setupCode."
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'SEND_AUDIO.ps1')
    $senderCode = $LASTEXITCODE
    if ($senderCode -ne 0) {
        throw "Audio sender exited with code $senderCode."
    }
}
catch {
    Write-Host ''
    Write-Host 'AUDIOBRIDGE STOPPED — DIAGNOSTIC' -ForegroundColor Red
    Write-Host '================================' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'The PowerShell window will NOT be closed by AudioBridge.' -ForegroundColor Cyan
    Write-Host "Scripts remain at: $Root"
    Write-Host ''
    return
}
finally {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'AudioBridge sender stopped. PowerShell remains open.' -ForegroundColor Cyan
