//
//  Updater.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Combine
import OSLog
import SwiftUI

// OpenUpdater updates *itself* through Sparkle — its own download/replace flow can't
// replace the running app, but Sparkle's relaunch helper can. Other apps are still
// updated through the recipe system. The `canImport` guard keeps the project building
// before the Sparkle package is added (the stub just disables the update controls).

#if canImport(Sparkle)
  import Sparkle

  /// Bridges Sparkle's "about to relaunch to install" callback to a flag. A separate
  /// object (not `Updater`) so it can be the updater delegate without a self-reference
  /// during `Updater.init`; Sparkle holds the delegate weakly, so `Updater` retains it.
  private final class RelaunchObserver: NSObject, SPUUpdaterDelegate {
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
      Updater.isRelaunchingForUpdate = true
    }
  }

  /// SwiftUI-facing wrapper around Sparkle's standard updater.
  @MainActor
  final class Updater: ObservableObject {
    /// Set by Sparkle immediately before it relaunches the app to install a
    /// self-update. The app checks this to skip its quit confirmation for that
    /// (intentional) termination. Only touched on the main thread.
    nonisolated(unsafe) static var isRelaunchingForUpdate = false

    private let relaunchObserver = RelaunchObserver()
    private let controller: SPUStandardUpdaterController
    /// True once the updater is idle and ready to check (drives the menu/button state).
    @Published var canCheckForUpdates = false
    /// Mirrors Sparkle's automatic-check preference (persisted by Sparkle itself).
    @Published var automaticallyChecksForUpdates: Bool

    private static let log = Logger(subsystem: "dev.casraf.OpenUpdater", category: "sparkle")

    init() {
      controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: relaunchObserver, userDriverDelegate: nil)
      automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
      let updater = controller.updater
      Self.log.notice(
        "Sparkle init: feedURL=\(String(describing: updater.feedURL), privacy: .public) canCheck=\(updater.canCheckForUpdates, privacy: .public) auto=\(updater.automaticallyChecksForUpdates, privacy: .public)"
      )
      updater.publisher(for: \.canCheckForUpdates)
        .sink { Self.log.notice("Sparkle canCheckForUpdates -> \($0, privacy: .public)") }
        .store(in: &cancellables)
      updater.publisher(for: \.canCheckForUpdates)
        .assign(to: &$canCheckForUpdates)
    }

    private var cancellables = Set<AnyCancellable>()

    func checkForUpdates() { controller.updater.checkForUpdates() }

    func setAutomaticChecks(_ enabled: Bool) {
      controller.updater.automaticallyChecksForUpdates = enabled
      automaticallyChecksForUpdates = enabled
    }
  }
#else
  /// Stub used until the Sparkle package is added, so the app keeps building.
  @MainActor
  final class Updater: ObservableObject {
    /// No self-update without Sparkle; always false so the quit confirmation applies.
    nonisolated(unsafe) static var isRelaunchingForUpdate = false
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false
    func checkForUpdates() {}
    func setAutomaticChecks(_ enabled: Bool) {}
  }
#endif
