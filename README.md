# Netter

A native macOS network scanner built with SwiftUI. Discover hosts on your local network, identify devices by vendor, scan ports, and inspect services — all from a clean, modern interface.

## Features

- **Network Interface Detection** — Automatically discovers Wi-Fi, Ethernet, and other active interfaces. Add custom IP ranges for VPNs or remote subnets.
- **Host Discovery** — Concurrent ICMP ping sweep with up to 50 simultaneous probes. See hosts appear in real-time as they respond.
- **Port Scanning** — Scan common ports with TCP connect and banner grabbing for service identification.
- **MAC Address & Vendor Lookup** — Reads the ARP table after scanning and identifies manufacturers from a bundled OUI database with 28,000+ vendor entries.
- **Device Type Inference** — Classifies devices as routers, printers, NAS, phones, servers, IoT devices, and more based on vendor name and open port signatures.
- **Vendor Icons** — Maps ~40 common vendors to SF Symbol icons for quick visual identification.
- **Hostname Resolution** — Reverse DNS lookup for all discovered hosts.
- **Sortable Columns** — Click any column header to sort by IP, hostname, MAC, vendor, or latency.
- **Search & Filter** — Filter results by any field. Toggle to show only online hosts.
- **Named Scans** — Save scan results with custom names and reload them later.
- **Copy Support** — Right-click any cell to copy its value to the clipboard.
- **Host Inspector** — Side panel with detailed information about the selected host including all open ports and services.

## Screenshots

<img width="1210" height="125" alt="CleanShot 2026-03-12 at 12 03 35" src="https://github.com/user-attachments/assets/3b59d566-7dc3-4016-bed2-1d410631e78c" />

## Requirements

- macOS 14.0 (Sonoma) or later

## Installation

### Download

1. Download `Netter.app.zip` from the [latest release](../../releases/latest)
2. Unzip and move `Netter.app` to your Applications folder
3. On first launch: right-click the app → **Open** (required for unsigned apps)

### Build from Source

1. Clone the repository:
   ```
   git clone https://github.com/hanfelt/Netter.git
   ```
2. Open `Netter.xcodeproj` in Xcode 15 or later
3. Build and run (⌘R)

## How It Works

Netter uses standard macOS system tools — no root access required:

| Feature | Method |
|---|---|
| Ping | `/sbin/ping` via `Process` |
| ARP table | `/usr/sbin/arp -a` via `Process` |
| Hostname | `getnameinfo()` reverse DNS |
| Vendor lookup | Bundled IEEE OUI JSON database |
| Port scan | Swift NIO-free TCP `connect()` |

App Sandbox is disabled to allow access to these system utilities.

## Architecture

```
Models/
  NetworkInterface.swift     Network interface (name, IP, subnet, scannable IPs)
  ScannedHost.swift          Discovered host (IP, hostname, MAC, vendor, device type)
  ScanState.swift            Scan lifecycle (idle → scanning → completed)
  PortInfo.swift             Port scan result (port, service, banner)

Services/
  NetworkInterfaceService    getifaddrs() + SystemConfiguration
  PingService                Concurrent ping via TaskGroup
  ARPService                 ARP table parsing
  HostnameResolver           Reverse DNS via getnameinfo()
  OUILookup                  Vendor lookup from bundled OUI database
  PortScannerService         TCP connect scan with banner grabbing
  PersistenceService         Save/load named scans

ViewModels/
  ScannerViewModel           @Observable orchestrator for scan lifecycle

Views/
  SidebarView                Interface selector + saved scans
  ScanResultsView            Sortable table with search
  ScanToolbar                Scan/stop controls and filters
  StatusBarView              Progress and summary
  HostDetailView             Inspector panel for selected host
```

## Tech Stack

- **Swift 6** with strict concurrency
- **SwiftUI** with `NavigationSplitView`, `Table`, and `.inspector()`
- **Structured concurrency** via `TaskGroup` with sliding window pattern
- **@Observable** (Observation framework) for state management
- No third-party dependencies

## License

MIT

## Author

Andreas Hanfelt
