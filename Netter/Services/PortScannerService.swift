//
//  PortScannerService.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation
import Network

nonisolated enum PortScannerService: Sendable {

    /// Scan common ports on a single host. Returns only open ports with banners.
    nonisolated static func scan(host: String) async -> [PortInfo] {
        await withTaskGroup(of: PortInfo?.self, returning: [PortInfo].self) { group in
            for entry in CommonPorts.all {
                group.addTask {
                    await scanPort(host: host, port: entry.port, service: entry.service)
                }
            }

            var results: [PortInfo] = []
            for await result in group {
                if let r = result {
                    results.append(r)
                }
            }
            return results.sorted { $0.port < $1.port }
        }
    }

    /// Try to connect to a single port with a short timeout.
    /// If open, attempt to grab the service banner.
    private nonisolated static func scanPort(
        host: String,
        port: UInt16,
        service: String
    ) async -> PortInfo? {
        let isOpen = await tcpConnect(host: host, port: port, timeout: 1.5)
        guard isOpen else { return nil }

        let banner = await grabBanner(host: host, port: port, service: service)
        return PortInfo(port: port, service: service, banner: banner)
    }

    // MARK: - TCP Connect

    /// Pure NWConnection-based TCP connect check.
    private nonisolated static func tcpConnect(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let params = NWParameters.tcp
            params.requiredInterfaceType = .other // Allow any interface
            let connection = NWConnection(host: nwHost, port: nwPort, using: params)

            let once = OnceFlag()

            let finish: @Sendable (Bool) -> Void = { result in
                guard once.tryAcquire() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .cancelled, .waiting:
                    finish(false)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }

    // MARK: - Banner Grabbing

    /// Try to read a service banner from an open port.
    /// Uses protocol-specific probes for HTTP(S), otherwise reads the initial banner.
    private nonisolated static func grabBanner(
        host: String,
        port: UInt16,
        service: String
    ) async -> String? {
        switch port {
        case 80, 8080, 5000, 9090:
            return await httpBanner(host: host, port: port, useTLS: false)
        case 443, 8443, 5001:
            return await httpBanner(host: host, port: port, useTLS: true)
        case 631:
            return await ippBanner(host: host)
        default:
            return await rawBanner(host: host, port: port)
        }
    }

    /// Read raw banner (SSH, SMB, etc.) — many services send a greeting on connect.
    private nonisolated static func rawBanner(
        host: String,
        port: UInt16
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)

            let once = OnceFlag()

            let finish: @Sendable (String?) -> Void = { result in
                guard once.tryAcquire() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                        if let data, let str = String(data: data, encoding: .utf8) {
                            let cleaned = cleanBanner(str)
                            finish(cleaned.isEmpty ? nil : cleaned)
                        } else {
                            finish(nil)
                        }
                    }
                case .failed, .cancelled, .waiting:
                    finish(nil)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                finish(nil)
            }
        }
    }

    /// Send an HTTP HEAD request and parse the Server header.
    private nonisolated static func httpBanner(
        host: String,
        port: UInt16,
        useTLS: Bool
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let once = OnceFlag()

            let finish: @Sendable (String?) -> Void = { result in
                guard once.tryAcquire() else { return }
                continuation.resume(returning: result)
            }

            let scheme = useTLS ? "https" : "http"
            guard let url = URL(string: "\(scheme)://\(host):\(port)/") else {
                finish(nil)
                return
            }

            var request = URLRequest(url: url, timeoutInterval: 3)
            request.httpMethod = "HEAD"

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = 3
            let delegate = InsecureSessionDelegate()
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

            let task = session.dataTask(with: request) { _, response, _ in
                if let http = response as? HTTPURLResponse {
                    let server = http.value(forHTTPHeaderField: "Server")
                    finish(server)
                } else {
                    finish(nil)
                }
                session.invalidateAndCancel()
            }
            task.resume()

            DispatchQueue.global().asyncAfter(deadline: .now() + 4.0) {
                task.cancel()
                finish(nil)
            }
        }
    }

    /// Query IPP printer attributes via a simple HTTP request.
    private nonisolated static func ippBanner(host: String) async -> String? {
        // IPP printers often expose info via HTTP on port 631
        if let server = await httpBanner(host: host, port: 631, useTLS: false) {
            return server
        }
        return nil
    }

    // MARK: - Helpers

    private nonisolated static func cleanBanner(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
           .components(separatedBy: "\r\n").first ?? raw
           .trimmingCharacters(in: .controlCharacters)
    }
}

/// Thread-safe one-shot flag for ensuring continuations resume exactly once
private nonisolated final class OnceFlag: Sendable {
    private let _flag = NSLock()
    private nonisolated(unsafe) let _acquired = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

    nonisolated init() { _acquired.initialize(to: false) }
    deinit { _acquired.deallocate() }

    nonisolated func tryAcquire() -> Bool {
        _flag.lock()
        defer { _flag.unlock() }
        if _acquired.pointee { return false }
        _acquired.pointee = true
        return true
    }
}

/// URLSession delegate that accepts self-signed certificates (common on LAN devices)
private final class InsecureSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}
