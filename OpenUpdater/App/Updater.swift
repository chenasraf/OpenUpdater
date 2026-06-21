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

  /// SwiftUI-facing wrapper around Sparkle's standard updater.
  @MainActor
  final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    /// True once the updater is idle and ready to check (drives the menu/button state).
    @Published var canCheckForUpdates = false
    /// Mirrors Sparkle's automatic-check preference (persisted by Sparkle itself).
    @Published var automaticallyChecksForUpdates: Bool

    private static let log = Logger(subsystem: "dev.casraf.OpenUpdater", category: "sparkle")

    init() {
      controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false
    func checkForUpdates() {}
    func setAutomaticChecks(_ enabled: Bool) {}
  }
#endif
