//
//  HTTPVersionSource.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation
import Yams

/// Generic version checks for apps that aren't on GitHub or Sparkle: fetch a URL
/// and extract the version (and optionally a download URL) from the response.
///
///   - `html` / `xml`: a regex whose first capture group is the value.
///   - `json` / `yaml`: a dotted key path (supports array indices, e.g. `files.0.url`).
///     `yaml` handles electron-builder `latest-mac.yml` feeds.
///
/// The download URL comes from the recipe's `download.url` template (preferred)
/// or, failing that, from a `download_pattern` / `download_path` on the same
/// response — enabling plain HTTP(S) downloads. An extracted download may be a
/// relative path; it's resolved against the check URL.
enum HTTPVersionSource {
  static func latest(for recipe: UpdateRecipe) async throws -> ReleaseResult {
    // Resolve any `{name}` placeholders from their own pages first, then substitute
    // them into the check URL (and, later, the download/changelog templates).
    let resolved = try await resolvePlaceholders(recipe.check.resolve)

    guard let rawURL = recipe.check.url,
      let url = URL(string: applyPlaceholders(recipe.resolveArch(rawURL), resolved))
    else {
      throw UpdateCheckError.missingURL
    }

    let data = try await fetch(url)

    let rawVersion: String
    let extractedDownload: String?

    switch recipe.check.kind {
    case .json, .yaml:
      let root: Any
      if recipe.check.kind == .yaml {
        guard let parsed = try Yams.load(yaml: String(data: data, encoding: .utf8) ?? "") else {
          throw UpdateCheckError.extractionFailed("version")
        }
        root = parsed
      } else {
        root = try JSONSerialization.jsonObject(with: data)
      }
      guard let path = recipe.check.path,
        let value = Self.keyPathValue(at: recipe.resolveArch(path), in: root)
      else {
        throw UpdateCheckError.extractionFailed("version")
      }
      rawVersion = value
      extractedDownload = recipe.check.downloadPath.flatMap {
        Self.keyPathValue(at: recipe.resolveArch($0), in: root)
      }

    case .html, .xml:
      let body = String(data: data, encoding: .utf8) ?? ""
      guard let pattern = recipe.check.pattern,
        let value = Self.selectCapture(pattern, in: body, select: recipe.check.select)
      else {
        throw UpdateCheckError.extractionFailed("version")
      }
      rawVersion = value
      extractedDownload = recipe.check.downloadPattern.flatMap {
        Self.firstCapture(recipe.resolveArch($0), in: body)
      }

    default:
      throw UpdateCheckError.unsupported
    }

    let version = recipe.normalizeVersion(fromTag: rawVersion)

    // Download URL: recipe template wins; otherwise use what we extracted
    // (resolved against the check URL, since electron feeds give a relative path).
    var downloadURL: URL?
    if let template = recipe.download?.urlTemplate {
      let expanded = applyPlaceholders(
        recipe.expand(template, tag: rawVersion, version: version), resolved)
      downloadURL = URL(string: expanded)
    } else if let extractedDownload {
      downloadURL = Self.resolveURL(extractedDownload, relativeTo: url)
    }

    let format =
      recipe.download?.format
      ?? downloadURL.flatMap { ArchiveFormat(inferringFrom: $0)?.rawValue }

    var changelogURL: URL?
    if let template = recipe.changelogTemplate {
      let expanded = applyPlaceholders(
        recipe.expand(template, tag: rawVersion, version: version), resolved)
      changelogURL = URL(string: expanded)
    }

    return ReleaseResult(
      tag: rawVersion,
      version: version,
      changelogURL: changelogURL,
      downloadURL: downloadURL,
      format: format
    )
  }

  /// GET a URL with the app's User-Agent, returning its body or throwing on a
  /// non-200 response.
  private static func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue(AppBranding.title, forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.badResponse(-1) }
    guard http.statusCode == 200 else { throw UpdateCheckError.badResponse(http.statusCode) }
    return data
  }

  /// Run each `resolve` step (fetch its page, extract its capture) into a map of
  /// placeholder name → value, ready to substitute into the check's templates.
  private static func resolvePlaceholders(
    _ steps: [String: UpdateRecipe.ResolveStep]?
  ) async throws -> [String: String] {
    guard let steps else { return [:] }
    var values: [String: String] = [:]
    for (name, step) in steps {
      guard let url = URL(string: step.url) else { throw UpdateCheckError.missingURL }
      let body = String(data: try await fetch(url), encoding: .utf8) ?? ""
      guard let value = selectCapture(step.pattern, in: body, select: step.select) else {
        throw UpdateCheckError.extractionFailed(name)
      }
      values[name] = value
    }
    return values
  }

  /// Substitute `{name}` placeholders with their resolved values.
  private static func applyPlaceholders(_ template: String, _ values: [String: String]) -> String {
    values.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
  }

  /// All first-capture-group matches of `pattern` in `text`, in document order.
  static func allCaptures(_ pattern: String, in text: String) -> [String] {
    guard
      let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      guard match.numberOfRanges > 1, let captured = Range(match.range(at: 1), in: text) else {
        return nil
      }
      return String(text[captured])
    }
  }

  /// Pick one capture per the `select` rule: the first match, or the highest version.
  static func selectCapture(
    _ pattern: String, in text: String, select: UpdateRecipe.Select
  ) -> String? {
    let captures = allCaptures(pattern, in: text)
    switch select {
    case .first: return captures.first
    case .latest: return VersionCompare.highest(captures)
    }
  }

  /// Follow a dotted key path through parsed JSON or YAML, returning a stringified
  /// scalar. Supports array indices and both `[String: Any]` and the
  /// `[AnyHashable: Any]` maps that Yams produces.
  static func keyPathValue(at path: String, in root: Any) -> String? {
    var current: Any? = root
    for component in path.split(separator: ".") {
      if let index = Int(component), let array = current as? [Any] {
        current = index < array.count ? array[index] : nil
      } else if let dict = current as? [String: Any] {
        current = dict[String(component)]
      } else if let dict = current as? [AnyHashable: Any] {
        current = dict[String(component)]
      } else {
        return nil
      }
    }
    switch current {
    case let string as String: return string
    case let number as NSNumber: return number.stringValue
    default: return nil
    }
  }

  /// Turn an extracted download reference into a URL. Handles absolute URLs,
  /// relative paths (resolved against `base`), and values containing spaces.
  static func resolveURL(_ value: String, relativeTo base: URL) -> URL? {
    if let absolute = URL(string: value), absolute.scheme != nil { return absolute }
    let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    if let absolute = URL(string: encoded), absolute.scheme != nil { return absolute }
    return URL(string: encoded, relativeTo: base)?.absoluteURL
  }

  /// First capture group of `pattern` in `text`, or `nil`.
  static func firstCapture(_ pattern: String, in text: String) -> String? {
    guard
      let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
      match.numberOfRanges > 1,
      let captured = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[captured])
  }
}
