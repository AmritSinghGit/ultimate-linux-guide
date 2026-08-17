[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Find-FFmpeg {
    $command = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe",
        "$env:ProgramFiles\ffmpeg\bin\ffmpeg.exe",
        "${env:ProgramFiles(x86)}\ffmpeg\bin\ffmpeg.exe",
        "C:\ffmpeg\bin\ffmpeg.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }

    $packageRoot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $packageRoot) {
        $found = Get-ChildItem -LiteralPath $packageRoot -Filter ffmpeg.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $found) { return $found.FullName }
    }
    return $null
}

Write-Host ''
Write-Host 'Windows audio sender setup'
Write-Host '=========================='
Write-Host ''

$ffmpeg = Find-FFmpeg
if ($null -eq $ffmpeg) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -eq $winget) { throw 'FFmpeg is missing and winget was not found.' }

    Write-Host 'Installing FFmpeg with winget...'
    & $winget.Source install --id Gyan.FFmpeg --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed with exit code $LASTEXITCODE." }

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
    $ffmpeg = Find-FFmpeg
}

if ($null -eq $ffmpeg) { throw 'FFmpeg installation completed but ffmpeg.exe still cannot be located. Open a new PowerShell window and rerun the same AudioBridge command.' }

Write-Host "FFmpeg found: $ffmpeg" -ForegroundColor Green
Write-Host ''
Write-Host 'For simultaneous playback, Windows needs a recordable copy of system audio.'
Write-Host 'If VoiceMeeter Output, Stereo Mix, or What U Hear is already available, the sender can use it.'
Write-Host 'Otherwise install/configure VoiceMeeter and keep A1 routed to the device that is already playing.'
Write-Host ''
