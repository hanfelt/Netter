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
        HStack(spacing: 6) {
            switch scanState {
            case .idle:
                Circle()
                    .fill(.tertiary)
                    .frame(width: 5, height: 5)
                Text("Ready")
                    .foregroundStyle(.tertiary)

            case .scanning(let progress):
                ProgressView(value: progress.fractionCompleted)
                    .frame(width: 100)
                    .controlSize(.small)
                Text(progress.description)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

            case .enriching(let progress):
                ProgressView(value: progress.fractionCompleted)
                    .frame(width: 100)
                    .controlSize(.small)
                Text(progress.description)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

            case .completed(let duration):
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Done in \(String(format: "%.1f", duration))s")
                    .foregroundStyle(.secondary)

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if totalCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(.green)
                        .frame(width: 5, height: 5)
                    Text("\(onlineCount)")
                        .foregroundStyle(.primary)
                    Text("/ \(totalCount)")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .font(.caption2)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
