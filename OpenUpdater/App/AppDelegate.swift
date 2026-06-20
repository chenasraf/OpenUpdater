//
//  AppDelegate.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    /// Single shared model layer, owned here so both the AppKit popover and the
    /// SwiftUI scene can read from the same instance.
    let updateManager = UpdateManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient // closes when clicking away
        popover.contentViewController = NSHostingController(
            rootView: ContentView(openMainWindow: openMainWindow)
                .environmentObject(updateManager)
        )

        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle.fill",
                                   accessibilityDescription: "App Updates")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Kick off the initial check at launch so the popover, main window, and
        // (later) the menubar badge all reflect available updates immediately.
        Task { await updateManager.checkForUpdatesIfNeeded() }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func openMainWindow() {
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}
