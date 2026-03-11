//
//  ScanState.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import Foundation

nonisolated enum ScanState: Sendable, Equatable {
    case idle
    case scanning(progress: ScanProgress)
    case enriching(progress: EnrichProgress)
    case completed(duration: TimeInterval)
    case error(message: String)

    var isScanning: Bool {
        switch self {
        case .scanning, .enriching: return true
        default: return false
        }
    }
}

/// Phase 1: Ping sweep
nonisolated struct ScanProgress: Sendable, Equatable {
    let currentIP: String
    let scannedCount: Int
    let totalCount: Int

    var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return Double(scannedCount) / Double(totalCount)
    }

    var description: String {
        "Scanning \(currentIP)... (\(scannedCount)/\(totalCount))"
    }
}

/// Phase 2: Detail enrichment (ARP, hostname, vendor)
nonisolated struct EnrichProgress: Sendable, Equatable {
    let completedCount: Int
    let totalCount: Int
    let currentIP: String

    var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var description: String {
        "Resolving details for \(currentIP)... (\(completedCount)/\(totalCount))"
    }
}
