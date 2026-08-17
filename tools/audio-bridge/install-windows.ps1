$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$BaseUrl = 'https://raw.githubusercontent.com/AmritSinghGit/ultimate-linux-guide/audio-bridge-bootstrap/tools/audio-bridge'
$Root = Join-Path $env:USERPROFILE 'Downloads\AudioBridge'

Write-Host ''
Write-Host 'AudioBridge bootstrap (Windows)'
Write-Host '==============================='

if (Test-Path -LiteralPath $Root) {
    Remove-Item -LiteralPath $Root -Recurse -Force
}
New-Item -ItemType Directory -Path $Root -Force | Out-Null

Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/SETUP_WINDOWS.ps1" -OutFile (Join-Path $Root 'SETUP_WINDOWS.ps1')
Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/SEND_AUDIO.ps1" -OutFile (Join-Path $Root 'SEND_AUDIO.ps1')

Write-Host "Refreshed: $Root" -ForegroundColor Green
Write-Host 'Running setup, then starting the sender...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'SETUP_WINDOWS.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "Windows setup exited with code $LASTEXITCODE."
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'SEND_AUDIO.ps1')
exit $LASTEXITCODE
