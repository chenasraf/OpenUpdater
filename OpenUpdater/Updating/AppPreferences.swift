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
  /// Selected release channel id (e.g. `stable`/`esr`). `nil` → the recipe's default
  /// channel (its first). Ignored when the recipe defines no channels.
  var channel: String?
  /// Never show this app as updatable.
  var ignored: Bool?
  /// Don't offer this specific version (reappears when a newer one ships).
  var ignoredVersion: String?
  /// Hide this app's updates until this moment; they reappear on their own afterwards.
  var snoozedUntil: Date?
  /// Whether to auto-install major-version upgrades for this app. `nil` → the default,
  /// which is "no" for apps whose recipe sets `manual_major_upgrades` and "yes" for
  /// everything else.
  var allowMajorUpgrades: Bool?

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

/// How long a snooze hides an app's updates.
enum SnoozeDuration: CaseIterable, Identifiable {
  case oneDay, threeDays, oneWeek, twoWeeks, oneMonth

  var id: Self { self }

  var label: String {
    switch self {
    case .oneDay: return "1 Day"
    case .threeDays: return "3 Days"
    case .oneWeek: return "1 Week"
    case .twoWeeks: return "2 Weeks"
    case .oneMonth: return "1 Month"
    }
  }

  /// When a snooze started at `start` ends.
  func end(from start: Date) -> Date {
    let calendar = Calendar.current
    let end: Date?
    switch self {
    case .oneDay: end = calendar.date(byAdding: .day, value: 1, to: start)
    case .threeDays: end = calendar.date(byAdding: .day, value: 3, to: start)
    case .oneWeek: end = calendar.date(byAdding: .day, value: 7, to: start)
    case .twoWeeks: end = calendar.date(byAdding: .day, value: 14, to: start)
    case .oneMonth: end = calendar.date(byAdding: .month, value: 1, to: start)
    }
    return end ?? start
  }
}
