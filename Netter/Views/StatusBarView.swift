//
//  StatusBarView.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import SwiftUI

struct StatusBarView: View {
    let scanState: ScanState
    let onlineCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 8) {
            switch scanState {
            case .idle:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                Text("Ready")
                    .foregroundStyle(.secondary)

            case .scanning(let progress):
                ProgressView(value: progress.fractionCompleted)
                    .frame(width: 120)
                Text(progress.description)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            case .enriching(let progress):
                ProgressView(value: progress.fractionCompleted)
                    .frame(width: 120)
                Text(progress.description)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            case .completed(let duration):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Scan complete in \(String(format: "%.1f", duration))s")
                    .foregroundStyle(.secondary)

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if totalCount > 0 {
                Text("\(onlineCount) online")
                    .foregroundStyle(.green)
                Text("/ \(totalCount) total")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
