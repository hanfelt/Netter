//
//  NetworkInterfaceService.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation
import Darwin
import SystemConfiguration

enum NetworkInterfaceService: Sendable {

    /// Discover all active IPv4 network interfaces with valid IP addresses
    nonisolated static func discoverInterfaces() -> [NetworkInterface] {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            return []
        }
        defer { freeifaddrs(ifaddrPtr) }

        var interfaces: [NetworkInterface] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let ifaddr = ptr {
            let addr = ifaddr.pointee
            ptr = addr.ifa_next

            // Only IPv4
            guard let addrFamily = addr.ifa_addr?.pointee.sa_family,
                  addrFamily == sa_family_t(AF_INET) else {
                continue
            }

            let name = String(cString: addr.ifa_name)

            // Skip loopback
            if name == "lo0" { continue }

            // Extract IP address
            guard let ipAddr = addr.ifa_addr else { continue }
            let ip = socketAddressToString(ipAddr)

            // Skip invalid IPs
            if ip == "0.0.0.0" || ip.hasPrefix("127.") { continue }

            // Extract subnet mask
            guard let maskAddr = addr.ifa_netmask else { continue }
            let mask = socketAddressToString(maskAddr)

            // Skip if mask is all zeros
            if mask == "0.0.0.0" { continue }

            let display = displayName(for: name)

            let iface = NetworkInterface(
                id: name,
                name: name,
                displayName: display,
                ipAddress: ip,
                subnetMask: mask
            )

            // Only include interfaces with more than 0 scannable hosts
            if iface.hostCount > 0 {
                interfaces.append(iface)
            }
        }

        return interfaces
    }

    /// Convert a sockaddr pointer to an IP address string
    private nonisolated static func socketAddressToString(_ addr: UnsafeMutablePointer<sockaddr>) -> String {
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(
            addr,
            socklen_t(addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil, 0,
            NI_NUMERICHOST
        )
        return String(cString: hostname)
    }

    /// Get a human-readable display name for a BSD network interface name
    private nonisolated static func displayName(for bsdName: String) -> String {
        if let allInterfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for iface in allInterfaces {
                if let name = SCNetworkInterfaceGetBSDName(iface) as String?,
                   name == bsdName,
                   let localizedName = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? {
                    return localizedName
                }
            }
        }

        // Fallback heuristics
        if bsdName == "en0" { return "Wi-Fi" }
        if bsdName.hasPrefix("en") { return "Ethernet (\(bsdName))" }
        if bsdName.hasPrefix("bridge") { return "Bridge (\(bsdName))" }
        if bsdName.hasPrefix("utun") { return "VPN Tunnel (\(bsdName))" }
        return bsdName
    }
}
