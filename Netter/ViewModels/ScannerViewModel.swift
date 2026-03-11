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

        // ── Phase 1: Ping sweep ─────────────────────────────────────────
        let pingResults = await PingService.scanHosts(ips, maxConcurrent: 50) { currentIP, count in
            await MainActor.run {
                self.scanState = .scanning(progress: ScanProgress(
                    currentIP: currentIP,
                    scannedCount: count,
                    totalCount: ips.count
                ))
            }
        }

        if Task.isCancelled { scanState = .idle; return }

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

        if Task.isCancelled { scanState = .idle; return }

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
                    if let index = hosts.firstIndex(where: { $0.ipAddress == ip }) {
                        hosts[index].latencyMs = latencyMs
                    }
                }
            }
        }

        if Task.isCancelled { scanState = .idle; return }

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

        if Task.isCancelled { scanState = .idle; return }

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

        if Task.isCancelled { scanState = .idle; return }

        let duration = Date().timeIntervalSince(startTime)
        scanState = .completed(duration: duration)

        // Cache results
        if let iface = selectedInterface {
            resultsCache[iface.id] = (hosts: hosts, state: scanState)
        }
    }
}
