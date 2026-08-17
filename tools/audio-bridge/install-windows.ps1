[CmdletBinding()]
param(
    [switch]$Diagnostic
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$BaseUrl = 'https://raw.githubusercontent.com/AmritSinghGit/ultimate-linux-guide/audio-bridge-bootstrap/tools/audio-bridge'
$Root = Join-Path $env:USERPROFILE 'Downloads\AudioBridge'
$TempRoot = Join-Path $env:TEMP ('AudioBridge-' + [Guid]::NewGuid().ToString('N'))

Write-Host ''
Write-Host 'AudioBridge bootstrap (Windows)'
Write-Host '==============================='

function Wait-AudioBridge {
    param([string]$Reason)

    Write-Host ''
    Write-Host $Reason -ForegroundColor Yellow
    try {
        [void](Read-Host 'Press Enter to continue')
    } catch {
        Write-Host 'The console is not interactive, so the pause could not be shown.' -ForegroundColor Yellow
    }
}

function Invoke-AudioBridgeScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @()
    )

    # Keep child output visible instead of letting assignment of this function's
    # return value capture and hide the diagnostic/setup text.
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments | Out-Host
    $exitCode = $LASTEXITCODE
    return $exitCode
}

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    $payloads = @('SETUP_WINDOWS.ps1', 'SEND_AUDIO.ps1', 'DIAGNOSE_WINDOWS.ps1')
    foreach ($payload in $payloads) {
        Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/$payload" -OutFile (Join-Path $TempRoot $payload)
    }

    # Do not delete the directory a shell may currently be standing in. Replace
    # only the managed files after every download has completed successfully.
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    foreach ($payload in $payloads) {
        Copy-Item -LiteralPath (Join-Path $TempRoot $payload) -Destination (Join-Path $Root $payload) -Force
    }

    Write-Host "Refreshed safely: $Root" -ForegroundColor Green

    $diagnosePath = Join-Path $Root 'DIAGNOSE_WINDOWS.ps1'
    if ($Diagnostic) {
        Write-Host 'Running diagnostics only; setup and streaming will not be started.'
        $diagnosticCode = Invoke-AudioBridgeScript -Path $diagnosePath -Arguments @('-PauseOnManualAction')
        if ($diagnosticCode -ne 0 -and $diagnosticCode -ne 2) {
            throw "Diagnostics exited with code $diagnosticCode."
        }
        Write-Host ''
        Write-Host 'Diagnostic-only mode complete. This window will remain open.' -ForegroundColor Green
    } else {
        Write-Host 'Running setup and a diagnostic summary before starting the sender...'

        $setupCode = Invoke-AudioBridgeScript -Path (Join-Path $Root 'SETUP_WINDOWS.ps1')
        if ($setupCode -ne 0) {
            throw "Windows setup exited with code $setupCode."
        }

        $diagnosticCode = Invoke-AudioBridgeScript -Path $diagnosePath
        if ($diagnosticCode -eq 2) {
            Wait-AudioBridge 'Manual action or input is required. Review the diagnostic summary above; the interactive sender will ask for any missing device or Mac IPv4 address.'
        } elseif ($diagnosticCode -ne 0) {
            throw "Diagnostics exited with code $diagnosticCode."
        }

        $senderCode = Invoke-AudioBridgeScript -Path (Join-Path $Root 'SEND_AUDIO.ps1')
        if ($senderCode -ne 0) {
            throw "Audio sender exited with code $senderCode."
        }
    }
} catch {
    Write-Host ''
    Write-Host 'AudioBridge could not continue.' -ForegroundColor Red
    Write-Host ("Reason: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Downloaded files (if available): {0}" -f $Root)
    Write-Host 'You can rerun the diagnostic-only one-liner after correcting the problem.'
    Wait-AudioBridge 'The console is being kept open so the error can be read.'
} finally {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'AudioBridge finished. PowerShell remains open.' -ForegroundColor Cyan
