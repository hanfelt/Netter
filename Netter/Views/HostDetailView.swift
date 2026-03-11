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
