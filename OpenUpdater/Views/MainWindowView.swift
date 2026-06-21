//
//  MainWindowView.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import SwiftUI

struct MainWindowView: View {
  @EnvironmentObject private var updateManager: UpdateManager
  @Environment(\.openWindow) private var openWindow
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
        Button {
          openWindow(id: PreferencesWindow.id)
        } label: {
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
  @State private var selection: Set<AppInfo.ID> = []

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
        if !selection.isEmpty {
          Button("Update Selected (\(selectedInstallableCount))") {
            let ids = selection
            Task {
              await updateManager.updateSelected(ids)
              selection = []
            }
          }
          .disabled(updateManager.isUpdatingAll || selectedInstallableCount == 0)
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

      List(updateManager.updates, selection: $selection) { app in
        UpdateRow(app: app)
      }
      .contextMenu(forSelectionType: AppInfo.ID.self) { ids in
        AppContextMenuItems(ids: ids)
      }
    }
  }

  /// How many of the selected apps actually have something to install.
  private var selectedInstallableCount: Int {
    updateManager.installableUpdates.filter { selection.contains($0.id) }.count
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
        .frame(width: 140, alignment: .trailing)
    }
    .padding(.vertical, 4)
    // Run the separator edge-to-edge, including under the app icon.
    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
  }

  @ViewBuilder private var installControl: some View {
    if updateManager.isRescanning(app.id) {
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text("Re-scanning…").font(.caption).foregroundStyle(.secondary)
      }
    } else {
      installPhaseControl
    }
  }

  @ViewBuilder private var installPhaseControl: some View {
    switch updateManager.installPhase(for: app.id) {
    case .idle:
      if app.source == .appStore {
        Button("App Store") { updateManager.openInAppStore(app) }
          .buttonStyle(.bordered)
          .disabled(updateManager.isUpdatingAll)
          .help("Update this app in the App Store")
      } else if app.downloadURL == nil {
        Button("Manual Update…") { updateManager.manualUpdate(app) }
          .buttonStyle(.bordered)
          .disabled(updateManager.isUpdatingAll)
          .help("\(AppBranding.title) can't auto-install this update — choose how to update.")
      } else {
        Button("Update") { updateManager.startInstall(app) }
          .buttonStyle(.borderedProminent)
          .disabled(updateManager.isUpdatingAll)
      }
    case .downloading(let fraction):
      HStack(spacing: 6) {
        ProgressView(value: fraction).controlSize(.small).frame(width: 50)
        Text("\(Int(fraction * 100))%").font(.caption).foregroundStyle(.secondary)
          .monospacedDigit()
        cancelButton
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
        Button {
          updateManager.showInstallFailure(app, message: message)
        } label: {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .help("Show error details")
        Button("Retry") { updateManager.startInstall(app) }
      }
    }
  }

  /// X button to cancel a running install.
  private var cancelButton: some View {
    Button {
      updateManager.cancelInstall(app)
    } label: {
      Image(systemName: "xmark.circle.fill")
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .help("Cancel")
  }

  private func progress(_ label: String) -> some View {
    HStack(spacing: 6) {
      ProgressView().controlSize(.small)
      Text(label).font(.caption).foregroundStyle(.secondary)
      cancelButton
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
        if updateManager.isRescanning(app.id) {
          ProgressView().controlSize(.small)
        } else if app.updateAvailable {
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
/// Context-menu items that adapt to how many apps they apply to: a single app gets
/// the full per-app menu (incl. the pre-release toggle); multiple selected apps get
/// plural actions that apply to all of them.
struct AppContextMenuItems: View {
  @EnvironmentObject private var updateManager: UpdateManager
  let ids: Set<AppInfo.ID>

  private var apps: [AppInfo] { updateManager.apps.filter { ids.contains($0.id) } }

  var body: some View {
    if apps.count == 1, let app = apps.first {
      single(app)
    } else if apps.count > 1 {
      multiple(apps)
    }
  }

  @ViewBuilder private func single(_ app: AppInfo) -> some View {
    Button("Re-scan App") {
      Task { await updateManager.rescan(app) }
    }
    .disabled(updateManager.isRescanning(app.id))

    if updateManager.supportsPrereleases(app) {
      Divider()
      Toggle(
        "Check for pre-releases",
        isOn: Binding(
          get: { updateManager.includePrereleases(for: app) },
          set: { value in Task { await updateManager.setPrereleases(value, for: app) } }
        ))
    }

    if app.builtInIgnoreReason == nil {
      Divider()
      Menu("Ignore…") {
        Button("Ignore this app") { updateManager.ignoreApp(app) }
        if app.updateAvailable {
          Button("Ignore this version") { updateManager.ignoreCurrentVersion(app) }
        }
      }
    }
  }

  @ViewBuilder private func multiple(_ apps: [AppInfo]) -> some View {
    Button("Re-scan \(apps.count) Apps") {
      Task { await updateManager.rescanApps(apps) }
    }

    let ignorable = apps.filter { $0.builtInIgnoreReason == nil }
    if !ignorable.isEmpty {
      Divider()
      Button("Ignore These Apps") { updateManager.ignoreApps(ignorable) }
      let withUpdates = ignorable.filter(\.updateAvailable)
      if !withUpdates.isEmpty {
        Button("Ignore These Versions") { updateManager.ignoreCurrentVersions(withUpdates) }
      }
    }
  }
}

private struct AppContextMenu: ViewModifier {
  let app: AppInfo

  func body(content: Content) -> some View {
    content.contextMenu { AppContextMenuItems(ids: [app.id]) }
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
    Image(nsImage: IconCache.icon(for: app.url))
      .resizable()
      .frame(width: size, height: size)
  }
}

/// Caches app icons so frequent list re-renders (e.g. during an install's progress
/// updates) don't hit `NSWorkspace` synchronously on the main thread each time.
@MainActor
enum IconCache {
  private static var cache: [String: NSImage] = [:]

  static func icon(for url: URL) -> NSImage {
    if let cached = cache[url.path] { return cached }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    cache[url.path] = icon
    return icon
  }
}
