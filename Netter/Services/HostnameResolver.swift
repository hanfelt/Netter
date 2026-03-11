//
//  HostnameResolver.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation
import Darwin

enum HostnameResolver: Sendable {

    /// Resolve a hostname for an IP address.
    /// Tries reverse DNS first, then NetBIOS (Windows), then mDNS (Apple/Bonjour).
    nonisolated static func resolve(_ ip: String) async -> String? {
        // Try reverse DNS first (fast, works with proper DNS servers)
        if let name = await reverseDNS(ip) {
            return name
        }

        // Try NetBIOS and mDNS in parallel — return whichever responds first
        async let netbios = netBIOSResolve(ip)
        async let mdns = mDNSResolve(ip)

        if let name = await netbios {
            return name
        }
        if let name = await mdns {
            return name
        }

        return nil
    }

    /// Reverse DNS using getnameinfo
    private nonisolated static func reverseDNS(_ ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                inet_pton(AF_INET, ip, &addr.sin_addr)

                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getnameinfo(
                            $0,
                            socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostname,
                            socklen_t(hostname.count),
                            nil, 0, 0
                        )
                    }
                }

                if result == 0 {
                    let name = String(cString: hostname)

                    // Don't return if it's just the IP echoed back
                    if name == ip {
                        continuation.resume(returning: nil)
                        return
                    }

                    continuation.resume(returning: cleanHostname(name))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Resolve hostname via mDNS using dns-sd command
    /// Constructs a reverse pointer name and queries for PTR record
    private nonisolated static func mDNSResolve(_ ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                // Build reverse DNS name: 192.168.50.35 -> 35.50.168.192.in-addr.arpa.
                let octets = ip.split(separator: ".")
                guard octets.count == 4 else {
                    continuation.resume(returning: nil)
                    return
                }
                let reverseName = octets.reversed().joined(separator: ".") + ".in-addr.arpa."

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
                process.arguments = ["-Q", reverseName, "PTR"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // dns-sd runs indefinitely, so kill it after a short timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                    if process.isRunning {
                        process.terminate()
                    }
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Parse dns-sd output for PTR record
                // Format: "... PTR hostname.local."
                let lines = output.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("PTR") && line.contains(".local.") {
                        // Extract the hostname from the end of the line
                        let parts = line.trimmingCharacters(in: .whitespaces)
                            .components(separatedBy: .whitespaces)
                        if let last = parts.last {
                            let hostname = cleanHostname(last)
                            if !hostname.isEmpty && hostname != ip {
                                continuation.resume(returning: hostname)
                                return
                            }
                        }
                    }
                }

                continuation.resume(returning: nil)
            }
        }
    }

    /// Resolve hostname via NetBIOS (NBNS) using smbutil
    /// Works for Windows machines, NAS devices, printers, etc.
    private nonisolated static func netBIOSResolve(_ ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
                process.arguments = ["status", ip]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // smbutil can hang, kill after timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                    if process.isRunning {
                        process.terminate()
                    }
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard let output = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Parse smbutil status output
                // Format: "Server: HOSTNAME"
                // or lines with workstation/server entries like:
                // "HOSTNAME        <00>  UNIQUE"
                let lines = output.components(separatedBy: "\n")
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // Look for "Server: NAME" line
                    if trimmed.hasPrefix("Server:") {
                        let name = trimmed
                            .replacingOccurrences(of: "Server:", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            continuation.resume(returning: name)
                            return
                        }
                    }
                }

                continuation.resume(returning: nil)
            }
        }
    }

    /// Clean up hostname by removing common suffixes and trailing dots
    private nonisolated static func cleanHostname(_ name: String) -> String {
        var cleaned = name
        // Remove trailing dot (FQDN format)
        if cleaned.hasSuffix(".") {
            cleaned = String(cleaned.dropLast())
        }
        // Remove common local suffixes
        cleaned = cleaned
            .replacingOccurrences(of: ".localdomain", with: "")
            .replacingOccurrences(of: ".local", with: "")
        return cleaned
    }
}
