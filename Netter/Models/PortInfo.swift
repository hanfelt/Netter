//
//  PortInfo.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation

nonisolated struct PortInfo: Identifiable, Sendable {
    let port: UInt16
    let service: String
    let banner: String?

    var id: UInt16 { port }

    /// Human-readable description like "nginx/1.24.0" or just "Open"
    var displayBanner: String {
        banner ?? "Open"
    }
}

/// Well-known ports to scan with their service names
nonisolated enum CommonPorts: Sendable {
    static let all: [(port: UInt16, service: String)] = [
        (22,    "SSH"),
        (53,    "DNS"),
        (80,    "HTTP"),
        (443,   "HTTPS"),
        (445,   "SMB"),
        (548,   "AFP"),
        (631,   "IPP"),
        (3389,  "RDP"),
        (5000,  "UPnP"),
        (5001,  "HTTPS Mgmt"),
        (8080,  "HTTP Proxy"),
        (8443,  "HTTPS Alt"),
        (9090,  "Web Admin"),
        (62078, "iServices"),
    ]

    static func serviceName(for port: UInt16) -> String {
        all.first(where: { $0.port == port })?.service ?? "Port \(port)"
    }
}
