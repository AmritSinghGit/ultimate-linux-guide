[CmdletBinding()]
param(
    [string]$MacIP,
    [switch]$PauseOnManualAction
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
        'C:\ffmpeg\bin\ffmpeg.exe'
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
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
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Get-TailscaleMacCandidates {
    param([string]$TailscalePath)

    $addresses = @()
    try {
        $raw = (& $TailscalePath status --json 2>$null) -join "`n"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $addresses }
        $status = $raw | ConvertFrom-Json
        if ($null -eq $status.Peer) { return $addresses }
        $peers = @($status.Peer.PSObject.Properties | ForEach-Object { $_.Value })
        foreach ($peer in $peers) {
            $online = if ($peer.PSObject.Properties.Name -contains 'Online') { [bool]$peer.Online } else { $true }
            if (-not $online -or ([string]$peer.OS) -notmatch '(?i)mac|darwin') { continue }
            foreach ($address in @($peer.TailscaleIPs | Where-Object { $_ -match '^100\.' })) {
                if ($addresses -notcontains $address) { $addresses += $address }
            }
        }
    } catch {
        Write-Host ("  Tailscale peer discovery failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
    return $addresses
}

function Get-DirectShowAudioDevices {
    param([string]$FFmpegPath)

    $lines = & $FFmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>&1
    $names = @()
    foreach ($lineObject in $lines) {
        $match = [regex]::Match($lineObject.ToString(), '^\[dshow[^\]]*\]\s+"(?<name>.+)"\s+\(audio\)\s*$')
        if ($match.Success -and $names -notcontains $match.Groups['name'].Value) {
            $names += $match.Groups['name'].Value
        }
    }
    return $names
}

function Test-UsableIPv4 {
    param([string]$Address)

    [System.Net.IPAddress]$parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) { return $false }
    if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $octets = $parsed.GetAddressBytes()
    return $octets[0] -ne 0 -and $octets[0] -ne 127 -and $octets[0] -lt 224 -and $Address -ne '255.255.255.255'
}

function Get-BluetoothPanAdapters {
    param([object[]]$Adapters)

    return @($Adapters | Where-Object {
        ("{0} {1}" -f $_.Name, $_.InterfaceDescription) -match '(?i)Bluetooth|Personal Area Network|\bPAN\b'
    })
}

function Get-PanNeighborCandidates {
    param(
        [object[]]$PanAdapters,
        [string[]]$LocalAddresses
    )

    $addresses = @()
    foreach ($adapter in $PanAdapters) {
        if ($adapter.Status -ne 'Up') { continue }
        try {
            $neighbors = @(Get-NetNeighbor -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.State -notin @('Unreachable', 'Incomplete') })
            foreach ($neighbor in $neighbors) {
                if ((Test-UsableIPv4 $neighbor.IPAddress) -and $LocalAddresses -notcontains $neighbor.IPAddress -and $addresses -notcontains $neighbor.IPAddress) {
                    $addresses += $neighbor.IPAddress
                }
            }
        } catch {
            Write-Host ("  Could not inspect neighbors on {0}: {1}" -f $adapter.Name, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    return $addresses
}

Write-Host ''
Write-Host 'AudioBridge diagnostic summary'
Write-Host '=============================='

$manualActions = @()
$ffmpeg = Find-FFmpeg
if ($null -eq $ffmpeg) {
    Write-Host 'FFmpeg present: NO' -ForegroundColor Red
    $manualActions += 'Install FFmpeg (the normal AudioBridge one-liner attempts this automatically).'
    $devices = @()
} else {
    Write-Host ("FFmpeg present: YES ({0})" -f $ffmpeg) -ForegroundColor Green
    $devices = @(Get-DirectShowAudioDevices -FFmpegPath $ffmpeg)
}

Write-Host ''
Write-Host ("Audio capture devices detected: {0}" -f $devices.Count)
if ($devices.Count -eq 0) {
    Write-Host '  None detected.' -ForegroundColor Red
    if ($null -ne $ffmpeg) {
        $manualActions += 'Enable Stereo Mix or install/configure VoiceMeeter so Windows exposes system audio as a recording device.'
    }
} else {
    $preferredDevices = @($devices | Where-Object { $_ -match '(?i)virtual-audio-capturer|VoiceMeeter.*Output|Stereo Mix|What U Hear|Wave Out Mix|Loopback' })
    foreach ($device in $devices) {
        $marker = if ($preferredDevices -contains $device) { '  <-- likely system audio' } else { '' }
        Write-Host ("  - {0}{1}" -f $device, $marker)
    }
    if ($preferredDevices.Count -eq 0) {
        $manualActions += 'Choose a capture source manually, or enable a recognized system-audio source such as Stereo Mix or VoiceMeeter Output.'
    } elseif ($preferredDevices.Count -gt 1) {
        $manualActions += 'Choose which detected system-audio capture source to use.'
    }
}

Write-Host ''
Write-Host 'Network interfaces detected:'
try {
    $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Sort-Object ifIndex)
} catch {
    $adapters = @()
    Write-Host ("  Unable to query network adapters: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $manualActions += 'Run PowerShell with permission to query Windows network adapters.'
}

$localAddresses = @()
if ($adapters.Count -eq 0) {
    Write-Host '  None reported.' -ForegroundColor Red
} else {
    foreach ($adapter in $adapters) {
        try {
            $addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.IPAddress -ne '127.0.0.1' } |
                Select-Object -ExpandProperty IPAddress)
        } catch {
            $addresses = @()
        }
        foreach ($address in $addresses) {
            if ($localAddresses -notcontains $address) { $localAddresses += $address }
        }
        $addressText = if ($addresses.Count -gt 0) { $addresses -join ', ' } else { 'no IPv4 address' }
        Write-Host ("  [{0}] {1} | {2} | IPv4: {3}" -f $adapter.ifIndex, $adapter.Name, $adapter.Status, $addressText)
    }
}

$panAdapters = @(Get-BluetoothPanAdapters -Adapters $adapters)
Write-Host ''
if ($panAdapters.Count -eq 0) {
    Write-Host 'Bluetooth/PAN interface: NOT DETECTED' -ForegroundColor Yellow
    Write-Host '  This is not fatal. AudioBridge can use Wi-Fi or Ethernet when the Windows PC can reach the Mac IPv4 address.'
} else {
    Write-Host ("Bluetooth/PAN interfaces detected: {0}" -f $panAdapters.Count)
    foreach ($adapter in $panAdapters) {
        $stateColor = if ($adapter.Status -eq 'Up') { 'Green' } else { 'Yellow' }
        Write-Host ("  [{0}] {1} | {2}" -f $adapter.ifIndex, $adapter.Name, $adapter.Status) -ForegroundColor $stateColor
    }
    if (@($panAdapters | Where-Object { $_.Status -eq 'Up' }).Count -eq 0) {
        Write-Host '  A PAN-capable interface exists, but none is currently connected.' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'IPv4 default routes detected:'
try {
    $routes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
        Sort-Object RouteMetric, ifIndex)
} catch {
    $routes = @()
    Write-Host ("  Unable to query routes: {0}" -f $_.Exception.Message) -ForegroundColor Red
}
if ($routes.Count -eq 0) {
    Write-Host '  None reported.' -ForegroundColor Yellow
} else {
    foreach ($route in $routes) {
        $adapter = $adapters | Where-Object { $_.ifIndex -eq $route.ifIndex } | Select-Object -First 1
        $adapterName = if ($null -ne $adapter) { $adapter.Name } else { 'unknown interface' }
        Write-Host ("  [{0}] {1} -> {2} | metric {3}" -f $route.ifIndex, $adapterName, $route.NextHop, $route.RouteMetric)
    }
}

$tailscale = Find-Tailscale
$tailscaleCandidates = @()
Write-Host ''
if ($null -eq $tailscale) {
    Write-Host 'Tailscale transport: NOT DETECTED' -ForegroundColor Yellow
    Write-Host '  This is optional when both computers can reach each other through LAN or Bluetooth/PAN.'
} else {
    $tailscaleIP = (& $tailscale ip -4 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($tailscaleIP)) {
        Write-Host 'Tailscale transport: installed but not connected' -ForegroundColor Yellow
    } else {
        Write-Host ("Tailscale transport: connected as {0}" -f $tailscaleIP) -ForegroundColor Green
        $tailscaleCandidates = @(Get-TailscaleMacCandidates -TailscalePath $tailscale)
        if ($tailscaleCandidates.Count -gt 0) {
            Write-Host ("  Online Mac peers: {0}" -f ($tailscaleCandidates -join ', '))
        } else {
            Write-Host '  No unique online Mac peer was detected.' -ForegroundColor Yellow
        }
    }
}

if ([string]::IsNullOrWhiteSpace($MacIP) -and -not [string]::IsNullOrWhiteSpace($env:AUDIOBRIDGE_MAC_IP)) {
    $MacIP = $env:AUDIOBRIDGE_MAC_IP
}

$destination = $null
$destinationSource = $null
if (-not [string]::IsNullOrWhiteSpace($MacIP)) {
    if (Test-UsableIPv4 $MacIP) {
        $destination = $MacIP
        $destinationSource = 'explicit AUDIOBRIDGE_MAC_IP or -MacIP value'
    } else {
        $manualActions += ("Replace the invalid Mac destination '{0}' with a usable IPv4 address." -f $MacIP)
    }
}

if ($null -eq $destination) {
    if ($tailscaleCandidates.Count -eq 1) {
        $destination = $tailscaleCandidates[0]
        $destinationSource = 'single online Mac peer in Tailscale'
    } elseif ($tailscaleCandidates.Count -gt 1) {
        $manualActions += 'Choose the Mac IPv4 address because more than one online Mac was detected in Tailscale.'
    }
}

if ($null -eq $destination) {
    $neighborCandidates = @(Get-PanNeighborCandidates -PanAdapters $panAdapters -LocalAddresses $localAddresses)
    if ($neighborCandidates.Count -eq 1) {
        $destination = $neighborCandidates[0]
        $destinationSource = 'single usable neighbor on an active Bluetooth/PAN interface'
    } elseif ($neighborCandidates.Count -gt 1) {
        Write-Host ''
        Write-Host ("Bluetooth/PAN neighbor candidates: {0}" -f ($neighborCandidates -join ', '))
        $manualActions += 'Choose the Mac IPv4 address because more than one Bluetooth/PAN neighbor was detected.'
    }
}

Write-Host ''
if ($null -ne $destination) {
    Write-Host ("Candidate Mac destination: {0} ({1})" -f $destination, $destinationSource) -ForegroundColor Green
} else {
    Write-Host 'Candidate Mac destination: NOT DETECTED' -ForegroundColor Yellow
    $manualActions += 'Enter a Mac IPv4 address shown by the Mac receiver; it may be on Wi-Fi, Ethernet, Tailscale, or a connected Bluetooth/PAN interface.'
}

Write-Host ''
if ($manualActions.Count -eq 0) {
    Write-Host 'Automatic checks are ready.' -ForegroundColor Green
    exit 0
}

Write-Host 'Manual action or input required:' -ForegroundColor Yellow
foreach ($action in $manualActions) {
    Write-Host ("  - {0}" -f $action) -ForegroundColor Yellow
}

if ($PauseOnManualAction) {
    Write-Host ''
    try {
        [void](Read-Host 'Press Enter after reviewing the diagnostic summary')
    } catch {
        Write-Host 'The console is not interactive, so the pause could not be shown.' -ForegroundColor Yellow
    }
}
exit 2
