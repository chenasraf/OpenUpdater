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
          .badge(updateManager.updates.count)
          .tag("updates")
        Label("Installed", systemImage: "square.grid.2x2")
          .tag("installed")
      }
      .navigationSplitViewColumnWidth(180)
      .safeAreaInset(edge: .bottom) {
        SettingsLink {
          Label("Preferences", systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } detail: {
      switch selectedTab {
      case "updates":
        UpdatesView()
      case "installed":
        InstalledView()
      default:
        EmptyView()
      }
    }
    .frame(minWidth: 700, minHeight: 450)
    .task { await updateManager.checkForUpdatesIfNeeded() }
  }
}

struct UpdatesView: View {
  @EnvironmentObject private var updateManager: UpdateManager

  var body: some View {
    Group {
      if !updateManager.updates.isEmpty {
        updateList
      } else if updateManager.isChecking {
        CenteredStatus(systemImage: nil, title: "Checking for Updates…", showSpinner: true)
      } else if updateManager.lastChecked == nil {
        CenteredStatus(
          systemImage: "arrow.triangle.2.circlepath.circle",
          title: "Check for Updates",
          message: "Look for newer versions of your installed apps."
        )
      } else if let error = updateManager.lastError {
        CenteredStatus(
          systemImage: "exclamationmark.triangle.fill",
          title: "Couldn't Check for Updates",
          message: error,
          tint: .orange
        )
      } else {
        CenteredStatus(
          systemImage: "checkmark.seal.fill",
          title: "Everything's Up to Date",
          message: lastCheckedText,
          tint: .green
        )
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) { CheckForUpdatesButton() }
    }
  }

  private var updateList: some View {
    VStack(spacing: 0) {
      HStack {
        Text("^[\(updateManager.updates.count) update](inflect: true) available")
          .font(.headline)
        Spacer()
        if let lastCheckedText {
          Text(lastCheckedText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button {
          Task { await updateManager.updateAll() }
        } label: {
          if updateManager.isUpdatingAll {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small)
              Text("Updating…")
            }
          } else {
            Text("Update All")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(updateManager.isUpdatingAll || updateManager.installableUpdates.isEmpty)
      }
      .padding()

      Divider()

      List(updateManager.updates) { app in
        UpdateRow(app: app)
      }
    }
  }

  private var lastCheckedText: String? {
    guard let lastChecked = updateManager.lastChecked else { return nil }
    return "Last checked \(lastChecked.formatted(date: .omitted, time: .shortened))"
  }
}

/// One available-update row: icon, name, release-notes link, version change, and
/// an Update button that downloads and installs in place.
struct UpdateRow: View {
  let app: AppInfo
  @EnvironmentObject private var updateManager: UpdateManager

  var body: some View {
    HStack(spacing: 12) {
      AppIcon(app: app)
      VStack(alignment: .leading, spacing: 2) {
        Text(app.name)
        if let changelogURL = app.changelogURL {
          Link("Release notes", destination: changelogURL)
            .font(.caption)
        } else {
          Text(app.id)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(app.latestVersion ?? "?")
          .foregroundStyle(.orange)
          .fontWeight(.medium)
        Text(app.installedVersion)
          .font(.caption)
          .foregroundStyle(.secondary)
          .strikethrough()
      }
      installControl
        .frame(width: 120, alignment: .trailing)
    }
    .padding(.vertical, 4)
    // Run the separator edge-to-edge, including under the app icon.
    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    .appContextMenu(app)
  }

  @ViewBuilder private var installControl: some View {
    switch updateManager.installPhase(for: app.id) {
    case .idle:
      Button("Update") {
        Task { await updateManager.installUpdate(app) }
      }
      .buttonStyle(.borderedProminent)
      .disabled(app.downloadURL == nil || updateManager.isUpdatingAll)
      .help(app.downloadURL == nil ? "No download available for this app yet" : "")
    case .downloading(let fraction):
      HStack(spacing: 6) {
        ProgressView(value: fraction).controlSize(.small).frame(width: 56)
        Text("\(Int(fraction * 100))%").font(.caption).foregroundStyle(.secondary)
          .monospacedDigit()
      }
    case .extracting:
      progress("Extracting…")
    case .verifying:
      progress("Verifying…")
    case .quitting:
      progress("Quitting app…")
    case .installing:
      progress("Installing…")
    case .done:
      Label("Updated", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed(let message):
      HStack(spacing: 4) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Button("Retry") { Task { await updateManager.installUpdate(app) } }
      }
      .help(message)
    }
  }

  private func progress(_ label: String) -> some View {
    HStack(spacing: 6) {
      ProgressView().controlSize(.small)
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
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
        if app.updateAvailable {
          Text("\(app.installedVersion) → \(app.latestVersion ?? "?")")
            .foregroundStyle(.orange)
        } else if app.latestVersion != nil {
          // Checked, no newer version. Use a plain HStack rather than a
          // Label — a Label here pulls the List row separator inward.
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
            Text(app.installedVersion)
          }
          .foregroundStyle(.green)
        } else {
          Text(app.installedVersion)
            .foregroundStyle(.secondary)
        }
      }
      // Run the separator edge-to-edge, including under the app icon.
      .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
      .appContextMenu(app)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) { CheckForUpdatesButton() }
    }
  }
}

/// Right-click menu for an app row. Currently the pre-release toggle (GitHub only).
private struct AppContextMenu: ViewModifier {
  let app: AppInfo
  @EnvironmentObject private var updateManager: UpdateManager

  @ViewBuilder func body(content: Content) -> some View {
    if updateManager.supportsPrereleases(app) {
      content.contextMenu {
        Toggle(
          "Check for pre-releases",
          isOn: Binding(
            get: { updateManager.includePrereleases(for: app) },
            set: { value in Task { await updateManager.setPrereleases(value, for: app) } }
          ))
      }
    } else {
      content
    }
  }
}

extension View {
  func appContextMenu(_ app: AppInfo) -> some View { modifier(AppContextMenu(app: app)) }
}

/// Toolbar button that triggers a check and shows a spinner while running.
struct CheckForUpdatesButton: View {
  @EnvironmentObject private var updateManager: UpdateManager

  var body: some View {
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

/// A large centered status message, optionally with a spinner instead of an icon.
struct CenteredStatus: View {
  var systemImage: String?
  let title: String
  var message: String?
  var tint: Color = .secondary
  var showSpinner = false

  var body: some View {
    VStack(spacing: 16) {
      if showSpinner {
        ProgressView().controlSize(.large)
      } else if let systemImage {
        Image(systemName: systemImage)
          .font(.system(size: 56))
          .foregroundStyle(tint)
      }
      Text(title)
        .font(.title2)
        .fontWeight(.medium)
      if let message {
        Text(message)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
