//
//  AppDelegate.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import AppKit
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  var statusItem: NSStatusItem!
  var popover: NSPopover!

  /// The SwiftUI main window. Retained (kept out of the release-on-close path) so
  /// Cmd-W only hides it and the menubar can bring it back later.
  private weak var mainWindow: NSWindow?

  /// Keeps the menubar badge in sync with the model's update count.
  private var cancellables: Set<AnyCancellable> = []

  /// Single shared model layer, owned here so both the AppKit popover and the
  /// SwiftUI scene can read from the same instance.
  let updateManager = UpdateManager()

  /// Sparkle-backed self-updater. Owned here (not as an App `@StateObject`) so it's
  /// created eagerly at launch — a menubar app opens no window, so a lazy
  /// `@StateObject` would never start Sparkle.
  let updater = Updater()

  /// SwiftUI's `openWindow`, captured from the scene at launch so AppKit code (the
  /// menubar popover) can open scene-managed windows like Preferences by id.
  var openWindowByID: ((String) -> Void)?

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
      rootView: ContentView(openMainWindow: openMainWindow, openPreferences: openPreferences)
        .environmentObject(updateManager))
    hosting.sizingOptions = [.preferredContentSize]
    popover.contentViewController = hosting

    // Create the status bar item
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      // The app's own glyph as a template image, so it tints for light/dark menubars.
      // Fall back to an SF Symbol if the asset can't be loaded — otherwise the button
      // would have no image and (at zero updates) no title, collapsing to a zero-width,
      // effectively invisible status item.
      let icon =
        NSImage(named: "MenuBarIcon")
        ?? NSImage(
          systemSymbolName: "arrow.down.app", accessibilityDescription: AppBranding.title)
      icon?.isTemplate = true
      icon?.size = NSSize(width: 18, height: 18)
      button.image = icon
      button.image?.accessibilityDescription = AppBranding.title
      button.action = #selector(togglePopover)
      button.target = self
    }

    // Force the item visible. `isVisible` is persisted across launches, so an item
    // that was ⌘-dragged off the menu bar (or dropped when the bar was full) stays
    // hidden forever otherwise — and the status item is this menubar app's primary
    // entry point, so a stuck-hidden state would lock the user out.
    statusItem.isVisible = true

    // Show the number of available updates next to the menubar glyph, kept in sync
    // with the model. `objectWillChange` fires before the value updates, so receive
    // on the main run loop to read the settled count.
    updateManager.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.updateMenuBarBadge() }
      .store(in: &cancellables)
    updateMenuBarBadge()

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

    // "Open main window on launch" (default on). SwiftUI always presents the single
    // `Window` at launch (and macOS may restore it), and `.defaultLaunchBehavior` is
    // overridden by sticky per-scene state — so when the preference is off we close the
    // window as it appears. Polling briefly catches both the auto-open and a restore.
    let openOnLaunch =
      UserDefaults.standard.object(forKey: "openMainWindowOnLaunch") as? Bool ?? true
    if !openOnLaunch {
      suppressLaunchWindow = true
      closeLaunchWindowIfNeeded(retries: 30)
    }
  }

  /// While set, the main window is kept closed at launch (the "open on launch" pref is
  /// off). Cleared the moment the user opens the window from the menubar/⌘.
  private var suppressLaunchWindow = false

  /// Close the launch/restored main window while `suppressLaunchWindow` holds, polling
  /// for ~3s so it catches the window whenever SwiftUI or state restoration presents it.
  private func closeLaunchWindowIfNeeded(retries: Int) {
    guard suppressLaunchWindow, retries > 0 else { return }
    if let window = NSApp.windows.first(where: { isAppWindow($0) && $0.title == AppBranding.title }
    ),
      window.isVisible
    {
      window.close()
      syncActivationPolicy()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.closeLaunchWindowIfNeeded(retries: retries - 1)
    }
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

  /// Append the available-update count to the status-bar glyph (hidden when zero).
  private func updateMenuBarBadge() {
    guard let button = statusItem?.button else { return }
    let count = updateManager.updates.count
    if count > 0 {
      button.title = " \(count)"
      button.imagePosition = .imageLeft
    } else {
      button.title = ""
      button.imagePosition = .imageOnly
    }
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
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    // Re-enable opening the launch window if it was suppressed earlier.
    suppressLaunchWindow = false
    let window = mainWindow ?? NSApp.windows.first(where: isAppWindow)
    window?.makeKeyAndOrderFront(nil)
  }

  /// Open the SwiftUI Preferences window from the menubar popover. It's scene-managed,
  /// so bring an existing one forward, otherwise trigger its menu command (⌘,) to create it.
  func openPreferences() {
    popover.performClose(nil)
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == PreferencesWindow.id })
    {
      window.makeKeyAndOrderFront(nil)
      return
    }
    openWindowByID?(PreferencesWindow.id)
  }
}
