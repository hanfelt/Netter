//
//  OUILookup.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation

/// Entry from mac-vendors-export.json
private nonisolated struct MACVendorEntry: Decodable, Sendable {
    let macPrefix: String
    let vendorName: String
}

nonisolated enum OUILookup: Sendable {

    /// Shared lookup dictionary loaded once from the bundled MAC vendors database
    private static let database: [String: String] = {
        guard let url = Bundle.main.url(forResource: "mac-vendors-export", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([MACVendorEntry].self, from: data)
        else {
            return [:]
        }
        // Build a dictionary keyed by uppercase MAC prefix (e.g. "00:00:0C" -> "Cisco Systems, Inc")
        var dict: [String: String] = [:]
        dict.reserveCapacity(entries.count)
        for entry in entries {
            dict[entry.macPrefix.uppercased()] = entry.vendorName
        }
        return dict
    }()

    /// Look up the vendor/manufacturer for a given MAC address
    /// Accepts any format: "AA:BB:CC:DD:EE:FF", "aa:bb:cc:dd:ee:ff", "aa-bb-cc-dd-ee-ff"
    nonisolated static func vendor(for macAddress: String) -> String? {
        let cleaned = macAddress
            .uppercased()
            .replacingOccurrences(of: "-", with: ":")

        let components = cleaned.split(separator: ":")
        guard components.count >= 3 else { return nil }

        // Zero-pad each octet and take first 3
        let prefix = components.prefix(3)
            .map { component in
                let hex = String(component)
                return hex.count == 1 ? "0\(hex)" : hex
            }
            .joined(separator: ":")

        return database[prefix]
    }
}
