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

function Find-Tailscale {
    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    foreach ($candidate in @(
        "$env:ProgramFiles\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
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
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg install failed with exit code $LASTEXITCODE." }
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
    $ffmpeg = Find-FFmpeg
}
if ($null -eq $ffmpeg) { throw 'FFmpeg installation completed but ffmpeg.exe still cannot be located. Rerun the SAME AudioBridge command.' }
Write-Host "FFmpeg found: $ffmpeg" -ForegroundColor Green

Write-Host ''
Write-Host 'Network transport check'
Write-Host '-----------------------'
$ts = Find-Tailscale
if ($null -eq $ts) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -ne $winget) {
        Write-Host 'Installing Tailscale because the computers are on separate phone hotspots...'
        & $winget.Source install --id Tailscale.Tailscale --exact --source winget --accept-package-agreements --accept-source-agreements
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = "$machinePath;$userPath"
        $ts = Find-Tailscale
    }
}

if ($null -ne $ts) {
    try { Start-Service -Name Tailscale -ErrorAction SilentlyContinue } catch {}
    $tsIp = (& $ts ip -4 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($tsIp)) {
        Write-Host ''
        Write-Host 'ONE-TIME ACTION: Tailscale needs sign-in on this Windows laptop.' -ForegroundColor Yellow
        Write-Host 'A browser/login prompt may open. Both computers must be in the same Tailscale network.' -ForegroundColor Yellow
        Write-Host 'Starting Tailscale sign-in now...'
        & $ts up
        $tsIp = (& $ts ip -4 2>$null | Select-Object -First 1)
    }
    if (-not [string]::IsNullOrWhiteSpace($tsIp)) {
        Write-Host "Tailscale connected: $tsIp" -ForegroundColor Green
    } else {
        Write-Host 'Tailscale is installed but not connected yet. Complete sign-in, then rerun the SAME AudioBridge command.' -ForegroundColor Yellow
    }
} else {
    Write-Host 'Tailscale could not be installed automatically. The sender can still use a shared LAN if one exists.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Audio capture check'
Write-Host '-------------------'
Write-Host 'The sender will now inspect recordable Windows audio devices.'
Write-Host 'If Stereo Mix / What U Hear / VoiceMeeter Output exists, it can duplicate current playback without stopping it.'
Write-Host ''
