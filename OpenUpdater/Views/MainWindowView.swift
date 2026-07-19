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
          .badge(updateManager.apps.count)
          .tag("installed")
        Label("Ignored", systemImage: "nosign")
          .badge(updateManager.ignoredApps.filter { $0.builtInIgnoreReason == nil }.count)
          .tag("ignored")
        Label("Unsupported", systemImage: "questionmark.circle")
          .badge(updateManager.unsupportedApps.count)
          .tag("unsupported")
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
      Group {
        switch selectedTab {
        case "updates":
          UpdatesView()
        case "installed":
          InstalledView()
        case "ignored":
          IgnoreListView()
        case "unsupported":
          UnsupportedAppsView(onCreateRecipe: createRecipe)
        default:
          EmptyView()
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
    }
    .frame(minWidth: 700, minHeight: 450)
    .task { await updateManager.checkForUpdatesIfNeeded() }
  }

  /// Create a draft custom recipe for an app, then open Preferences and let it
  /// select the new recipe in the Custom Recipes tab (which lives in that window).
  private func createRecipe(for app: AppInfo) {
    updateManager.pendingCustomRecipeID = updateManager.createCustomRecipeDraft(for: app)
    openWindow(id: PreferencesWindow.id)
  }
}

/// Thin bar across the bottom of the window: the current activity (an in-flight
/// install or check, with the per-app/recipe detail) and, at rest, the last-checked
/// time. The individual list rows keep their own inline progress as well.
struct StatusBar: View {
  @EnvironmentObject private var updateManager: UpdateManager

  var body: some View {
    HStack(spacing: 6) {
      if updateManager.isChecking || updateManager.isInstalling {
        ProgressView().controlSize(.small)
      }
      Text(updateManager.statusLine)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
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
        if !selection.isEmpty {
          Button("Update Selected (\(selectedInstallableCount))") {
            updateManager.updateSelected(selection)
            selection = []
          }
          .disabled(selectedInstallableCount == 0)
        }
        Button {
          updateManager.updateAll()
        } label: {
          if updateManager.isInstalling {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small)
              Text("Updating…")
            }
          } else {
            Text("Update All")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(updateManager.isInstalling || updateManager.installableUpdates.isEmpty)
        if updateManager.isInstalling {
          Button(role: .destructive) {
            updateManager.stopBatch()
          } label: {
            Label("Stop", systemImage: "stop.fill")
          }
          .help("Stop the current update and don't continue with the rest")
        }
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
          .help("Update this app in the App Store")
      } else if app.downloadURL == nil {
        Button("Manual Update…") { updateManager.manualUpdate(app) }
          .buttonStyle(.bordered)
          .help("\(AppBranding.title) can't auto-install this update — choose how to update.")
      } else {
        Button("Update") { updateManager.enqueueInstall(app) }
          .buttonStyle(.borderedProminent)
      }
    case .queued:
      HStack(spacing: 6) {
        Text("Queued").font(.caption).foregroundStyle(.secondary)
        cancelButton
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
    case .failed(let message):
      HStack(spacing: 4) {
        Button {
          updateManager.showInstallFailure(app, message: message)
        } label: {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .help("Show error details")
        Button("Retry") { updateManager.enqueueInstall(app) }
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

/// Info icon for an ignored app: tapping it shows why it's ignored in a popover
/// anchored below the icon; clicking out (or the icon) dismisses it.
struct IgnoreReasonButton: View {
  let message: String
  @State private var showing = false

  var body: some View {
    Button {
      showing.toggle()
    } label: {
      Image(systemName: "info.circle").foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $showing, arrowEdge: .bottom) {
      Text(message)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 260, alignment: .leading)
        .padding(12)
    }
    .help("Why is this app ignored?")
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
        if let message = ignoreMessage(for: app) {
          IgnoreReasonButton(message: message)
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
      // Gray out ignored apps (by OpenUpdater or the user) to signal they're skipped.
      .opacity(ignoreMessage(for: app) == nil ? 1 : 0.5)
      // Run the separator edge-to-edge, including under the app icon.
      .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
      .appContextMenu(app)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) { CheckForUpdatesButton() }
    }
  }

  /// Why this app is being skipped, or `nil` if it isn't ignored. OpenUpdater's own
  /// built-in ignore wins over a user ignore (it's what actually suppresses checks).
  private func ignoreMessage(for app: AppInfo) -> String? {
    if let reason = app.builtInIgnoreReason {
      return "Ignored by \(AppBranding.title). Reason: \(reason)"
    }
    if app.ignored {
      return "Ignored by user. Scope: Entire app"
    }
    if let version = app.ignoredVersion {
      return "Ignored by user. Scope: Version \(version)"
    }
    return nil
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
    Button("Launch App") { NSWorkspace.shared.open(app.url) }
    if let homepage = app.homepageURL {
      Button("Open Homepage") { NSWorkspace.shared.open(homepage) }
    }
    Button("Show in Finder") {
      NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    Divider()

    Button("Re-scan App") {
      Task { await updateManager.rescan(app) }
    }
    .disabled(updateManager.isRescanning(app.id))

    if updateManager.supportsChannels(app) {
      Divider()
      Picker(
        "Release Channel",
        selection: Binding(
          get: { updateManager.selectedChannel(for: app) },
          set: { id in Task { await updateManager.setChannel(id, for: app) } }
        )
      ) {
        ForEach(updateManager.channels(for: app), id: \.id) { channel in
          Text(channel.displayName).tag(channel.id)
        }
      }
    }

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
