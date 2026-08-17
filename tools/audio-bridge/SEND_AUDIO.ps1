[CmdletBinding()]
param(
    [string]$MacIP,
    [ValidateRange(1024, 65535)][int]$Port = 49876,
    [string]$Device,
    [ValidateSet('64k','96k','128k')][string]$Bitrate = '128k'
)

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

function Get-DirectShowAudioDevices([string]$FFmpegPath) {
    $lines = & $FFmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>&1
    $names = @()
    foreach ($lineObject in $lines) {
        $match = [regex]::Match($lineObject.ToString(), '^\[dshow[^\]]*\]\s+"(?<name>.+)"\s+\(audio\)\s*$')
        if ($match.Success -and $names -notcontains $match.Groups['name'].Value) { $names += $match.Groups['name'].Value }
    }
    return $names
}

function Find-LikelyMacIP {
    try {
        $candidates = @(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -match '^192\.168\.137\.' -and $_.IPAddress -ne '192.168.137.1' -and $_.State -ne 'Unreachable' } |
            Select-Object -ExpandProperty IPAddress -Unique)
        if ($candidates.Count -eq 1) {
            Write-Host "Auto-detected likely Mac Bluetooth/PAN address: $($candidates[0])" -ForegroundColor Green
            return $candidates[0]
        }
    } catch {}
    return $null
}

function Read-IPv4Address([string]$ExistingValue) {
    $value = $ExistingValue
    if ([string]::IsNullOrWhiteSpace($value)) { $value = Find-LikelyMacIP }
    while ($true) {
        if ([string]::IsNullOrWhiteSpace($value)) { $value = Read-Host 'Enter the Mac Bluetooth/PAN IPv4 address shown by the Mac receiver' }
        [System.Net.IPAddress]$parsed = $null
        if ([System.Net.IPAddress]::TryParse($value, [ref]$parsed) -and $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and $value -ne '0.0.0.0') { return $value }
        Write-Host "'$value' is not a usable IPv4 address." -ForegroundColor Yellow
        $value = $null
    }
}

function Select-AudioDevice([string[]]$Devices, [string]$RequestedDevice) {
    if (-not [string]::IsNullOrWhiteSpace($RequestedDevice)) {
        $exact = $Devices | Where-Object { $_ -eq $RequestedDevice } | Select-Object -First 1
        if ($null -ne $exact) { return $exact }
    }

    $preferred = @($Devices | Where-Object { $_ -match '(?i)VoiceMeeter Output|Stereo Mix|What U Hear' })
    if ($preferred.Count -eq 1) {
        Write-Host "Auto-selected system-audio capture source: $($preferred[0])" -ForegroundColor Green
        return $preferred[0]
    }

    Write-Host 'Available Windows recording/capture devices:'
    for ($i = 0; $i -lt $Devices.Count; $i++) {
        $marker = if ($Devices[$i] -match '(?i)VoiceMeeter Output|Stereo Mix|What U Hear') { '  <-- likely system audio' } else { '' }
        Write-Host ('  [{0}] {1}{2}' -f ($i + 1), $Devices[$i], $marker)
    }
    do {
        $selection = Read-Host 'Choose the capture-device number'
        $number = 0
    } until ([int]::TryParse($selection, [ref]$number) -and $number -ge 1 -and $number -le $Devices.Count)
    return $Devices[$number - 1]
}

Write-Host ''
Write-Host 'Windows -> Mac audio sender'
Write-Host '==========================='
Write-Host ''

$ffmpeg = Find-FFmpeg
if ($null -eq $ffmpeg) { throw 'FFmpeg was not found. Rerun the GitHub AudioBridge one-liner.' }
$devices = @(Get-DirectShowAudioDevices $ffmpeg)
if ($devices.Count -eq 0) { throw 'No Windows audio capture devices were found. Enable Stereo Mix or install/configure VoiceMeeter.' }

$selectedDevice = Select-AudioDevice $devices $Device
$MacIP = Read-IPv4Address $MacIP
$target = 'udp://{0}:{1}?pkt_size=1316' -f $MacIP, $Port

Write-Host ''
Write-Host "Capture device: $selectedDevice"
Write-Host "Destination:    $MacIP UDP/$Port"
Write-Host "Audio bitrate:  $Bitrate"
Write-Host 'Streaming started. Control-C stops it.' -ForegroundColor Green
Write-Host ''

$arguments = @(
    '-hide_banner','-loglevel','warning','-thread_queue_size','2048',
    '-f','dshow','-i',("audio={0}" -f $selectedDevice),
    '-vn','-ac','2','-ar','44100','-af','aresample=async=1:first_pts=0',
    '-c:a','aac','-b:a',$Bitrate,'-profile:a','aac_low',
    '-f','mpegts','-mpegts_flags','+resend_headers','-muxdelay','0','-muxpreload','0','-flush_packets','1',$target
)

& $ffmpeg @arguments
exit $LASTEXITCODE
