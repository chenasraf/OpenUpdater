//
//  CheckCache.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation

/// Persisted update-check results, so the last-known state shows instantly at launch —
/// before the background re-check finishes. Keyed by bundle id.
struct CheckCache: Codable {
  var lastChecked: Date?
  var apps: [String: Entry]

  /// The resolved fields for one app, mirroring the update-relevant parts of `AppInfo`.
  struct Entry: Codable {
    var latestVersion: String?
    var latestBuild: String?
    var changelogURL: URL?
    var homepageURL: URL?
    var downloadURL: URL?
    var downloadFormat: String?
    var appStoreURL: URL?
    var source: UpdateSource
  }
}

/// Reads/writes the check cache at `~/Library/Application Support/<app>/check-cache.json`.
enum CheckCacheStore {
  private static var fileURL: URL {
    let base =
      (try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    return base.appendingPathComponent("\(AppBranding.title)/check-cache.json")
  }

  static func load() -> CheckCache? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(CheckCache.self, from: data)
  }

  static func save(_ cache: CheckCache) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(cache) else { return }
    try? FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }
}
