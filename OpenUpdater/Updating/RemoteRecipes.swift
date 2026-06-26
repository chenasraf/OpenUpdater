//
//  RemoteRecipes.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 26/06/2026.
//

import Foundation
import Yams
import os

/// Syncs the crowdsourced recipe set from GitHub at runtime, so coverage improves
/// without an app update. The canonical recipes live in the repo under
/// `OpenUpdater/Recipes`; a generated `RecipeManifest.json` (hash + per-recipe minimum
/// app version) is the index. Downloaded recipes are mirrored into Application Support
/// and layered over the built-in set (see `UpdateManager.rebuildActiveRecipes`).
///
/// Change detection compares the manifest `hash` as an OPAQUE token against the one we
/// last synced — the app never recomputes it, so it can't disagree with the generator.
/// The stored state also records the app version: after an app update (which may add an
/// engine feature) we re-sync so recipes that were previously gated out get pulled.
///
/// `nonisolated` — all I/O and networking, driven via `await` from `UpdateManager`; this
/// keeps the downloads and file writes off the main actor.
nonisolated enum RemoteRecipeStore {
  private static let rawBase =
    "https://raw.githubusercontent.com/chenasraf/OpenUpdater/master/OpenUpdater"
  private static let log = Logger(subsystem: "dev.casraf.OpenUpdater", category: "recipes")

  struct Manifest: Codable {
    let hash: String
    let recipes: [Entry]
    struct Entry: Codable {
      let file: String
      let minApp: String
      let sha: String
    }
  }

  /// What we last synced — the manifest plus the app version it was synced for.
  private struct SyncState: Codable {
    let hash: String
    let appVersion: String
    let recipes: [Manifest.Entry]
  }

  // MARK: - Locations

  /// `~/Library/Application Support/OpenUpdater/RemoteRecipes` (sibling of the custom
  /// recipes folder).
  static var directory: URL {
    appSupportRoot.appendingPathComponent("RemoteRecipes", isDirectory: true)
  }

  private static var stateURL: URL {
    appSupportRoot.appendingPathComponent("RemoteRecipes.state.json")
  }

  private static var appSupportRoot: URL {
    let base =
      (try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    return base.appendingPathComponent(AppBranding.title, isDirectory: true)
  }

  private static func ensureDirectory() {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  // MARK: - Loading

  /// Decode every downloaded recipe, skipping any that fail (the belt-and-suspenders
  /// behind the manifest's `minApp` gating — a recipe the engine can't parse is dropped,
  /// and the built-in copy remains in effect).
  static func loadAll() -> [String: UpdateRecipe] {
    let decoder = YAMLDecoder()
    var recipes: [String: UpdateRecipe] = [:]
    for url in recipeFiles() {
      guard let text = try? String(contentsOf: url, encoding: .utf8),
        let recipe = try? decoder.decode(UpdateRecipe.self, from: text)
      else { continue }
      recipes[recipe.id] = recipe
    }
    return recipes
  }

  private static func recipeFiles() -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
      ?? []).filter { $0.pathExtension == "yml" }
  }

  /// Delete every downloaded recipe and the sync state, so the next sync re-downloads
  /// the full set from scratch. Used by the "Reset downloaded recipes" action.
  static func clear() {
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.removeItem(at: stateURL)
  }

  // MARK: - Sync

  /// Fetch the manifest and, if it differs from what we last synced (or the app version
  /// changed), download the recipes this app version supports. Best-effort: any failure
  /// (offline, GitHub down, bad response) returns `false` and never throws, so it can't
  /// block an update check. Returns `true` when the local recipe set changed.
  static func sync(appVersion: String) async -> Bool {
    do {
      let manifest = try await fetchManifest()
      let state = loadState()
      if manifest.hash == state?.hash, appVersion == state?.appVersion { return false }

      // Only activate recipes this app version can actually run.
      let compatible = manifest.recipes.filter {
        !VersionCompare.isNewer($0.minApp, than: appVersion)
      }
      let priorSHA = Dictionary(
        (state?.recipes ?? []).map { ($0.file, $0.sha) }, uniquingKeysWith: { a, _ in a })

      ensureDirectory()
      // (Re)download only what's new, changed, or missing on disk.
      let toFetch = compatible.filter { entry in
        priorSHA[entry.file] != entry.sha
          || !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(entry.file).path)
      }
      try await downloadAll(toFetch)

      // Drop anything no longer compatible/listed.
      let wanted = Set(compatible.map(\.file))
      for url in recipeFiles() where !wanted.contains(url.lastPathComponent) {
        try? FileManager.default.removeItem(at: url)
      }

      saveState(SyncState(hash: manifest.hash, appVersion: appVersion, recipes: manifest.recipes))
      log.notice(
        "Recipe sync: \(toFetch.count, privacy: .public) downloaded, \(compatible.count, privacy: .public) active, hash \(manifest.hash, privacy: .public)"
      )
      return true
    } catch {
      log.error("Recipe sync failed: \(String(describing: error), privacy: .public)")
      return false
    }
  }

  /// Download `entries` into `directory` with bounded concurrency, writing each file
  /// atomically as it arrives. Throws on the first failure (leaving state unsaved, so the
  /// next sync retries).
  private static func downloadAll(_ entries: [Manifest.Entry]) async throws {
    guard !entries.isEmpty else { return }
    let maxConcurrent = 8
    try await withThrowingTaskGroup(of: (String, Data).self) { group in
      var iterator = entries.makeIterator()
      func addNext() {
        guard let entry = iterator.next() else { return }
        let url = recipeURL(entry.file)
        let file = entry.file
        group.addTask { (file, try await fetch(url)) }
      }
      for _ in 0..<maxConcurrent { addNext() }
      while let (file, data) = try await group.next() {
        try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        addNext()
      }
    }
  }

  // MARK: - State persistence

  private static func loadState() -> SyncState? {
    guard let data = try? Data(contentsOf: stateURL) else { return nil }
    return try? JSONDecoder().decode(SyncState.self, from: data)
  }

  private static func saveState(_ state: SyncState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    try? data.write(to: stateURL, options: .atomic)
  }

  // MARK: - Networking

  static var manifestURL: URL { URL(string: "\(rawBase)/RecipeManifest.json")! }
  private static func recipeURL(_ file: String) -> URL {
    URL(string: "\(rawBase)/Recipes/\(file)")!
  }

  private static func fetchManifest() async throws -> Manifest {
    try JSONDecoder().decode(Manifest.self, from: await fetch(manifestURL))
  }

  /// GET with the app's User-Agent; throws on a non-200 response.
  private static func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue(AppBranding.title, forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    return data
  }
}
