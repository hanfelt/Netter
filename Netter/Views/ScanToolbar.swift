//
//  ScanToolbar.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import SwiftUI

struct ScanToolbar: ToolbarContent {
    @Bindable var viewModel: ScannerViewModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if viewModel.scanState.isScanning {
                Button {
                    viewModel.stopScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .tint(.red)
            } else {
                Button {
                    viewModel.startScan()
                } label: {
                    Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(viewModel.selectedInterface == nil)
            }
        }

        ToolbarItem(placement: .automatic) {
            Toggle(isOn: $viewModel.showOnlineOnly) {
                Label("Online Only", systemImage: "line.3.horizontal.decrease.circle")
            }
            .toggleStyle(.button)
            .help("Show only online hosts")
        }

        ToolbarItem(placement: .automatic) {
            Button {
                viewModel.loadInterfaces()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh network interfaces")
        }
    }
}
