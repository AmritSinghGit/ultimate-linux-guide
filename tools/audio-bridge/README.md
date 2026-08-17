# Windows to Mac AudioBridge

The bootstraps always refresh `Downloads/AudioBridge` from the
`audio-bridge-bootstrap` branch before they run. A Bluetooth/PAN connection is
optional: Wi-Fi, Ethernet, or the Tailscale fallback also works when Windows can
reach the Mac IPv4 address printed by the receiver.

## Mac receiver

```bash
curl -fsSL https://raw.githubusercontent.com/AmritSinghGit/ultimate-linux-guide/audio-bridge-bootstrap/tools/audio-bridge/install-mac.sh | bash
```

## Windows sender

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/AmritSinghGit/ultimate-linux-guide/audio-bridge-bootstrap/tools/audio-bridge/install-windows.ps1 | iex
```

The Windows bootstrap prints a diagnostic summary before streaming. It reports
FFmpeg, capture devices, network interfaces, default routes, Bluetooth/PAN and
Tailscale state, and any safely detected candidate Mac destination. When automatic
detection is incomplete, it pauses and asks for the required input instead of
closing the console.

## Windows diagnostics only

This refreshes the same files and prints the report without installing FFmpeg
or starting a stream:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/AmritSinghGit/ultimate-linux-guide/audio-bridge-bootstrap/tools/audio-bridge/install-windows.ps1))) -Diagnostic
```

To provide an explicit destination for diagnostics and future sender runs:

```powershell
$env:AUDIOBRIDGE_MAC_IP = '192.0.2.10'
```

Replace the example with an IPv4 address actually printed by the Mac receiver.
