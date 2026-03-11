//
//  ARPService.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation

enum ARPService: Sendable {

    struct ARPEntry: Sendable {
        let hostname: String?
        let ipAddress: String
        let macAddress: String
        let interfaceName: String
    }

    /// Read the entire ARP table by running /usr/sbin/arp -a
    nonisolated static func readARPTable() async -> [ARPEntry] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
                process.arguments = ["-a"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: [])
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: [])
                    return
                }

                let entries = parseARPOutput(output)
                continuation.resume(returning: entries)
            }
        }
    }

    /// Parse ARP table output
    /// Format: "hostname (IP) at MAC on INTERFACE ifscope [type]"
    /// When hostname is unknown: "? (IP) at MAC on INTERFACE ifscope [type]"
    private nonisolated static func parseARPOutput(_ output: String) -> [ARPEntry] {
        let lines = output.components(separatedBy: "\n")
        let pattern = #"^(\S+)\s+\(([^)]+)\)\s+at\s+([0-9a-f:]+)\s+on\s+(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        var entries: [ARPEntry] = []

        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }

            guard let hostnameRange = Range(match.range(at: 1), in: line),
                  let ipRange = Range(match.range(at: 2), in: line),
                  let macRange = Range(match.range(at: 3), in: line),
                  let ifaceRange = Range(match.range(at: 4), in: line) else { continue }

            let hostnameStr = String(line[hostnameRange])
            let ip = String(line[ipRange])
            let rawMac = String(line[macRange])
            let iface = String(line[ifaceRange])

            // Skip incomplete entries (MAC = ff:ff:ff:ff:ff:ff or (incomplete))
            if rawMac == "ff:ff:ff:ff:ff:ff" { continue }

            let mac = normalizeMACAddress(rawMac)

            // Hostname: "?" means unknown
            var hostname: String? = nil
            if hostnameStr != "?" {
                // Strip common suffixes
                hostname = hostnameStr
                    .replacingOccurrences(of: ".localdomain", with: "")
                    .replacingOccurrences(of: ".local", with: "")
            }

            entries.append(ARPEntry(
                hostname: hostname,
                ipAddress: ip,
                macAddress: mac,
                interfaceName: iface
            ))
        }

        return entries
    }

    /// Normalize a MAC address to uppercase, zero-padded format (e.g. "3c:61:5:de:1e:b8" -> "3C:61:05:DE:1E:B8")
    nonisolated static func normalizeMACAddress(_ mac: String) -> String {
        mac.split(separator: ":")
            .map { component in
                let hex = String(component)
                return hex.count == 1 ? "0\(hex)" : hex
            }
            .joined(separator: ":")
            .uppercased()
    }
}
