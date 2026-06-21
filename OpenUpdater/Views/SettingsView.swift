//
//  SettingsView.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  enum Tab: String, CaseIterable, Identifiable {
    case general, updating, ignoreList, unsupported
    var id: String { rawValue }
    var title: String {
      switch self {
      case .general: return "General"
      case .updating: return "Updating"
      case .ignoreList: return "Ignore List"
      case .unsupported: return "Unsupported"
      }
    }
    var icon: String {
      switch self {
      case .general: return "gearshape"
      case .updating: return "arrow.triangle.2.circlepath"
      case .ignoreList: return "nosign"
      case .unsupported: return "questionmark.circle"
      }
    }
  }

  @State private var selection: Tab = .general

  var body: some View {
    NavigationSplitView {
      List(Tab.allCases, selection: $selection) { tab in
        Label(tab.title, systemImage: tab.icon).tag(tab)
      }
      .navigationSplitViewColumnWidth(170)
    } detail: {
      switch selection {
      case .general: GeneralSettingsView()
      case .updating: UpdatingSettingsView()
      case .ignoreList: IgnoreListView()
      case .unsupported: UnsupportedAppsView()
      }
    }
    .navigationTitle("Preferences")
    .frame(minWidth: 580, minHeight: 360)
  }
}

struct GeneralSettingsView: View {
  var body: some View {
    Form {
      Text("General settings coming soon.")
        .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
  }
}

struct IgnoreListView: View {
  @EnvironmentObject private var updateManager: UpdateManager

