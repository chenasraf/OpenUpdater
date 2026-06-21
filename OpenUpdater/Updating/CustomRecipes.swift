//
//  CustomRecipes.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation
import Yams

/// A user-provided recipe stored under Application Support, listed and editable in
/// Preferences. Custom recipes layer over the built-in set: an enabled, valid one
/// whose `id` matches a built-in (or an app's bundle id) overrides it.
struct CustomRecipe: Identifiable, Equatable {
  /// The recipe's bundle id — its decoded `id`, or the filename stem if it doesn't
  /// parse. Also the key used to override a built-in recipe.
  var id: String
  /// On-disk file (named `<stem>.yml`).
  var url: URL
  /// Raw YAML text.
  var text: String
  /// Decoded display name, when the recipe parses.
  var name: String?
  var enabled: Bool
  /// A short message when the YAML isn't a valid recipe; `nil` when it's fine.
  var parseError: String?
  /// True when this id also has a built-in recipe (so it overrides it).
  var overridesBuiltIn: Bool

  /// The filename stem (independent of the decoded `id`).
  var fileStem: String { url.deletingPathExtension().lastPathComponent }
}

/// File I/O for custom recipes under `~/Library/Application Support/<app>/Recipes`.
enum CustomRecipeStore {
  static var directory: URL {
    let base =
      (try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    return base.appendingPathComponent("\(AppBranding.title)/Recipes", isDirectory: true)
  }

  static func ensureDirectory() {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  static func fileURL(forStem stem: String) -> URL {
    directory.appendingPathComponent("\(stem).yml")
  }

  /// Read and decode every custom recipe file. `builtInIDs` flags which ones override.
  static func loadAll(builtInIDs: Set<String>) -> [CustomRecipe] {
    ensureDirectory()
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    else { return [] }

    let decoder = YAMLDecoder()
    var result: [CustomRecipe] = []
    for url in urls where url.pathExtension == "yml" {
      let stem = url.deletingPathExtension().lastPathComponent
      let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      var id = stem
      var name: String?
      var enabled = true
      var parseError: String?
      do {
        let recipe = try decoder.decode(UpdateRecipe.self, from: text)
        id = recipe.id
        name = recipe.name
        enabled = recipe.isEnabled
      } catch {
        parseError = friendly(error)
      }
      result.append(
        CustomRecipe(
          id: id, url: url, text: text, name: name, enabled: enabled,
          parseError: parseError, overridesBuiltIn: builtInIDs.contains(id)))
    }
    return result.sorted {
      ($0.name ?? $0.id).localizedCaseInsensitiveCompare($1.name ?? $1.id) == .orderedAscending
    }
  }

  static func write(_ text: String, toStem stem: String) throws {
    ensureDirectory()
    try text.write(to: fileURL(forStem: stem), atomically: true, encoding: .utf8)
  }

  static func deleteStem(_ stem: String) {
    try? FileManager.default.removeItem(at: fileURL(forStem: stem))
  }

  /// Decode recipe YAML, or `nil` if it's invalid.
  static func decoded(_ text: String) -> UpdateRecipe? {
    try? YAMLDecoder().decode(UpdateRecipe.self, from: text)
  }

  /// Validate recipe YAML; returns a short error message or `nil` when it's valid.
  static func validate(_ text: String) -> String? {
    do {
      _ = try YAMLDecoder().decode(UpdateRecipe.self, from: text)
      return nil
    } catch {
      return friendly(error)
    }
  }

  /// Return `text` with its `enabled:` flag set, replacing an existing line or
  /// appending one.
  static func text(_ text: String, settingEnabled enabled: Bool) -> String {
    let line = "enabled: \(enabled)"
    let range = NSRange(text.startIndex..., in: text)
    if let regex = try? NSRegularExpression(pattern: "(?m)^enabled:[ \\t]*.*$"),
      regex.firstMatch(in: text, range: range) != nil
    {
      return regex.stringByReplacingMatches(in: text, range: range, withTemplate: line)
    }
    return text + (text.hasSuffix("\n") ? "" : "\n") + line + "\n"
  }

  /// A starter recipe for a new app — disabled until the author fills it in.
  static func draft(id: String, name: String) -> String {
    """
    id: \(id)
    name: \(name)
    homepage: https://example.com

    check:
      type: github_releases
      repo: owner/name

    download:
      url: https://github.com/owner/name/releases/download/{tag}/App-{version}.dmg
      format: dmg

    changelog:
      url: https://github.com/owner/name/releases/tag/{tag}

    enabled: false
    """
  }

  private static func friendly(_ error: Error) -> String {
    String(describing: error).split(separator: "\n").first.map(String.init) ?? "Invalid YAML"
  }
}
