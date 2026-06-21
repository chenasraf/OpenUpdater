//
//  UpdateRecipe.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation
import Yams

/// A single app's update recipe, decoded from its `<bundle-id>.yml` file.
struct UpdateRecipe: Decodable {
  let id: String
  let name: String?
  let homepage: String?
  let check: Check
  let download: Download?

  private let version: VersionRule?
  private let changelog: Changelog?

  struct Check: Decodable {
    enum Kind: String, Decodable {
      case githubReleases = "github_releases"
      case sparkle
      case html  // fetch a page, extract version via regex
      case xml  // fetch XML, extract version via regex
      case json  // fetch JSON, extract version via a key path
      case yaml  // fetch YAML (e.g. electron latest-mac.yml), extract via a key path
    }
    let kind: Kind
    let repo: String?  // github_releases
    let feed: String?  // sparkle (explicit appcast URL, for apps without a static SUFeedURL)
    let prereleases: Bool

    // Generic html/xml/json sources:
    let url: String?  // page/API to fetch
    let pattern: String?  // html/xml: regex, capture group 1 = version
    let path: String?  // json: dotted key path (supports array indices)
    let downloadPattern: String?  // html/xml: regex, capture group 1 = download URL
    let downloadPath: String?  // json: key path to a download URL

    enum CodingKeys: String, CodingKey {
      case kind = "type"
      case repo
      case feed
      case prereleases
      case url
      case pattern
      case path
      case downloadPattern = "download_pattern"
      case downloadPath = "download_path"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      kind = try container.decode(Kind.self, forKey: .kind)
      repo = try container.decodeIfPresent(String.self, forKey: .repo)
      feed = try container.decodeIfPresent(String.self, forKey: .feed)
      prereleases = try container.decodeIfPresent(Bool.self, forKey: .prereleases) ?? false
      url = try container.decodeIfPresent(String.self, forKey: .url)
      pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
      path = try container.decodeIfPresent(String.self, forKey: .path)
      downloadPattern = try container.decodeIfPresent(String.self, forKey: .downloadPattern)
      downloadPath = try container.decodeIfPresent(String.self, forKey: .downloadPath)
    }
  }

  struct VersionRule: Decodable {
    let stripPrefix: String?
    let pattern: String?

    enum CodingKeys: String, CodingKey {
      case stripPrefix = "strip_prefix"
      case pattern
    }
  }

  struct Download: Decodable {
    let urlTemplate: String
    let format: String?

    enum CodingKeys: String, CodingKey {
      case urlTemplate = "url"
      case format
    }
  }

  private struct Changelog: Decodable {
    let url: String
  }

  /// Changelog URL template, or `nil` if the recipe omits one.
  var changelogTemplate: String? { changelog?.url }

  private var versionRule: VersionRule { version ?? VersionRule(stripPrefix: nil, pattern: nil) }

  /// Turn a raw release tag (e.g. `v0.20.3-Beta`) into a comparable version string.
  func normalizeVersion(fromTag tag: String) -> String {
    var value = tag
    let rule = versionRule
    if let prefix = rule.stripPrefix, !prefix.isEmpty, value.hasPrefix(prefix) {
      value.removeFirst(prefix.count)
    }
    if let pattern = rule.pattern, !pattern.isEmpty,
      let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
      match.numberOfRanges > 1,
      let range = Range(match.range(at: 1), in: value)
    {
      value = String(value[range])
    }
    return value
  }

  /// Expand `{tag}` and `{version}` placeholders in a URL template.
  func expand(_ template: String, tag: String, version: String) -> String {
    template
      .replacingOccurrences(of: "{tag}", with: tag)
      .replacingOccurrences(of: "{version}", with: version)
  }
}

/// Loads every recipe bundled under `Recipes/`, keyed by bundle identifier.
enum RecipeStore {
  static func loadAll() -> [String: UpdateRecipe] {
    // Look both in a "Recipes" subdirectory and at the Resources root: Xcode's
    // synchronized groups flatten the folder into the bundle root, while a plain
    // group would preserve it. These calls return an EMPTY array (not nil) when
    // nothing matches, so we must merge both — a `??` fall-through would stop at
    // the first empty result and miss the flattened files.
    var urls = Bundle.main.urls(forResourcesWithExtension: "yml", subdirectory: "Recipes") ?? []
    urls += Bundle.main.urls(forResourcesWithExtension: "yml", subdirectory: nil) ?? []

    let decoder = YAMLDecoder()
    var seen = Set<String>()
    var recipes: [String: UpdateRecipe] = [:]
    for url in urls where seen.insert(url.lastPathComponent).inserted {
      do {
        let text = try String(contentsOf: url, encoding: .utf8)
        let recipe = try decoder.decode(UpdateRecipe.self, from: text)
        recipes[recipe.id] = recipe
      } catch {
        // Skip a malformed recipe rather than failing the whole load.
        continue
      }
    }
    return recipes
  }
}

/// Compares dotted version strings.
enum VersionCompare {
  /// True when `latest` is a strictly newer release than `installed`.
  ///
  /// Only the leading run of dot-separated integers is compared; trailing
  /// suffixes such as `-Beta` are ignored, so two identical builds are never
  /// flagged as an update.
  static func isNewer(_ latest: String, than installed: String) -> Bool {
    let lhs = numericComponents(latest)
    let rhs = numericComponents(installed)
    for index in 0..<Swift.max(lhs.count, rhs.count) {
      let l = index < lhs.count ? lhs[index] : 0
      let r = index < rhs.count ? rhs[index] : 0
      if l != r { return l > r }
    }
    return false
  }

  private static func numericComponents(_ version: String) -> [Int] {
    var components: [Int] = []
    for part in version.split(separator: ".") {
      let digits = part.prefix { $0.isNumber }
      guard !digits.isEmpty else { break }
      components.append(Int(digits) ?? 0)
      if digits.count != part.count { break }  // hit a suffix like "3-Beta"
    }
    return components
  }
}
