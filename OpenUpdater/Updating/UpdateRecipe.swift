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
  /// Mutable so `applyingChannel` can overlay a release channel's overrides onto a
  /// copy; the decoded value is otherwise treated as read-only.
  var check: Check
  var download: Download?
  /// Optional release streams (e.g. Stable / ESR / LTS). When present, the user picks
  /// one per app; the chosen channel's `check`/`download` overlay the base ones. The
  /// first channel is the default. Omit entirely for single-stream apps.
  let channels: [Channel]?
  /// Custom recipes only: when `false`, the recipe is ignored (built-in/auto sources
  /// take over). Absent means enabled. Built-in recipes never set this.
  let enabled: Bool?
  /// Whether this recipe is active. `enabled` absent → treated as enabled.
  var isEnabled: Bool { enabled ?? true }
  /// Maps the host arch (`arm64` / `x86_64`) to this app's arch string for the
  /// `{arch}` placeholder. Omit when the app uses `arm64`/`x86_64` verbatim.
  let arch: [String: String]?

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
    // github_releases tag filtering — skip rolling tags ("continuous"/"nightly") or
    // restrict to versioned ones. Applied before picking the newest release.
    let tagPattern: String?  // only releases whose tag matches this regex are considered
    let tagIgnore: String?  // releases whose tag matches this regex are skipped

    // Generic html/xml/json sources:
    let url: String?  // page/API to fetch
    let pattern: String?  // html/xml: regex, capture group 1 = version
    let path: String?  // json: dotted key path (supports array indices)
    let downloadPattern: String?  // html/xml: regex, capture group 1 = download URL
    let downloadPath: String?  // json: key path to a download URL
    // When a `pattern` matches several times, which match to use (html/xml only).
    let select: Select
    // Placeholders resolved from other pages before the check runs, substituted as
    // `{name}` into this check's `url` (and the download/changelog templates). Lets a
    // recipe discover a value — e.g. the current release series — instead of pinning it.
    let resolve: [String: ResolveStep]?

    enum CodingKeys: String, CodingKey {
      case kind = "type"
      case repo
      case feed
      case prereleases
      case tagPattern = "tag_pattern"
      case tagIgnore = "tag_ignore"
      case url
      case pattern
      case path
      case downloadPattern = "download_pattern"
      case downloadPath = "download_path"
      case select
      case resolve
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      kind = try container.decode(Kind.self, forKey: .kind)
      repo = try container.decodeIfPresent(String.self, forKey: .repo)
      feed = try container.decodeIfPresent(String.self, forKey: .feed)
      prereleases = try container.decodeIfPresent(Bool.self, forKey: .prereleases) ?? false
      tagPattern = try container.decodeIfPresent(String.self, forKey: .tagPattern)
      tagIgnore = try container.decodeIfPresent(String.self, forKey: .tagIgnore)
      url = try container.decodeIfPresent(String.self, forKey: .url)
      pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
      path = try container.decodeIfPresent(String.self, forKey: .path)
      downloadPattern = try container.decodeIfPresent(String.self, forKey: .downloadPattern)
      downloadPath = try container.decodeIfPresent(String.self, forKey: .downloadPath)
      select = try container.decodeIfPresent(Select.self, forKey: .select) ?? .first
      resolve = try container.decodeIfPresent([String: ResolveStep].self, forKey: .resolve)
    }

    /// Whether a release tag passes this recipe's tag filters. A tag must match
    /// `tag_pattern` (when set) and must not match `tag_ignore` (when set).
    func tagAllowed(_ tag: String) -> Bool {
      if let tagPattern, !Self.regexMatches(tag, tagPattern) { return false }
      if let tagIgnore, Self.regexMatches(tag, tagIgnore) { return false }
      return true
    }

    private static func regexMatches(_ string: String, _ pattern: String) -> Bool {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
      return regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }
  }

  /// Which match to take when a regex matches more than once.
  enum Select: String, Decodable {
    case first  // the first match in document order (default)
    case latest  // the highest version among all matches
  }

  /// A pre-fetch step that discovers a placeholder value from another page. The
  /// `url` is fetched as text, `pattern`'s first capture group is extracted, and
  /// `select` decides which match to use when there are several.
  struct ResolveStep: Decodable {
    let url: String
    let pattern: String
    let select: Select

    enum CodingKeys: String, CodingKey {
      case url
      case pattern
      case select
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      url = try container.decode(String.self, forKey: .url)
      pattern = try container.decode(String.self, forKey: .pattern)
      select = try container.decodeIfPresent(Select.self, forKey: .select) ?? .first
    }
  }

  /// A selectable release stream. `check`/`download`, when present, replace the
  /// recipe's base blocks for this channel; absent fields inherit the base.
  struct Channel: Decodable {
    let id: String
    let name: String?
    let check: Check?
    let download: Download?

    /// Label shown in the UI; falls back to the id when no `name` is given.
    var displayName: String { name ?? id }
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
    let urlTemplate: String?  // optional: omit when the URL comes from download_pattern/path
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

  // MARK: - Release channels

  /// The recipe's channels, or an empty list when it defines none.
  var channelList: [Channel] { channels ?? [] }

  /// The id of the default channel (the first one), or `nil` when none are defined.
  var defaultChannelID: String? { channels?.first?.id }

  /// Resolve a channel by id, falling back to the default (first) channel. Returns
  /// `nil` only when the recipe declares no channels.
  func channel(id: String?) -> Channel? {
    guard let channels, !channels.isEmpty else { return nil }
    if let id, let match = channels.first(where: { $0.id == id }) { return match }
    return channels.first
  }

  /// A copy of this recipe with the selected channel's `check`/`download` overlaid.
  /// Absent channel fields keep the base values; no channels means an unchanged copy.
  func applyingChannel(_ channelID: String?) -> UpdateRecipe {
    guard let channel = channel(id: channelID) else { return self }
    var copy = self
    if let check = channel.check { copy.check = check }
    if let download = channel.download { copy.download = download }
    return copy
  }

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

  /// This app's arch string for the running Mac (e.g. `arm64`, `x64`, `aarch64`).
  var archString: String {
    arch?[SystemArch.current] ?? SystemArch.current
  }

  /// Replace the `{arch}` placeholder — usable on feed URLs, regex patterns, and
  /// JSON key paths that don't carry `{tag}`/`{version}`.
  func resolveArch(_ template: String) -> String {
    template.replacingOccurrences(of: "{arch}", with: archString)
  }

  /// Expand `{tag}`, `{version}`, `{major}`/`{minor}`/`{patch}`, and `{arch}`
  /// placeholders. (For a major.minor folder, write `{major}.{minor}`.)
  func expand(_ template: String, tag: String, version: String) -> String {
    let parts = version.split(separator: ".").map(String.init)
    return resolveArch(template)
      .replacingOccurrences(of: "{tag}", with: tag)
      .replacingOccurrences(of: "{version}", with: version)
      .replacingOccurrences(of: "{major}", with: parts.first ?? "")
      .replacingOccurrences(of: "{minor}", with: parts.count > 1 ? parts[1] : "")
      .replacingOccurrences(of: "{patch}", with: parts.count > 2 ? parts[2] : "")
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

  /// The highest of several version-ish strings, comparing every run of digits in
  /// turn (so `4-5` > `4-2`, `4.5.10` > `4.5.9`). Ties keep the earlier value.
  /// Returns `nil` for an empty input.
  static func highest(_ versions: [String]) -> String? {
    versions.max { looseComponents($0).lexicographicallyPrecedes(looseComponents($1)) }
  }

  /// Every run of digits in a string, as integers (e.g. `4-5` → `[4, 5]`). Unlike
  /// `numericComponents` this ignores all non-digit separators, so it orders series
  /// labels and dotted versions alike.
  private static func looseComponents(_ value: String) -> [Int] {
    value.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
  }

  private static func numericComponents(_ version: String) -> [Int] {
    // Tolerate a leading "v" (e.g. an installed version of "v2.0.3").
    var remaining = Substring(version)
    if let first = remaining.first, first == "v" || first == "V" {
      remaining = remaining.dropFirst()
    }
    var components: [Int] = []
    for part in remaining.split(separator: ".") {
      let digits = part.prefix { $0.isNumber }
      guard !digits.isEmpty else { break }
      components.append(Int(digits) ?? 0)
      if digits.count != part.count { break }  // hit a suffix like "3-Beta"
    }
    return components
  }
}
