//
//  ScanResultsView.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import SwiftUI
import AppKit

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
                        HStack(spacing: 5) {
                            Image(systemName: host.vendorIconName ?? host.deviceType.iconName)
                                .font(.system(size: 12))
                                .foregroundStyle(host.isOnline ? .primary : .tertiary)
                                .frame(width: 16)
                            Circle()
                                .fill(host.isOnline ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .width(min: 50, ideal: 60)

                    TableColumn("IP Address", value: \.ipSortKey) { host in
                        Text(host.ipAddress)
                            .font(.body.monospaced().weight(.medium))
                            .copyable(host.ipAddress)
                    }
                    .width(min: 110, ideal: 130)

                    TableColumn("Hostname", value: \.hostnameSortKey) { host in
                        Text(host.hostname ?? "—")
                            .font(.callout)
                            .foregroundStyle(host.hostname != nil ? .primary : .quaternary)
                            .copyable(host.hostname)
                    }
                    .width(min: 100, ideal: 170)

                    TableColumn("MAC Address", value: \.macSortKey) { host in
                        Text(host.macAddress ?? "—")
                            .font(.caption.monospaced())
                            .foregroundStyle(host.macAddress != nil ? .secondary : .quaternary)
                            .copyable(host.macAddress)
                    }
                    .width(min: 130, ideal: 150)

                    TableColumn("Vendor", value: \.vendorSortKey) { host in
                        HStack(spacing: 5) {
                            if let iconName = host.vendorIconName {
                                Image(systemName: iconName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                            }
                            Text(host.vendor ?? "—")
                                .font(.callout)
                                .foregroundStyle(host.vendor != nil ? .primary : .quaternary)
                        }
                        .copyable(host.vendor)
                    }
                    .width(min: 80, ideal: 190)

                    TableColumn("Latency", value: \.latencySortKey) { host in
                        Text(host.latencyString ?? "—")
                            .font(.caption.monospaced())
                            .foregroundStyle(host.latencyMs != nil ? .secondary : .quaternary)
                            .copyable(host.latencyString)
                    }
                    .width(min: 60, ideal: 75)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .searchable(text: $viewModel.searchText, prompt: "Filter by IP, hostname, MAC or vendor")
                .contextMenu(forSelectionType: String.self) { selection in
                    if let id = selection.first,
                       let host = viewModel.hosts.first(where: { $0.id == id }) {
                        Button("Copy IP Address") {
                            copyToClipboard(host.ipAddress)
                        }
                        if let hostname = host.hostname {
                            Button("Copy Hostname") {
                                copyToClipboard(hostname)
                            }
                        }
                        if let mac = host.macAddress {
                            Button("Copy MAC Address") {
                                copyToClipboard(mac)
                            }
                        }
                        if let vendor = host.vendor {
                            Button("Copy Vendor") {
                                copyToClipboard(vendor)
                            }
                        }
                    }
                }
            }

            StatusBarView(
                scanState: viewModel.scanState,
                onlineCount: viewModel.onlineCount,
                totalCount: viewModel.hosts.count
            )
        }
        .navigationTitle("Netter")
    }

    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

/// View modifier that adds a right-click "Copy" menu item to any view
private struct CopyableModifier: ViewModifier {
    let value: String?

    func body(content: Content) -> some View {
        if let value, !value.isEmpty {
            content.contextMenu {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func copyable(_ value: String?) -> some View {
        modifier(CopyableModifier(value: value))
    }
}
