//
//  NetworkInterface.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation

nonisolated struct NetworkInterface: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let displayName: String
    let ipAddress: String
    let subnetMask: String

    var iconName: String {
        if name == "custom" {
            return "globe"
        } else if name == "en0" || displayName.lowercased().contains("wi-fi") {
            return "wifi"
        } else if displayName.lowercased().contains("ethernet") || displayName.lowercased().contains("thunderbolt") {
            return "cable.connector.horizontal"
        } else {
            return "network"
        }
    }

    /// Number of scannable hosts in the subnet
    var hostCount: Int {
        let mask = ipToUInt32(subnetMask)
        let hostBits = ~mask
        let count = Int(hostBits) - 1
        return max(count, 0)
    }

    /// All scannable IP addresses in the subnet (excludes network and broadcast)
    var scannableIPs: [String] {
        let ip = ipToUInt32(ipAddress)
        let mask = ipToUInt32(subnetMask)
        let network = ip & mask
        let broadcast = network | ~mask

        guard broadcast > network + 1 else { return [] }

        return ((network + 1)..<broadcast).map { uint32ToIP($0) }
    }

    /// Subnet in CIDR notation (e.g. "192.168.1.0/24")
    var cidrNotation: String {
        let ip = ipToUInt32(ipAddress)
        let mask = ipToUInt32(subnetMask)
        let network = ip & mask
        let prefix = mask.nonzeroBitCount
        return "\(uint32ToIP(network))/\(prefix)"
    }

    /// Create a NetworkInterface from CIDR notation (e.g. "192.168.1.0/24" or "10.0.0.0/16")
    static func fromCIDR(_ cidr: String, name: String? = nil) -> NetworkInterface? {
        let parts = cidr.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard parts.count == 2,
              let prefixLength = Int(parts[1]),
              prefixLength >= 8 && prefixLength <= 30 else {
            return nil
        }

        let ipStr = String(parts[0])
        let octets = ipStr.split(separator: ".").compactMap { UInt32($0) }
        guard octets.count == 4, octets.allSatisfy({ $0 <= 255 }) else {
            return nil
        }

        // Build subnet mask from prefix length
        let maskValue: UInt32 = prefixLength == 0 ? 0 : ~((1 << (32 - prefixLength)) - 1)
        let mask = "\((maskValue >> 24) & 0xFF).\((maskValue >> 16) & 0xFF).\((maskValue >> 8) & 0xFF).\(maskValue & 0xFF)"

        let displayName = (name?.isEmpty == false) ? name! : cidr

        return NetworkInterface(
            id: "custom-\(cidr)",
            name: "custom",
            displayName: displayName,
            ipAddress: ipStr,
            subnetMask: mask
        )
    }

    private func ipToUInt32(_ ip: String) -> UInt32 {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return 0 }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    private func uint32ToIP(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}
