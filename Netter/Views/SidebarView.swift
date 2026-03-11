//
//  SidebarView.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: ScannerViewModel
    @State private var customCIDR: String = ""
    @State private var showInvalidInput: Bool = false

    private var localInterfaces: [NetworkInterface] {
        viewModel.interfaces.filter { !$0.id.hasPrefix("custom-") }
    }

    private var customInterfaces: [NetworkInterface] {
        viewModel.interfaces.filter { $0.id.hasPrefix("custom-") }
    }

    var body: some View {
        List(selection: Binding(
            get: { viewModel.selectedInterface },
            set: { newValue in
                viewModel.selectInterface(newValue)
            }
        )) {
            Section("Custom Scan") {
                HStack(spacing: 6) {
                    TextField("e.g. 10.0.0.0/24", text: $customCIDR)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit {
                            addCustomNetwork()
                        }
                    Button {
                        addCustomNetwork()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(customCIDR.isEmpty)
                }

                if showInvalidInput {
                    Text("Invalid format. Use CIDR: 192.168.1.0/24")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                ForEach(customInterfaces) { iface in
                    InterfaceRow(interface: iface)
                        .tag(iface)
                }
            }

            Section("Local Networks") {
                if localInterfaces.isEmpty {
                    Text("No networks found")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(localInterfaces) { iface in
                        InterfaceRow(interface: iface)
                            .tag(iface)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Netter")
    }

    private func addCustomNetwork() {
        let input = customCIDR.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        if viewModel.addCustomNetwork(input) {
            customCIDR = ""
            showInvalidInput = false
        } else {
            showInvalidInput = true
        }
    }
}

private struct InterfaceRow: View {
    let interface: NetworkInterface

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(interface.displayName)
                    .font(.headline)
                Text(interface.ipAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(interface.cidrNotation) · \(interface.hostCount) hosts")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } icon: {
            Image(systemName: interface.iconName)
                .foregroundStyle(.blue)
                .frame(width: 20)
        }
        .padding(.vertical, 4)
    }
}
