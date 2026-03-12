//
//  ScannerViewModel.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation
import Observation
import SwiftUI

@Observable
final class ScannerViewModel {

    // MARK: - State

    var interfaces: [NetworkInterface] = []
    var selectedInterface: NetworkInterface?
    var hosts: [ScannedHost] = []
    var selectedHostID: String?
    var scanState: ScanState = .idle
    var showOnlineOnly: Bool = true
    var searchText: String = ""
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
        var base = showOnlineOnly ? hosts.filter(\.isOnline) : hosts

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            base = base.filter { host in
                host.ipAddress.lowercased().contains(query)
                || (host.hostname?.lowercased().contains(query) ?? false)
                || (host.macAddress?.lowercased().contains(query) ?? false)
                || (host.vendor?.lowercased().contains(query) ?? false)
            }
        }

        return base.sorted(using: sortOrder)
    }

    var onlineCount: Int {
        hosts.filter(\.isOnline).count
    }

    // MARK: - Actions

    func loadInterfaces() {
        interfaces = NetworkInterfaceService.discoverInterfaces()

        // Restore saved custom networks
        let savedNetworks = PersistenceService.loadCustomNetworks()
        for network in savedNetworks {
            if let iface = NetworkInterface.fromCIDR(network.cidr, name: network.name) {
                if !interfaces.contains(where: { $0.id == iface.id }) {
                    interfaces.append(iface)
                }
                // Restore cached scan results from disk
                if let savedHosts = PersistenceService.loadScanResults(for: iface.id) {
                    resultsCache[iface.id] = (hosts: savedHosts, state: .idle)
                }
            }
        }

        if selectedInterface == nil {
            selectedInterface = interfaces.first
        }
    }

    /// Add a custom network from CIDR string with optional name and select it
    func addCustomNetwork(_ cidr: String, name: String? = nil) -> Bool {
        guard let iface = NetworkInterface.fromCIDR(cidr, name: name) else {
            return false
        }
        // Remove any previous custom network with the same CIDR
        interfaces.removeAll { $0.id == iface.id }
        interfaces.append(iface)
        persistCustomNetworks()
        selectInterface(iface)
        return true
    }

    /// Remove a custom network and its saved results
    func removeCustomNetwork(_ interface: NetworkInterface) {
        let wasSelected = selectedInterface == interface

        // Clear cache and persisted results
        resultsCache.removeValue(forKey: interface.id)
        PersistenceService.removeScanResults(for: interface.id)

        interfaces.removeAll { $0.id == interface.id }
        persistCustomNetworks()

        if wasSelected {
            selectInterface(interfaces.first)
        }
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

    private func persistCustomNetworks() {
        let networks = interfaces
            .filter { $0.id.hasPrefix("custom-") }
            .map { iface in
                let cidr = iface.id.replacingOccurrences(of: "custom-", with: "")
                // Only save the name if it differs from the CIDR (i.e. user gave a custom name)
                let name = (iface.displayName != cidr) ? iface.displayName : nil
                return PersistenceService.SavedNetwork(cidr: cidr, name: name)
            }
        PersistenceService.saveCustomNetworks(networks)
    }

    private func performScan(on interface: NetworkInterface) async {
        let interfaceID = interface.id
        let ips = interface.scannableIPs
        let startTime = Date()
        hosts = []
        resultsCache.removeValue(forKey: interfaceID)
        scanState = .scanning(progress: ScanProgress(
            currentIP: "",
            scannedCount: 0,
            totalCount: ips.count
        ))

        // ── Phase 1: Ping sweep ─────────────────────────────────────────
        let pingResults = await PingService.scanHosts(ips, maxConcurrent: 50) { currentIP, count in
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.selectedInterface?.id == interfaceID else { return }
                self.scanState = .scanning(progress: ScanProgress(
                    currentIP: currentIP,
                    scannedCount: count,
                    totalCount: ips.count
                ))
            }
        }

        guard !Task.isCancelled, selectedInterface?.id == interfaceID else { return }

        // Build host list
        withAnimation(.easeInOut(duration: 0.3)) {
            hosts = pingResults.map { ip, result in
                ScannedHost(
                    id: ip,
                    ipAddress: ip,
                    isOnline: result.isAlive,
                    latencyMs: result.latencyMs,
                    lastSeen: Date()
                )
            }
        }

        // ── Phase 2: Enrichment (ARP, hostname, ports) ──────────────────
        let onlineCount = hosts.filter(\.isOnline).count
        scanState = .enriching(progress: EnrichProgress(
            completedCount: 0,
            totalCount: onlineCount,
            currentIP: ""
        ))

        // Step 2a: ARP table → MAC addresses and vendor lookup
        let arpEntries = await ARPService.readARPTable()

        guard !Task.isCancelled, selectedInterface?.id == interfaceID else { return }

        let arpMap = Dictionary(arpEntries.map { ($0.ipAddress, $0) },
                                uniquingKeysWith: { first, _ in first })

        withAnimation(.easeInOut(duration: 0.3)) {
            for i in hosts.indices {
                if let entry = arpMap[hosts[i].ipAddress] {
                    hosts[i].macAddress = entry.macAddress
                    if let hostname = entry.hostname {
                        hosts[i].hostname = hostname
                    }
                    if let mac = hosts[i].macAddress {
                        hosts[i].vendor = OUILookup.vendor(for: mac)
                    }
                    if !hosts[i].isOnline {
                        hosts[i].isOnline = true
                        hosts[i].lastSeen = Date()
                    }
                }
            }
        }

        guard !Task.isCancelled, selectedInterface?.id == interfaceID else { return }

        // Step 2b: Re-ping hosts found only via ARP (no latency yet)
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
                    if Task.isCancelled { group.cancelAll(); return }
                    if let index = hosts.firstIndex(where: { $0.ipAddress == ip }) {
                        hosts[index].latencyMs = latencyMs
                    }
                }
            }
        }

        guard !Task.isCancelled, selectedInterface?.id == interfaceID else { return }

        // Step 2c: Hostname resolution (sliding window of 10)
        var enrichedCount = 0
        let hostsNeedingHostname = hosts.enumerated()
            .filter { $0.element.isOnline && $0.element.hostname == nil }
            .map { (index: $0.offset, ip: $0.element.ipAddress) }

        await withTaskGroup(of: (Int, String?).self) { group in
            var iterator = hostsNeedingHostname.makeIterator()

            for _ in 0..<min(10, hostsNeedingHostname.count) {
                guard let item = iterator.next() else { break }
                group.addTask {
                    let hostname = await HostnameResolver.resolve(item.ip)
                    return (item.index, hostname)
                }
            }

            for await (index, hostname) in group {
                if Task.isCancelled { group.cancelAll(); return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    if let hostname = hostname {
                        hosts[index].hostname = hostname
                    }
                }
                enrichedCount += 1
                scanState = .enriching(progress: EnrichProgress(
                    completedCount: enrichedCount,
                    totalCount: hostsNeedingHostname.count,
                    currentIP: hosts[index].ipAddress
                ))

                if let item = iterator.next() {
                    group.addTask {
                        let hostname = await HostnameResolver.resolve(item.ip)
                        return (item.index, hostname)
                    }
                }
            }
        }

        guard !Task.isCancelled, selectedInterface?.id == interfaceID else { return }

        // Step 2d: Port scan online hosts (sliding window of 5)
        let hostIndicesForPortScan = hosts.indices.filter { hosts[$0].isOnline }
        var portScanCount = 0

        await withTaskGroup(of: (Int, [PortInfo]).self) { group in
            var iterator = hostIndicesForPortScan.makeIterator()

            for _ in 0..<min(5, hostIndicesForPortScan.count) {
                guard let idx = iterator.next() else { break }
                let ip = hosts[idx].ipAddress
                group.addTask {
                    let ports = await PortScannerService.scan(host: ip)
                    return (idx, ports)
                }
            }

            for await (index, ports) in group {
                if Task.isCancelled { group.cancelAll(); return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    hosts[index].openPorts = ports
                }
                portScanCount += 1
                scanState = .enriching(progress: EnrichProgress(
                    completedCount: portScanCount,
                    totalCount: hostIndicesForPortScan.count,
                    currentIP: hosts[index].ipAddress
                ))

                if let idx = iterator.next() {
                    let ip = hosts[idx].ipAddress
                    group.addTask {
                        let ports = await PortScannerService.scan(host: ip)
                        return (idx, ports)
                    }
                }
            }
        }

        guard !Task.isCancelled, selectedInterface?.id == interfaceID else { return }

        let duration = Date().timeIntervalSince(startTime)
        scanState = .completed(duration: duration)

        // Cache results for the scanned interface (use interfaceID, not selectedInterface)
        resultsCache[interfaceID] = (hosts: hosts, state: scanState)
        if interfaceID.hasPrefix("custom-") {
            PersistenceService.saveScanResults(hosts, for: interfaceID)
        }
    }
}
