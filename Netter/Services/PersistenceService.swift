//
//  PersistenceService.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-12.
//

import Foundation

/// Persists custom networks and their scan results between launches
nonisolated enum PersistenceService: Sendable {

    private static let customNetworksKey = "customNetworks"
    private static let scanResultsKey = "scanResults"

    // MARK: - Custom Networks

    struct SavedNetwork: Codable {
        let cidr: String
        let name: String?
    }

    static func loadCustomNetworks() -> [SavedNetwork] {
        // Try new format first (array of SavedNetwork)
        if let data = UserDefaults.standard.data(forKey: customNetworksKey),
           let networks = try? JSONDecoder().decode([SavedNetwork].self, from: data) {
            return networks
        }
        // Fall back to old format (array of CIDR strings)
        if let cidrs = UserDefaults.standard.stringArray(forKey: customNetworksKey) {
            return cidrs.map { SavedNetwork(cidr: $0, name: nil) }
        }
        return []
    }

    static func saveCustomNetworks(_ networks: [SavedNetwork]) {
        if let data = try? JSONEncoder().encode(networks) {
            UserDefaults.standard.set(data, forKey: customNetworksKey)
        }
    }

    // MARK: - Scan Results

    /// Save scan results for a given interface id
    static func saveScanResults(_ hosts: [ScannedHost], for interfaceID: String) {
        var all = loadAllScanResults()
        all[interfaceID] = hosts
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: scanResultsKey)
        }
    }

    /// Load scan results for a given interface id
    static func loadScanResults(for interfaceID: String) -> [ScannedHost]? {
        let all = loadAllScanResults()
        return all[interfaceID]
    }

    /// Remove scan results for a given interface id
    static func removeScanResults(for interfaceID: String) {
        var all = loadAllScanResults()
        all.removeValue(forKey: interfaceID)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: scanResultsKey)
        }
    }

    private static func loadAllScanResults() -> [String: [ScannedHost]] {
        guard let data = UserDefaults.standard.data(forKey: scanResultsKey),
              let results = try? JSONDecoder().decode([String: [ScannedHost]].self, from: data) else {
            return [:]
        }
        return results
    }
}
