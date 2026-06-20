//
//  SparkleSource.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation

/// One `<item>` parsed from a Sparkle appcast.
private struct AppcastItem {
  var title: String?
  var shortVersion: String?  // sparkle:shortVersionString (marketing version)
  var version: String?  // sparkle:version (build number)
  var releaseNotesLink: String?
  var minimumSystemVersion: String?
  var channel: String?  // Sparkle 2 channel (e.g. "beta"); nil == default/stable
  var os: String?  // enclosure sparkle:os; nil == macos
  var downloadURL: String?  // enclosure url (full build, not a delta)

  /// Human-facing version for display: marketing string preferred.
  var displayVersion: String? { (shortVersion?.isEmpty == false) ? shortVersion : version }

  /// Comparison key: build number preferred (monotonic), else marketing version.
  var sortKey: String? {
    let value = (version?.isEmpty == false) ? version : shortVersion
    return (value?.isEmpty == false) ? value : nil
  }
}

/// Minimal SAX parser for the Sparkle appcast RSS format.
///
/// Namespace processing is left off, so elements/attributes arrive as qualified
/// names (`sparkle:version`, `enclosure`, …), which is exactly what we match on.
private final class AppcastParser: NSObject, XMLParserDelegate {
  private var items: [AppcastItem] = []
  private var current: AppcastItem?
  private var text = ""

  func parse(_ data: Data) -> [AppcastItem] {
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.parse()
    return items
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String,
    namespaceURI: String?, qualifiedName: String?, attributes: [String: String]
  ) {
    text = ""
    switch elementName {
    case "item":
      current = AppcastItem()
    case "enclosure":
      // Version info often lives on the enclosure; child elements (handled
      // below) take precedence when present.
      if current?.shortVersion == nil {
        current?.shortVersion = attributes["sparkle:shortVersionString"]
      }
      if current?.version == nil { current?.version = attributes["sparkle:version"] }
      current?.os = attributes["sparkle:os"]
      // Prefer the full build's URL, ignoring binary-delta enclosures.
      if attributes["sparkle:deltaFrom"] == nil, current?.downloadURL == nil {
        current?.downloadURL = attributes["url"]
      }
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  func parser(
    _ parser: XMLParser, didEndElement elementName: String,
    namespaceURI: String?, qualifiedName: String?
  ) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch elementName {
    case "title" where current != nil && current?.title == nil:
      current?.title = trimmed
    case "sparkle:shortVersionString" where !trimmed.isEmpty:
      current?.shortVersion = trimmed
    case "sparkle:version" where !trimmed.isEmpty:
      current?.version = trimmed
    case "sparkle:releaseNotesLink":
      current?.releaseNotesLink = trimmed
    case "sparkle:minimumSystemVersion":
      current?.minimumSystemVersion = trimmed
    case "sparkle:channel":
      current?.channel = trimmed
    case "item":
      if let current { items.append(current) }
      current = nil
    default:
      break
    }
    text = ""
  }
}

/// Resolves the latest version of an app from its Sparkle appcast feed.
enum SparkleSource {
  static func latest(feedURL: URL) async throws -> ReleaseResult {
    var request = URLRequest(url: feedURL)
    request.setValue("OpenUpdater", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.badResponse(-1) }
    guard http.statusCode == 200 else { throw UpdateCheckError.badResponse(http.statusCode) }

    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    let osString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

    let eligible = AppcastParser().parse(data).filter { item in
      guard item.sortKey != nil else { return false }
      // Default channel and macOS only.
      guard item.channel == nil, item.os == nil || item.os == "macos" else { return false }
      // Skip builds that need a newer macOS than we're running.
      if let minimum = item.minimumSystemVersion, VersionCompare.isNewer(minimum, than: osString) {
        return false
      }
      return true
    }

    // Pick the newest by build number (sortKey) — appcasts are usually
    // newest-first, but don't rely on it. The build is more reliable than the
    // marketing string, which can be a git hash or otherwise non-monotonic.
    guard
      let best = eligible.max(by: {
        VersionCompare.isNewer($1.sortKey!, than: $0.sortKey!)
      })
    else {
      throw UpdateCheckError.noReleases
    }

    let downloadURL = best.downloadURL.flatMap(URL.init(string:))
    return ReleaseResult(
      tag: best.displayVersion ?? best.sortKey!,
      version: best.displayVersion ?? best.sortKey!,
      build: best.version,
      changelogURL: best.releaseNotesLink.flatMap(URL.init(string:)),
      downloadURL: downloadURL,
      format: downloadURL.flatMap { ArchiveFormat(inferringFrom: $0)?.rawValue }
    )
  }
}
