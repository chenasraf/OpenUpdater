//
//  OpenUpdaterApp.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import SwiftUI

@main
struct OpenUpdaterApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Window("App Updates", id: "main") {
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
