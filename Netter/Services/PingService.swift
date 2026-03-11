//
//  PingService.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation

enum PingService: Sendable {

    struct PingResult: Sendable {
        let isAlive: Bool
        let latencyMs: Double?
    }

    /// Ping a single host using /sbin/ping
    nonisolated static func ping(_ ip: String, timeout: Int = 2) async -> PingResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                // -c 1: one packet, -t: timeout in seconds, -W: wait time in ms for reply
                process.arguments = ["-c", "1", "-t", "\(timeout)", "-W", "1000", ip]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: PingResult(isAlive: false, latencyMs: nil))
                    return
                }

                // Read stdout BEFORE waitUntilExit to avoid pipe buffer deadlock
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let isAlive = process.terminationStatus == 0
                var latency: Double? = nil

                if isAlive, let output = String(data: data, encoding: .utf8),
                   let range = output.range(of: #"time=(\d+\.?\d*)"#, options: .regularExpression) {
                    let match = output[range]
                    let timeStr = match.dropFirst(5) // drop "time="
                    latency = Double(timeStr)
                }

                continuation.resume(returning: PingResult(isAlive: isAlive, latencyMs: latency))
            }
        }
    }

    /// Scan multiple hosts concurrently with a sliding window of maxConcurrent
    nonisolated static func scanHosts(
        _ ips: [String],
        maxConcurrent: Int = 50,
        onProgress: @escaping @Sendable (String, Int) async -> Void
    ) async -> [String: PingResult] {
        var results: [String: PingResult] = [:]
        var scannedCount = 0

        await withTaskGroup(of: (String, PingResult).self) { group in
            var iterator = ips.makeIterator()

            // Seed the group with the initial batch
            for _ in 0..<min(maxConcurrent, ips.count) {
                guard let ip = iterator.next() else { break }
                group.addTask {
                    let result = await ping(ip)
                    return (ip, result)
                }
            }

            // As each task completes, start the next one
            for await (ip, result) in group {
                results[ip] = result
                scannedCount += 1
                await onProgress(ip, scannedCount)

                if let nextIP = iterator.next() {
                    group.addTask {
                        let result = await ping(nextIP)
                        return (nextIP, result)
                    }
                }
            }
        }

        return results
    }
}
