//
//  ScannedHost.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation

/// Inferred device type based on vendor name and open ports
nonisolated enum DeviceType: String, Sendable {
    case router
    case accessPoint
    case printer
    case phone
    case computer
    case server
    case nas
    case iotDevice
    case unknown

    var iconName: String {
        switch self {
        case .router:      return "wifi.router"
        case .accessPoint:  return "wifi"
        case .printer:      return "printer"
        case .phone:        return "iphone"
        case .computer:     return "desktopcomputer"
        case .server:       return "server.rack"
        case .nas:          return "externaldrive.connected.to.line.below"
        case .iotDevice:    return "sensor"
        case .unknown:      return "display"
        }
    }

    var label: String {
        switch self {
        case .router:      return "Router"
        case .accessPoint:  return "AP"
        case .printer:      return "Printer"
        case .phone:        return "Phone"
        case .computer:     return "Computer"
        case .server:       return "Server"
        case .nas:          return "NAS"
        case .iotDevice:    return "IoT"
        case .unknown:      return "Device"
        }
    }
}

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

    /// Inferred device type based on vendor + open ports
    var deviceType: DeviceType {
        let v = vendor?.lowercased() ?? ""
        let portNumbers = Set(openPorts.map(\.port))

        // Router / gateway vendors
        let routerVendors = ["cisco", "ubiquiti", "mikrotik", "netgear", "tp-link",
                             "asus", "linksys", "d-link", "zyxel", "juniper", "aruba",
                             "fortinet", "pfsense", "draytek", "huawei", "sonicwall"]
        if routerVendors.contains(where: { v.contains($0) }) {
            return .router
        }

        // Printers
        let printerVendors = ["hp", "hewlett", "canon", "epson", "brother",
                              "xerox", "ricoh", "lexmark", "konica", "kyocera"]
        if printerVendors.contains(where: { v.contains($0) }) || portNumbers.contains(631) {
            return .printer
        }

        // NAS devices
        let nasVendors = ["synology", "qnap", "western digital", "buffalo", "drobo", "asustor"]
        if nasVendors.contains(where: { v.contains($0) }) {
            return .nas
        }

        // Phones / mobile (iServices port or mobile vendors)
        if portNumbers.contains(62078) {
            return .phone
        }
        let phoneVendors = ["samsung", "xiaomi", "oneplus", "huawei mobile", "oppo", "vivo"]
        if phoneVendors.contains(where: { v.contains($0) }) {
            return .phone
        }

        // Servers (many open ports or server-like port profile)
        let serverPorts: Set<UInt16> = [22, 53, 80, 443, 3306, 5432, 8080, 8443, 9090]
        let serverPortCount = portNumbers.intersection(serverPorts).count
        if serverPortCount >= 3 {
            return .server
        }

        // IoT devices
        let iotVendors = ["espressif", "raspberry", "arduino", "sonoff",
                          "shelly", "tuya", "philips hue", "nest", "ring"]
        if iotVendors.contains(where: { v.contains($0) }) {
            return .iotDevice
        }

        // Computers (Apple, Intel, Dell, etc.)
        let computerVendors = ["apple", "dell", "lenovo", "intel", "microsoft",
                               "acer", "asus", "msi", "gigabyte", "realtek"]
        if computerVendors.contains(where: { v.contains($0) }) {
            // Apple with iServices → phone
            if v.contains("apple") && portNumbers.contains(62078) {
                return .phone
            }
            return .computer
        }

        // If online with some ports, call it a device
        if isOnline && !portNumbers.isEmpty {
            return .unknown
        }

        return .unknown
    }

    /// SF Symbol icon for the vendor (nil if no match)
    var vendorIconName: String? {
        guard let v = vendor?.lowercased() else { return nil }

        // Apple ecosystem
        if v.contains("apple") { return "apple.logo" }

        // Network equipment
        if v.contains("cisco") { return "network" }
        if v.contains("ubiquiti") { return "wifi.router" }
        if v.contains("netgear") || v.contains("tp-link") || v.contains("linksys")
            || v.contains("d-link") || v.contains("zyxel") || v.contains("asus")
            || v.contains("draytek") || v.contains("aruba") { return "wifi.router" }
        if v.contains("mikrotik") || v.contains("juniper") || v.contains("fortinet")
            || v.contains("sonicwall") { return "shield.lefthalf.filled" }

        // Printers
        if v.contains("hp") || v.contains("hewlett") || v.contains("canon")
            || v.contains("epson") || v.contains("brother") || v.contains("xerox")
            || v.contains("ricoh") || v.contains("lexmark") || v.contains("kyocera")
            || v.contains("konica") { return "printer" }

        // NAS / Storage
        if v.contains("synology") || v.contains("qnap") || v.contains("buffalo")
            || v.contains("drobo") || v.contains("asustor") { return "externaldrive" }
        if v.contains("western digital") || v.contains("seagate") { return "internaldrive" }

        // Mobile
        if v.contains("samsung") { return "iphone" }
        if v.contains("xiaomi") || v.contains("oneplus") || v.contains("oppo")
            || v.contains("vivo") || v.contains("huawei") { return "iphone" }
        if v.contains("google") { return "globe" }

        // Computers
        if v.contains("dell") || v.contains("lenovo") || v.contains("acer")
            || v.contains("msi") || v.contains("gigabyte") { return "laptopcomputer" }
        if v.contains("intel") || v.contains("realtek") || v.contains("broadcom")
            || v.contains("qualcomm") { return "cpu" }
        if v.contains("microsoft") { return "desktopcomputer" }

        // IoT / Smart home
        if v.contains("espressif") || v.contains("arduino") { return "cpu" }
        if v.contains("sonoff") || v.contains("shelly") || v.contains("tuya") { return "lightbulb" }
        if v.contains("philips") { return "lightbulb" }
        if v.contains("nest") || v.contains("ring") || v.contains("amazon") { return "homepod" }

        // Media / Entertainment
        if v.contains("sonos") || v.contains("bose") { return "hifispeaker" }
        if v.contains("roku") || v.contains("nvidia") { return "tv" }
        if v.contains("sony") { return "gamecontroller" }
        if v.contains("lg") || v.contains("vizio") { return "tv" }

        // Cameras
        if v.contains("hikvision") || v.contains("dahua") || v.contains("axis")
            || v.contains("reolink") { return "video" }

        return nil
    }

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
