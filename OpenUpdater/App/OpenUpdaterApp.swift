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
      // Rename the standard "Settings…" item to "Preferences…" (still ⌘,).
      // SettingsLink is the only supported way to open the Settings scene.
      CommandGroup(replacing: .appSettings) {
        SettingsLink {
          Text("Preferences…")
        }
        .keyboardShortcut(",", modifiers: .command)
      }
    }

    Settings {
      SettingsView()
        .environmentObject(appDelegate.updateManager)
    }
  }
}
