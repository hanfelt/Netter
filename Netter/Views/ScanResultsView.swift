//
//  ScanResultsView.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import SwiftUI

struct ScanResultsView: View {
    @Bindable var viewModel: ScannerViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.selectedInterface == nil {
                ContentUnavailableView(
                    "Select a Network",
                    systemImage: "network",
                    description: Text("Choose a network interface from the sidebar to begin scanning.")
                )
            } else if viewModel.hosts.isEmpty && !viewModel.scanState.isScanning {
                ContentUnavailableView(
                    "No Scan Results",
                    systemImage: "magnifyingglass",
                    description: Text("Press Scan to discover devices on this network.")
                )
            } else {
                Table(viewModel.filteredHosts, selection: $viewModel.selectedHostID, sortOrder: $viewModel.sortOrder) {
                    TableColumn("Status") { host in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(host.isOnline ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text(host.isOnline ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundStyle(host.isOnline ? .primary : .tertiary)
                        }
                    }
                    .width(min: 60, ideal: 75)

                    TableColumn("IP Address", value: \.ipSortKey) { host in
                        Text(host.ipAddress)
                            .font(.body.monospaced())
                    }
                    .width(min: 110, ideal: 130)

                    TableColumn("Hostname") { host in
                        Text(host.hostname ?? "—")
                            .foregroundStyle(host.hostname != nil ? .primary : .tertiary)
                    }
                    .width(min: 100, ideal: 170)

                    TableColumn("MAC Address") { host in
                        Text(host.macAddress ?? "—")
                            .font(.body.monospaced())
                            .foregroundStyle(host.macAddress != nil ? .primary : .tertiary)
                    }
                    .width(min: 130, ideal: 150)

                    TableColumn("Vendor") { host in
                        Text(host.vendor ?? "—")
                            .foregroundStyle(host.vendor != nil ? .primary : .tertiary)
                    }
                    .width(min: 80, ideal: 180)

                    TableColumn("Latency") { host in
                        Text(host.latencyString ?? "—")
                            .font(.body.monospaced())
                            .foregroundStyle(host.latencyMs != nil ? .primary : .tertiary)
                    }
                    .width(min: 60, ideal: 75)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }

            StatusBarView(
                scanState: viewModel.scanState,
                onlineCount: viewModel.onlineCount,
                totalCount: viewModel.hosts.count
            )
        }
    }
}
