//
//  ScannedHost.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation

nonisolated struct ScannedHost: Identifiable, Sendable, Codable {
    let id: String
    let ipAddress: String
    var hostname: String?
    var macAddress: String?
    var vendor: String?
    var isOnline: Bool
    var latencyMs: Double?
    var openPorts: [PortInfo] = []
    var lastSeen: Date

    /// Numeric sort key for natural IP ordering
    var ipSortKey: UInt32 {
        let parts = ipAddress.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return 0 }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    // Sort keys — empty values sort last (zzz prefix)
    var hostnameSortKey: String { hostname?.lowercased() ?? "\u{FFFF}" }
    var macSortKey: String { macAddress ?? "\u{FFFF}" }
    var vendorSortKey: String { vendor?.lowercased() ?? "\u{FFFF}" }
    var latencySortKey: Double { latencyMs ?? Double.infinity }

    /// Formatted latency string
    var latencyString: String? {
        guard let ms = latencyMs else { return nil }
        if ms < 1 {
            return String(format: "%.2f ms", ms)
        } else {
            return String(format: "%.1f ms", ms)
        }
    }
}
