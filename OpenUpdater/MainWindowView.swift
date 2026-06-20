//
//  MainWindowView.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//


import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var updateManager: UpdateManager
    @State private var selectedTab = "updates"

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    .tag("updates")
                Label("Installed", systemImage: "square.grid.2x2")
                    .tag("installed")
                Label("Settings", systemImage: "gear")
                    .tag("settings")
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selectedTab {
            case "updates":
                UpdatesView()
            case "installed":
                InstalledView()
            case "settings":
                Text("Settings coming soon")
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
        .frame(minWidth: 700, minHeight: 450)
    }
}

struct UpdatesView: View {
    @EnvironmentObject private var updateManager: UpdateManager

    var body: some View {
        Group {
            if updateManager.updates.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text("No Updates Available")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("All your apps sourced from open registries are up to date.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Check for Updates") {
                        Task { await updateManager.checkForUpdates() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updateManager.isChecking)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(updateManager.updates) { app in
                    HStack {
                        AppIcon(app: app)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(app.installedVersion) → \(app.latestVersion ?? "?")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await updateManager.checkForUpdates() }
                } label: {
                    if updateManager.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(updateManager.isChecking)
            }
        }
    }
}

/// The macOS icon for an app bundle, loaded from disk via `NSWorkspace`.
struct AppIcon: View {
    let app: AppInfo
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

struct InstalledView: View {
    @EnvironmentObject private var updateManager: UpdateManager

    var body: some View {
        List(updateManager.apps) { app in
            HStack {
                AppIcon(app: app)
                VStack(alignment: .leading) {
                    Text(app.name)
                    Text(app.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(app.installedVersion)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
