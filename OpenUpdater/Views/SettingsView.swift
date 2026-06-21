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
    case general, updating, ignoreList, unsupported, customRecipes
    var id: String { rawValue }
    var title: String {
      switch self {
      case .general: return "General"
      case .updating: return "Updating"
      case .ignoreList: return "Ignore List"
      case .unsupported: return "Unsupported"
      case .customRecipes: return "Custom Recipes"
      }
    }
    var icon: String {
      switch self {
      case .general: return "gearshape"
      case .updating: return "arrow.triangle.2.circlepath"
      case .ignoreList: return "nosign"
      case .unsupported: return "questionmark.circle"
      case .customRecipes: return "doc.badge.plus"
      }
    }
  }

  @EnvironmentObject private var updateManager: UpdateManager
  @State private var selection: Tab = .general
  @State private var customSelection: String?

  var body: some View {
    HStack(spacing: 0) {
      List(Tab.allCases, selection: $selection) { tab in
        Label(tab.title, systemImage: tab.icon).tag(tab)
      }
      .listStyle(.sidebar)
      .frame(width: 180)

      Divider()

      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(
      minWidth: 680, idealWidth: 820, maxWidth: .infinity,
      minHeight: 440, idealHeight: 560, maxHeight: .infinity)
  }

  @ViewBuilder private var detail: some View {
    switch selection {
    case .general: GeneralSettingsView()
    case .updating: UpdatingSettingsView()
    case .ignoreList: IgnoreListView()
    case .unsupported: UnsupportedAppsView(onCreateRecipe: createRecipe)
    case .customRecipes: CustomRecipesView(selectedID: $customSelection)
    }
  }

  /// Create a draft custom recipe for an app and jump to the Custom Recipes tab.
  private func createRecipe(for app: AppInfo) {
    customSelection = updateManager.createCustomRecipeDraft(for: app)
    selection = .customRecipes
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
  let onCreateRecipe: (AppInfo) -> Void
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
              Menu {
                Button("Create Custom Recipe") { onCreateRecipe(app) }
                Button("Request on GitHub…") {
                  updateManager.openRecipeIssue(name: app.name, bundleID: app.id)
                }
              } label: {
                Image(systemName: "ellipsis.circle")
              }
              .menuStyle(.borderlessButton)
              .fixedSize()
              .help("Create a custom recipe, or request one on GitHub")
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
              Label("Report All…", systemImage: "exclamationmark.bubble")
            }
            .help("Open one issue listing every unsupported app")
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

/// Lists the user's custom recipes (stored in Application Support) and edits them.
/// An enabled, valid recipe overrides the built-in one for the same bundle id.
struct CustomRecipesView: View {
  @EnvironmentObject private var updateManager: UpdateManager
  @Binding var selectedID: String?
  /// The live editor buffer for the selected recipe (may differ from disk = unsaved).
  @State private var draftText = ""

  private var recipes: [CustomRecipe] { updateManager.customRecipes }
  private var selected: CustomRecipe? { recipes.first { $0.id == selectedID } }
  private var isDirty: Bool { selected.map { draftText != $0.text } ?? false }
  private var parseError: String? { selected == nil ? nil : CustomRecipeStore.validate(draftText) }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Custom Recipes").font(.headline)
        Spacer()
        Button {
          selectedID = updateManager.createCustomRecipe()
        } label: {
          Label("New Recipe", systemImage: "plus")
        }
      }
      .padding(.horizontal).padding(.vertical, 8)

      Divider()

      if recipes.isEmpty {
        emptyState
      } else {
        HSplitView {
          List(recipes, selection: $selectedID) { recipe in
            row(recipe)
          }
          .frame(minWidth: 200, idealWidth: 240, maxWidth: 340)

          Group {
            if let selected {
              editor(selected)
            } else {
              Text("Select a recipe to edit.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
          .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .onAppear(perform: syncDraft)
    .onChange(of: selectedID) { _, _ in syncDraft() }
  }

  /// Load the selected recipe's on-disk text into the editor buffer.
  private func syncDraft() {
    draftText = selected?.text ?? ""
  }

  /// Enable/disable: persist only the `enabled:` line to disk (not other unsaved
  /// edits), and mirror that one-line change into the live buffer so editor edits
  /// in progress are preserved.
  private func setEnabled(_ enabled: Bool, _ recipe: CustomRecipe) {
    updateManager.setCustomRecipeEnabled(enabled, recipe)
    if recipe.id == selectedID {
      draftText = CustomRecipeStore.text(draftText, settingEnabled: enabled)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "doc.badge.plus").font(.system(size: 40)).foregroundStyle(.secondary)
      Text("No custom recipes").font(.title3)
      Text(
        "Add your own recipe to cover an app \(AppBranding.title) doesn't yet — or to "
          + "override a built-in one."
      )
      .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("New Recipe") { selectedID = updateManager.createCustomRecipe() }
        .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
  }

  private func row(_ recipe: CustomRecipe) -> some View {
    HStack(spacing: 8) {
      Toggle(
        "",
        isOn: Binding(
          get: { recipe.enabled },
          set: { setEnabled($0, recipe) }
        )
      )
      .labelsHidden().toggleStyle(.switch).controlSize(.mini)
      .disabled(recipe.parseError != nil)
      .help(recipe.parseError != nil ? "Fix errors before enabling" : "Enable or disable")

      VStack(alignment: .leading, spacing: 1) {
        Text(recipe.name ?? recipe.id).lineLimit(1)
        Text(recipe.id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 4)
      if recipe.parseError != nil {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange).help(recipe.parseError ?? "")
      } else if recipe.overridesBuiltIn {
        Image(systemName: "square.2.layers.3d.top.filled")
          .foregroundStyle(.secondary).help("Overrides a built-in recipe")
      }
    }
  }

  private func editor(_ recipe: CustomRecipe) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      TextEditor(text: $draftText)
        .font(.system(.body, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

      if let parseError {
        Label(parseError, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange).font(.caption).lineLimit(2)
      } else {
        Label("Valid recipe", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green).font(.caption)
      }

      HStack {
        Button("Save") {
          selectedID = updateManager.saveCustomRecipe(
            text: draftText, originalStem: recipe.fileStem)
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!isDirty)

        Button("Delete", role: .destructive) {
          updateManager.deleteCustomRecipe(recipe)
          selectedID = nil
        }
        Spacer()
        Button("Submit Recipe…") {
          let decoded = CustomRecipeStore.decoded(draftText)
          updateManager.openRecipeIssue(
            name: decoded?.name ?? recipe.id, bundleID: decoded?.id ?? recipe.id, recipe: draftText)
        }
        .disabled(parseError != nil)
        .help("Open a pre-filled GitHub issue with this recipe")
      }
    }
    .padding()
  }
}
