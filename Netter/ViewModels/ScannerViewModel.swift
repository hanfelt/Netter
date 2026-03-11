//
//  ScannerViewModel.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation
import Observation

@Observable
final class ScannerViewModel {

    // MARK: - State

    var interfaces: [NetworkInterface] = []
    var selectedInterface: NetworkInterface?
    var hosts: [ScannedHost] = []
    var selectedHostID: String?
    var scanState: ScanState = .idle
    var showOnlineOnly: Bool = true
    var sortOrder: [KeyPathComparator<ScannedHost>] = [
        .init(\.ipSortKey, order: .forward)
    ]

    // MARK: - Private

    private var scanTask: Task<Void, Never>?
    /// Cache of scan results per interface id
    private var resultsCache: [String: (hosts: [ScannedHost], state: ScanState)] = [:]

    // MARK: - Computed Properties

    var selectedHost: ScannedHost? {
        guard let id = selectedHostID else { return nil }
        return hosts.first(where: { $0.id == id })
    }

    var filteredHosts: [ScannedHost] {
        let base = showOnlineOnly ? hosts.filter(\.isOnline) : hosts
        return base.sorted(using: sortOrder)
    }

    var onlineCount: Int {
        hosts.filter(\.isOnline).count
    }

    // MARK: - Actions

    func loadInterfaces() {
        interfaces = NetworkInterfaceService.discoverInterfaces()
        if selectedInterface == nil {
            selectedInterface = interfaces.first
        }
    }

    /// Add a custom network from CIDR string and select it
    func addCustomNetwork(_ cidr: String) -> Bool {
        guard let iface = NetworkInterface.fromCIDR(cidr) else {
            return false
        }
        // Remove any previous custom network with the same CIDR
        interfaces.removeAll { $0.id == iface.id }
        interfaces.append(iface)
        selectInterface(iface)
        return true
    }

    func selectInterface(_ interface: NetworkInterface?) {
        if selectedInterface != interface {
            stopScan()

            // Save current results to cache
            if let current = selectedInterface {
                resultsCache[current.id] = (hosts: hosts, state: scanState)
            }

            selectedInterface = interface
            selectedHostID = nil

            // Restore cached results or reset
            if let iface = interface, let cached = resultsCache[iface.id] {
                hosts = cached.hosts
                scanState = cached.state
            } else {
                hosts = []
                scanState = .idle
            }
        }
    }

    func startScan() {
        guard let interface = selectedInterface else { return }
        guard !scanState.isScanning else { return }

        scanTask = Task {
            await performScan(on: interface)
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        if scanState.isScanning {
            scanState = .idle
        }
    }

    // MARK: - Private Methods

    private func performScan(on interface: NetworkInterface) async {
        let ips = interface.scannableIPs
        let startTime = Date()
        hosts = []
        resultsCache.removeValue(forKey: interface.id)
        scanState = .scanning(progress: ScanProgress(
            currentIP: "",
            scannedCount: 0,
            totalCount: ips.count
        ))

        // Step 1: Ping all hosts concurrently
        let pingResults = await PingService.scanHosts(ips, maxConcurrent: 50) { currentIP, count in
            await MainActor.run {
                self.scanState = .scanning(progress: ScanProgress(
                    currentIP: currentIP,
                    scannedCount: count,
                    totalCount: ips.count
                ))
            }
        }

        // Check for cancellation
        if Task.isCancelled {
            scanState = .idle
            return
        }

        // Step 2: Build host list from ping results (only online hosts for cleaner results)
        hosts = pingResults.map { ip, result in
            ScannedHost(
                id: ip,
                ipAddress: ip,
                isOnline: result.isAlive,
                latencyMs: result.latencyMs,
                lastSeen: Date()
            )
        }

        // Check for cancellation
        if Task.isCancelled {
            scanState = .idle
            return
        }

        // Step 3: Read ARP table for MAC addresses and hostnames
        // The ARP cache is populated by the ping sweep, so hosts that responded
        // will have entries even if the ping exit code was non-zero (e.g. ICMP blocked but ARP replied)
        let arpEntries = await ARPService.readARPTable()
        for entry in arpEntries {
            if let index = hosts.firstIndex(where: { $0.ipAddress == entry.ipAddress }) {
                hosts[index].macAddress = entry.macAddress
                if let hostname = entry.hostname {
                    hosts[index].hostname = hostname
                }
                if let mac = hosts[index].macAddress {
                    hosts[index].vendor = OUILookup.vendor(for: mac)
                }
                // If we have a valid ARP entry (MAC address), the host is reachable
                // even if ICMP ping was blocked or timed out
                if !hosts[index].isOnline {
                    hosts[index].isOnline = true
                    hosts[index].lastSeen = Date()
                }
            }
        }

        // Check for cancellation
        if Task.isCancelled {
            scanState = .idle
            return
        }

        // Step 4: Re-ping online hosts that lack latency data (found via ARP only)
        // This gives them a second chance with a direct ping for accurate latency
        let hostsNeedingLatency = hosts.filter { $0.isOnline && $0.latencyMs == nil }
        if !hostsNeedingLatency.isEmpty {
            await withTaskGroup(of: (String, Double?).self) { group in
                for host in hostsNeedingLatency {
                    group.addTask {
                        let result = await PingService.ping(host.ipAddress, timeout: 2)
                        return (host.ipAddress, result.latencyMs)
                    }
                }
                for await (ip, latencyMs) in group {
                    if let index = hosts.firstIndex(where: { $0.ipAddress == ip }) {
                        hosts[index].latencyMs = latencyMs
                    }
                }
            }
        }

        // Check for cancellation
        if Task.isCancelled {
            scanState = .idle
            return
        }

        // Step 5: Resolve hostnames for online hosts that don't have one yet
        await withTaskGroup(of: (String, String?).self) { group in
            for host in hosts where host.isOnline && host.hostname == nil {
                group.addTask {
                    let hostname = await HostnameResolver.resolve(host.ipAddress)
                    return (host.ipAddress, hostname)
                }
            }
            for await (ip, hostname) in group {
                if let index = hosts.firstIndex(where: { $0.ipAddress == ip }),
                   let hostname = hostname {
                    hosts[index].hostname = hostname
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        scanState = .completed(duration: duration)

        // Cache results for this interface
        if let iface = selectedInterface {
            resultsCache[iface.id] = (hosts: hosts, state: scanState)
        }
    }
}
