//
//  ContentView.swift
//  Netter
//
//  Created by Andreas Hanfelt on 2026-03-11.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = ScannerViewModel()
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            ScanResultsView(viewModel: viewModel)
                .inspector(isPresented: $showInspector) {
                    if let host = viewModel.selectedHost {
                        HostDetailView(host: host)
                    } else {
                        ContentUnavailableView(
                            "No Selection",
                            systemImage: "desktopcomputer",
                            description: Text("Select a host to view details.")
                        )
                    }
                }
        }
        .toolbar {
            ScanToolbar(viewModel: viewModel)

            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $showInspector) {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .toggleStyle(.button)
                .help("Toggle host details inspector")
            }
        }
        .onAppear {
            viewModel.loadInterfaces()
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
