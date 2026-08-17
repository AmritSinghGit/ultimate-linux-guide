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

function Get-DirectShowAudioDevices([string]$FFmpegPath) {
    $lines = & $FFmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>&1
    $names = @()
    foreach ($lineObject in $lines) {
        $match = [regex]::Match($lineObject.ToString(), '^\[dshow[^\]]*\]\s+"(?<name>.+)"\s+\(audio\)\s*$')
        if ($match.Success -and $names -notcontains $match.Groups['name'].Value) { $names += $match.Groups['name'].Value }
    }
    return $names
}

function Find-MacViaTailscale {
    $ts = Find-Tailscale
    if ($null -eq $ts) { return $null }
    try {
        $raw = (& $ts status --json 2>$null) -join "`n"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $status = $raw | ConvertFrom-Json
        $peers = @()
        if ($null -ne $status.Peer) {
            $peers = @($status.Peer.PSObject.Properties | ForEach-Object { $_.Value })
        }
        $macs = @($peers | Where-Object {
            $os = [string]$_.OS
            $online = if ($_.PSObject.Properties.Name -contains 'Online') { [bool]$_.Online } else { $true }
            $online -and $os -match '(?i)mac|darwin' -and $null -ne $_.TailscaleIPs
        })
        if ($macs.Count -eq 1) {
            $ip = @($macs[0].TailscaleIPs | Where-Object { $_ -match '^100\.' } | Select-Object -First 1)
            if ($ip.Count -eq 1) {
                Write-Host "Auto-detected Mac through Tailscale: $($ip[0])" -ForegroundColor Green
                return $ip[0]
            }
        }
        if ($macs.Count -gt 1) {
            Write-Host 'Multiple online Macs were found in Tailscale:'
            for ($i = 0; $i -lt $macs.Count; $i++) {
                $ip = @($macs[$i].TailscaleIPs | Where-Object { $_ -match '^100\.' } | Select-Object -First 1)
                $name = if ($macs[$i].DNSName) { ([string]$macs[$i].DNSName).TrimEnd('.') } else { [string]$macs[$i].HostName }
                Write-Host ('  [{0}] {1}  {2}' -f ($i + 1), $name, ($ip -join ''))
            }
        }
    } catch {}
    return $null
}

function Test-UsableIPv4([string]$Address) {
    [System.Net.IPAddress]$parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) { return $false }
    if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $octets = $parsed.GetAddressBytes()
    return $octets[0] -ne 0 -and $octets[0] -ne 127 -and $octets[0] -lt 224 -and $Address -ne '255.255.255.255'
}

function Find-MacViaPan {
    try {
        $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object {
            ("{0} {1}" -f $_.Name, $_.InterfaceDescription) -match '(?i)Bluetooth|Personal Area Network|\bPAN\b'
        })
        if ($adapters.Count -eq 0) {
            Write-Host 'No Bluetooth/PAN interface was detected. Wi-Fi or Ethernet can still be used.' -ForegroundColor Yellow
            return $null
        }

        $activeAdapters = @($adapters | Where-Object { $_.Status -eq 'Up' })
        if ($activeAdapters.Count -eq 0) {
            Write-Host 'A Bluetooth/PAN interface exists, but it is not connected. Wi-Fi or Ethernet can still be used.' -ForegroundColor Yellow
            return $null
        }

        $localAddresses = @(foreach ($adapter in $activeAdapters) {
            Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty IPAddress
        })
        $candidates = @()
        foreach ($adapter in $activeAdapters) {
            $neighbors = @(Get-NetNeighbor -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.State -notin @('Unreachable', 'Incomplete') })
            foreach ($neighbor in $neighbors) {
                if ((Test-UsableIPv4 $neighbor.IPAddress) -and $localAddresses -notcontains $neighbor.IPAddress -and $candidates -notcontains $neighbor.IPAddress) {
                    $candidates += $neighbor.IPAddress
                }
            }
        }
        if ($candidates.Count -eq 1) {
            Write-Host "Auto-detected the only usable Bluetooth/PAN neighbor: $($candidates[0])" -ForegroundColor Green
            return $candidates[0]
        }
        if ($candidates.Count -gt 1) {
            Write-Host ("Multiple Bluetooth/PAN neighbors were detected: {0}" -f ($candidates -join ', ')) -ForegroundColor Yellow
        }
    } catch {
        Write-Host ("Bluetooth/PAN auto-detection could not run: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
    return $null
}

function Read-IPv4Address([string]$ExistingValue) {
    $value = $ExistingValue
    if ([string]::IsNullOrWhiteSpace($value) -and -not [string]::IsNullOrWhiteSpace($env:AUDIOBRIDGE_MAC_IP)) {
        $value = $env:AUDIOBRIDGE_MAC_IP
    }
    if ([string]::IsNullOrWhiteSpace($value)) { $value = Find-MacViaTailscale }
    if ([string]::IsNullOrWhiteSpace($value)) { $value = Find-MacViaPan }
    while ($true) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host ''
            Write-Host 'Automatic Mac discovery did not find a reachable Mac.' -ForegroundColor Yellow
            Write-Host 'Use any reachable address printed by the Mac receiver: LAN, Tailscale, or Bluetooth/PAN.' -ForegroundColor Yellow
            $value = Read-Host 'Enter the Mac IPv4 address'
        }
        if (Test-UsableIPv4 $value) { return $value }
        Write-Host "'$value' is not a usable IPv4 address." -ForegroundColor Yellow
        $value = $null
    }
}

