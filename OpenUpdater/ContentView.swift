//
//  ContentView.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import SwiftUI

struct ContentView: View {
    let openMainWindow: () -> Void
    @EnvironmentObject private var updateManager: UpdateManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(.tint)
                Text("App Updates")
                    .font(.headline)
                Spacer()
                Button(action: openMainWindow) {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .help("Open full window")
            }
            .padding()
            .background(.bar)

            Divider()

            // Update list / empty state
            if updateManager.updates.isEmpty {
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("All apps are up to date")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(updateManager.updates) { app in
                    HStack {
                        AppIcon(app: app, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                            Text("\(app.installedVersion) → \(app.latestVersion ?? "?")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                if updateManager.isChecking {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Check Now") {
                        Task { await updateManager.checkForUpdates() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}