  var body: some View {
    Group {
      if updateManager.ignoredApps.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "nosign").font(.system(size: 40)).foregroundStyle(.secondary)
          Text("No ignored apps").font(.title3)
          Text("Right-click an app and choose Ignore to add it here.")
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(updateManager.ignoredApps) { app in
          HStack(spacing: 10) {
            AppIcon(app: app, size: 28)
            VStack(alignment: .leading, spacing: 2) {
              Text(app.name)
              Text(ignoreDescription(app)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if app.builtInIgnoreReason != nil {
              Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .help("Always ignored by \(AppBranding.title)")
            } else {
              Button("Remove") { updateManager.clearIgnore(for: app) }
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  private func ignoreDescription(_ app: AppInfo) -> String {
    if let reason = app.builtInIgnoreReason { return reason }
    if app.ignored { return "Ignored by user" }
    if let version = app.ignoredVersion { return "Version \(version) ignored by user" }
    return ""
  }
}

/// Lists apps with no update source — candidates for new community recipes — and
/// offers ways to share the list so coverage can be improved.
struct UnsupportedAppsView: View {
  @EnvironmentObject private var updateManager: UpdateManager
  @State private var copied = false

  private var apps: [AppInfo] { updateManager.unsupportedApps }

  var body: some View {
    Group {
      if apps.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(.green)
          Text("Every app has an update source").font(.title3)
          Text("Nothing to report — \(AppBranding.title) can check all your installed apps.")
            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
      } else {
        VStack(spacing: 0) {
          Text(
            "^[\(apps.count) app](inflect: true) with no known update source. Report them or contribute a recipe to expand coverage."
          )
          .font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal).padding(.vertical, 10)

          Divider()

          List(apps) { app in
            HStack(spacing: 10) {
              AppIcon(app: app, size: 28)
              VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(app.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
              }
              Spacer()
            }
            .padding(.vertical, 2)
          }
        }
        .safeAreaInset(edge: .bottom) {
          HStack {
            Button {
              copyBundleIDs()
            } label: {
              Label(copied ? "Copied" : "Copy Bundle IDs", systemImage: "doc.on.clipboard")
            }
            Button {
              exportToFile()
            } label: {
              Label("Export…", systemImage: "square.and.arrow.down")
            }
            Spacer()
            Button {
              reportOnGitHub()
            } label: {
              Label("Report on GitHub…", systemImage: "exclamationmark.bubble")
            }
            .buttonStyle(.borderedProminent)
          }
          .padding(12)
          .background(.bar)
        }
      }
    }
  }

  /// Bundle ids, one per line — the payload for copy/export.
  private func bundleIDList() -> String {
    apps.map(\.id).joined(separator: "\n")
  }

  private func copyBundleIDs() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(bundleIDList(), forType: .string)
    copied = true
    Task {
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      copied = false
    }
  }

  private func exportToFile() {
    let panel = NSSavePanel()
    panel.title = "Export Unsupported Apps"
    panel.nameFieldStringValue = "openupdater-unsupported.txt"
    panel.allowedContentTypes = [.plainText]
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? bundleIDList().write(to: url, atomically: true, encoding: .utf8)
  }

  private func reportOnGitHub() {
    guard let url = issueURL() else { return }
    NSWorkspace.shared.open(url)
  }

  /// A prefilled "new issue" URL listing the unsupported apps.
  private func issueURL() -> URL? {
    let title = "Add update sources for \(apps.count) app\(apps.count == 1 ? "" : "s")"
    let lines = apps.map { "- \($0.name) (`\($0.id)`)" }.joined(separator: "\n")
    let body = """
      The following installed apps have no update source in \(AppBranding.title) yet:

      \(lines)
      """
    var components = URLComponents(
      url: AppBranding.repositoryURL.appendingPathComponent("issues/new"),
      resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "title", value: title),
      URLQueryItem(name: "body", value: body),
    ]
    return components?.url
  }
}

struct UpdatingSettingsView: View {
  @EnvironmentObject private var updateManager: UpdateManager
  @State private var token: String
  @State private var hasStoredToken: Bool
  @State private var status: String?
  @State private var helperStatus: SMAppService.Status = .notRegistered
  @State private var helperMessage: String?

  init() {
    // Load at construction so the field is populated on first render — onAppear
    // is unreliable for a Settings detail pane.
    let existing = GitHubToken.load() ?? ""
    _token = State(initialValue: existing)
    _hasStoredToken = State(initialValue: !existing.isEmpty)
  }

  var body: some View {
    Form {
      Section {
        SecureField("Personal access token", text: $token)

        HStack {
          Button("Save") {
            let ok = GitHubToken.save(token)
            hasStoredToken = GitHubToken.exists
            if ok {
              // Re-check now so the new token takes effect immediately.
              status = "Saved — re-checking…"
              Task { await updateManager.checkForUpdates() }
            } else {
              status = "Couldn't save."
            }
          }
          .keyboardShortcut(.defaultAction)
          .disabled(updateManager.isChecking)

          if hasStoredToken {
            Button("Remove", role: .destructive) {
              GitHubToken.clear()
              token = ""
              hasStoredToken = false
              status = "Removed."
            }
          }

          if let status {
            Text(status).font(.caption).foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("GitHub Access Token")
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            "Raises GitHub's API limit from 60 to 5,000 requests/hour for update checks. "
              + "A classic token with no scopes (or a fine-grained token with public read) is enough. "
              + "It's stored encrypted in your Keychain."
          )
          Link(
            "Create a token on GitHub…",
            destination: URL(
              string: "https://github.com/settings/tokens/new?description=\(AppBranding.title)")!
          )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section {
        HStack {
          Text(helperStatusText)
          Spacer()
          if helperStatus == .enabled {
            Button("Remove", role: .destructive) {
              Task {
                try? await PrivilegedHelper.shared.unregister()
                refreshHelperStatus()
              }
            }
          } else {
            Button("Install Helper…") { installHelper() }
          }
        }
        if let helperMessage {
          Text(helperMessage).font(.caption).foregroundStyle(.secondary)
        }
      } header: {
        Text("Background Helper")
      } footer: {
        Text(
          "Installs updates without asking for your password each time. You approve it "
            + "once in System Settings → Login Items, then pkg installs and protected apps "
            + "update silently."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .onAppear(perform: refreshHelperStatus)
  }

  private var helperStatusText: String {
    switch helperStatus {
    case .enabled: return "Installed and enabled"
    case .requiresApproval: return "Waiting for approval in System Settings"
    case .notRegistered: return "Not installed"
    case .notFound: return "Not available in this build"
    @unknown default: return "Unknown"
    }
  }

  private func refreshHelperStatus() {
    helperStatus = PrivilegedHelper.shared.status
  }

  private func installHelper() {
    do {
      let status = try PrivilegedHelper.shared.register()
      helperStatus = status
      if status == .requiresApproval {
        helperMessage = "Approve \(AppBranding.title) under Login Items to finish."
        SMAppService.openSystemSettingsLoginItems()
      } else if status == .enabled {
        helperMessage = "Helper installed."
      }
    } catch {
      helperStatus = PrivilegedHelper.shared.status
      helperMessage = "Couldn't install the helper: \(error.localizedDescription)"
    }
  }
}
