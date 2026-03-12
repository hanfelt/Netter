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
    @State private var customName: String = ""
    @State private var showInvalidInput: Bool = false
    @State private var pendingInterface: NetworkInterface?
    @State private var showSwitchConfirmation: Bool = false

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
                guard newValue != viewModel.selectedInterface else { return }
                if viewModel.scanState.isScanning {
                    pendingInterface = newValue
                    showSwitchConfirmation = true
                } else {
                    viewModel.selectInterface(newValue)
                }
            }
        )) {
            Section("Custom Scan") {
                VStack(spacing: 4) {
                    TextField("Name (optional)", text: $customName)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
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
                }

                if showInvalidInput {
                    Text("Invalid format. Use CIDR: 192.168.1.0/24")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                ForEach(customInterfaces) { iface in
                    HStack {
                        InterfaceRow(interface: iface)
                        Spacer()
                        Button {
                            viewModel.removeCustomNetwork(iface)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this custom network")
                    }
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
        .confirmationDialog(
            "A scan is currently in progress.",
            isPresented: $showSwitchConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Scan and Switch", role: .destructive) {
                if let iface = pendingInterface {
                    viewModel.selectInterface(iface)
                }
                pendingInterface = nil
            }
            Button("Cancel", role: .cancel) {
                pendingInterface = nil
            }
        } message: {
            Text("Switching network will stop the current scan. Do you want to continue?")
        }
    }

    private func addCustomNetwork() {
        let input = customCIDR.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        let name = customName.trimmingCharacters(in: .whitespaces)
        if viewModel.addCustomNetwork(input, name: name.isEmpty ? nil : name) {
            customCIDR = ""
            customName = ""
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
                if interface.name == "custom" {
                    Text("\(interface.cidrNotation) · \(interface.hostCount) hosts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(interface.ipAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(interface.cidrNotation) · \(interface.hostCount) hosts")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } icon: {
            Image(systemName: interface.iconName)
                .foregroundStyle(.blue)
                .frame(width: 20)
        }
        .padding(.vertical, 4)
    }
}
