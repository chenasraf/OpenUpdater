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
    }
}
