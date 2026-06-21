//
//  OpenUpdaterApp.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import SwiftUI

/// The app's display name — one source of truth for the product name (window
/// title, menubar, quit dialog, network User-Agent). `nonisolated` so it's also
/// reachable from off-main code like `Installer`. No "OpenUpdater" literals
/// anywhere else.
nonisolated enum AppBranding {
  static let title = "OpenUpdater"
  /// The project's GitHub repository — used for "report an app" links, etc.
  static let repositoryURL = URL(string: "https://github.com/chenasraf/OpenUpdater")!
}

@main
struct OpenUpdaterApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Window(AppBranding.title, id: "main") {
      MainWindowView()
        .environmentObject(appDelegate.updateManager)
    }
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unified)
    .defaultSize(width: 800, height: 550)
    .commands {
      // Rename the standard "Settings…" item to "Preferences…" (still ⌘,). Preferences
      // is a regular Window (not a Settings scene) so it can be resized.
      CommandGroup(replacing: .appSettings) {
        OpenPreferencesButton()
      }
    }

    Window("Preferences", id: PreferencesWindow.id) {
      SettingsView()
        .environmentObject(appDelegate.updateManager)
    }
    .windowResizability(.contentMinSize)
    .defaultSize(width: 820, height: 560)
  }
}

enum PreferencesWindow {
  static let id = "preferences"
}

/// The "Preferences…" menu command (⌘,). A small view so it can use `openWindow`.
private struct OpenPreferencesButton: View {
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Button("Preferences…") { openWindow(id: PreferencesWindow.id) }
      .keyboardShortcut(",", modifiers: .command)
  }
}
