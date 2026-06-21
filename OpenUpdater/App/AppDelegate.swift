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

  /// The SwiftUI main window. Retained (kept out of the release-on-close path) so
  /// Cmd-W only hides it and the menubar can bring it back later.
  private weak var mainWindow: NSWindow?

  /// Single shared model layer, owned here so both the AppKit popover and the
  /// SwiftUI scene can read from the same instance.
  let updateManager = UpdateManager()

  /// Sparkle-backed self-updater. Owned here (not as an App `@StateObject`) so it's
  /// created eagerly at launch — a menubar app opens no window, so a lazy
  /// `@StateObject` would never start Sparkle.
  let updater = Updater()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Start menubar-only (no Dock icon). The Dock icon appears only while a real
    // window is open — see syncActivationPolicy().
    NSApp.setActivationPolicy(.accessory)

    // Create the popover. It sizes to the SwiftUI content's preferred size, so the
    // in-popover resize handle (which persists width/height) drives it.
    popover = NSPopover()
    popover.behavior = .transient  // closes when clicking away
    popover.animates = false  // immediate, so live-resize doesn't jitter
    let savedWidth = UserDefaults.standard.double(forKey: "popoverWidth")
    let savedHeight = UserDefaults.standard.double(forKey: "popoverHeight")
    popover.contentSize = NSSize(
      width: savedWidth > 0 ? savedWidth : 460, height: savedHeight > 0 ? savedHeight : 560)
    let hosting = NSHostingController(
      rootView: ContentView(openMainWindow: openMainWindow).environmentObject(updateManager))
    hosting.sizingOptions = [.preferredContentSize]
    popover.contentViewController = hosting

    // Create the status bar item
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      // The app's own glyph as a template image, so it tints for light/dark menubars.
      let icon = NSImage(named: "MenuBarIcon")
      icon?.isTemplate = true
      icon?.size = NSSize(width: 18, height: 18)
      button.image = icon
      button.image?.accessibilityDescription = AppBranding.title
      button.action = #selector(togglePopover)
      button.target = self
    }

    // Track window lifecycle: the Dock icon follows window visibility, and a
    // closed main window can be reopened from the menubar.
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(windowDidBecomeMain(_:)),
      name: NSWindow.didBecomeMainNotification, object: nil)
    center.addObserver(
      self, selector: #selector(windowWillClose(_:)),
      name: NSWindow.willCloseNotification, object: nil)

    // Kick off the initial check at launch so the popover, main window, and
    // (later) the menubar badge all reflect available updates immediately.
    Task { await updateManager.checkForUpdatesIfNeeded() }
  }

  // MARK: - Dock icon follows window visibility

  /// True for the app's real windows (the SwiftUI `Window` / Settings), as opposed
  /// to the status-bar popover panel or the status item itself.
  private func isAppWindow(_ window: NSWindow) -> Bool {
    window.styleMask.contains(.titled) && !(window is NSPanel)
  }

  @objc private func windowDidBecomeMain(_ note: Notification) {
    guard let window = note.object as? NSWindow, isAppWindow(window) else { return }
    if window.title == AppBranding.title {
      // Keep it alive across Cmd-W so the menubar can reopen the same window.
      window.isReleasedWhenClosed = false
      mainWindow = window
    }
    syncActivationPolicy()
  }

  @objc private func windowWillClose(_ note: Notification) {
    guard let window = note.object as? NSWindow, isAppWindow(window) else { return }
    // Re-evaluate once the window has actually gone away.
    DispatchQueue.main.async { [weak self] in self?.syncActivationPolicy() }
  }

  /// Show the Dock icon while any real window is on screen; drop back to
  /// menubar-only when none are.
  private func syncActivationPolicy() {
    let hasWindow = NSApp.windows.contains { $0.isVisible && isAppWindow($0) }
    NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
  }

  // MARK: - Quit behavior

  /// Closing the last window leaves the app running in the menubar; it only quits
  /// via Cmd-Q / the Quit button (which go through applicationShouldTerminate).
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// Confirm before quitting — quitting stops background update checks entirely.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Quit \(AppBranding.title)?"
    alert.informativeText =
      "\(AppBranding.title) will stop checking for app updates in the background."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
  }

  // MARK: - Status item / window

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
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    let window = mainWindow ?? NSApp.windows.first(where: isAppWindow)
    window?.makeKeyAndOrderFront(nil)
  }
}

extension Notification.Name {
  static let openMainWindow = Notification.Name("openMainWindow")
}