function Select-AudioDevice([string[]]$Devices, [string]$RequestedDevice) {
    if (-not [string]::IsNullOrWhiteSpace($RequestedDevice)) {
        $exact = $Devices | Where-Object { $_ -eq $RequestedDevice } | Select-Object -First 1
        if ($null -ne $exact) { return $exact }
        Write-Host "Requested capture device was not found: $RequestedDevice" -ForegroundColor Yellow
    }

    $systemAudioPattern = '(?i)virtual-audio-capturer|VoiceMeeter.*Output|Stereo Mix|What U Hear|Wave Out Mix|Loopback'
    $preferred = @($Devices | Where-Object { $_ -match $systemAudioPattern })
    if ($preferred.Count -eq 1) {
        Write-Host "Auto-selected system-audio capture source: $($preferred[0])" -ForegroundColor Green
        return $preferred[0]
    }

    Write-Host 'Available Windows recording/capture devices:'
    for ($i = 0; $i -lt $Devices.Count; $i++) {
        $marker = if ($Devices[$i] -match $systemAudioPattern) { '  <-- system audio candidate' } else { '' }
        Write-Host ('  [{0}] {1}{2}' -f ($i + 1), $Devices[$i], $marker)
    }

    if ($preferred.Count -eq 0) {
        Write-Host ''
        Write-Host 'No system-playback capture endpoint was found.' -ForegroundColor Yellow
        Write-Host 'Do NOT choose the microphone if you want the laptop sound.' -ForegroundColor Yellow
        Write-Host 'Enable Stereo Mix if the audio driver provides it, or install VoiceMeeter so Windows exposes a recordable playback copy.' -ForegroundColor Yellow
        throw 'System-audio capture endpoint missing (Stereo Mix / What U Hear / VoiceMeeter Output / virtual-audio-capturer).'
    }

    do {
        $selection = Read-Host 'Choose the system-audio capture-device number'
        $number = 0
    } until ([int]::TryParse($selection, [ref]$number) -and $number -ge 1 -and $number -le $Devices.Count -and $Devices[$number - 1] -match $systemAudioPattern)
    return $Devices[$number - 1]
}

Write-Host ''
Write-Host 'Windows -> Mac audio sender'
Write-Host '==========================='
Write-Host ''

$ffmpeg = Find-FFmpeg
if ($null -eq $ffmpeg) { throw 'FFmpeg was not found. Rerun the GitHub AudioBridge one-liner.' }
$devices = @(Get-DirectShowAudioDevices $ffmpeg)
if ($devices.Count -eq 0) { throw 'No Windows audio capture devices were found at all.' }

$selectedDevice = Select-AudioDevice $devices $Device
$MacIP = Read-IPv4Address $MacIP
$target = 'udp://{0}:{1}?pkt_size=1316' -f $MacIP, $Port

Write-Host ''
Write-Host "Capture device: $selectedDevice"
Write-Host "Destination:    $MacIP UDP/$Port"
Write-Host "Audio bitrate:  $Bitrate"
Write-Host 'Streaming started. Existing Windows playback is not stopped by this sender.' -ForegroundColor Green
Write-Host 'Control-C stops only the AudioBridge stream.' -ForegroundColor Green
Write-Host ''

$arguments = @(
    '-hide_banner','-loglevel','warning','-thread_queue_size','2048',
    '-f','dshow','-i',("audio={0}" -f $selectedDevice),
    '-vn','-ac','2','-ar','44100','-af','aresample=async=1:first_pts=0',
    '-c:a','aac','-b:a',$Bitrate,'-profile:a','aac_low',
    '-f','mpegts','-mpegts_flags','+resend_headers','-muxdelay','0','-muxpreload','0','-flush_packets','1',$target
)

& $ffmpeg @arguments
$code = $LASTEXITCODE
if ($code -ne 0) { throw "FFmpeg sender exited with code $code." }
