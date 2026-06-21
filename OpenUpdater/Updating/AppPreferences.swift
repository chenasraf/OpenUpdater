//
//  AppPreferences.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation

/// Per-app user settings, persisted (as JSON) in UserDefaults keyed by bundle id.
/// Add new fields here as more per-app options appear — keep them optional so an
/// unset value falls back to the recipe/source default.
struct AppPreferences: Codable {
  /// Include pre-releases for this app. `nil` → use the recipe's `prereleases` default.
  var includePrereleases: Bool?

  // MARK: Persistence

  private static let keyPrefix = "app-prefs."

  static func load(for id: String) -> AppPreferences {
    guard let data = UserDefaults.standard.data(forKey: keyPrefix + id),
      let prefs = try? JSONDecoder().decode(AppPreferences.self, from: data)
    else { return AppPreferences() }
    return prefs
  }

  func save(for id: String) {
    if let data = try? JSONEncoder().encode(self) {
      UserDefaults.standard.set(data, forKey: Self.keyPrefix + id)
    }
  }

  /// Load, mutate, and save in one step.
  static func update(_ id: String, _ change: (inout AppPreferences) -> Void) {
    var prefs = load(for: id)
    change(&prefs)
    prefs.save(for: id)
  }
}
