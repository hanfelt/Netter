//
//  HostDetailView.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import SwiftUI

struct HostDetailView: View {
    let host: ScannedHost

    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("IP Address", value: host.ipAddress)
                LabeledContent("Hostname", value: host.hostname ?? "Unknown")
                LabeledContent("Status") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(host.isOnline ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(host.isOnline ? "Online" : "Offline")
                    }
                }
            }

            Section("Network") {
                LabeledContent("MAC Address", value: host.macAddress ?? "Unknown")
                LabeledContent("Vendor", value: host.vendor ?? "Unknown")
                if let latency = host.latencyString {
                    LabeledContent("Latency", value: latency)
                }
            }

            if !host.openPorts.isEmpty {
                Section("Open Ports") {
                    Grid(alignment: .leading, verticalSpacing: 6) {
                        GridRow {
                            Text("Port")
                                .fontWeight(.semibold)
                            Text("Service")
                                .fontWeight(.semibold)
                            Text("Details")
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Divider()

                        ForEach(host.openPorts) { port in
                            GridRow {
                                Text(verbatim: "\(port.port)")
                                    .monospacedDigit()
                                Text(port.service)
                                Text(port.displayBanner)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .font(.callout)
                        }
                    }
                }
            }

            Section("Activity") {
                LabeledContent("Last Seen", value: host.lastSeen.formatted(
                    .dateTime.hour().minute().second()
                ))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 250)
    }
}
