//
//  SettingsView.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import SwiftUI

struct SettingsView: View {
  enum Tab: String, CaseIterable, Identifiable {
    case general, updating
    var id: String { rawValue }
    var title: String { self == .general ? "General" : "Updating" }
    var icon: String { self == .general ? "gearshape" : "arrow.triangle.2.circlepath" }
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

struct UpdatingSettingsView: View {
  @EnvironmentObject private var updateManager: UpdateManager
  @State private var token: String
  @State private var hasStoredToken: Bool
  @State private var status: String?

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
              string: "https://github.com/settings/tokens/new?description=OpenUpdater")!
          )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}
