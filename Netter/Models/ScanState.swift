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
    case completed(duration: TimeInterval)
    case error(message: String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

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
