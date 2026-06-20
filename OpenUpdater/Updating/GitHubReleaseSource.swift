//
//  GitHubReleaseSource.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation

enum UpdateCheckError: Error, CustomStringConvertible {
  case unsupported
  case missingRepo
  case missingFeed
  case rateLimited
  case badResponse(Int)
  case noReleases

  var description: String {
    switch self {
    case .unsupported: return "unsupported source type"
    case .missingRepo: return "recipe is missing a repo"
    case .missingFeed: return "recipe is missing a feed URL"
    case .rateLimited: return "GitHub rate limit reached"
    case .badResponse(let code): return "HTTP \(code)"
    case .noReleases: return "no matching release"
    }
  }

  /// Whether this error reflects a transient/environmental problem (vs. a bad recipe).
  var isTransient: Bool {
    switch self {
    case .rateLimited, .badResponse: return true
    case .unsupported, .missingRepo, .missingFeed, .noReleases: return false
    }
  }
}

/// The latest release discovered for an app.
struct ReleaseResult {
  /// Raw tag, e.g. `v0.20.3-Beta`.
  let tag: String
  /// Normalized, comparable marketing version, e.g. `0.20.3-Beta`.
  let version: String
  /// Build number (`CFBundleVersion`), when the source reports one (Sparkle).
  /// Used for comparison since marketing strings can be non-monotonic.
  var build: String?
  /// Release-notes link supplied directly by the source (e.g. a Sparkle appcast).
  /// `nil` lets the caller fall back to a recipe's changelog template.
  var changelogURL: URL?
  /// Where to download the new build, when known.
  var downloadURL: URL?
  /// Archive format of `downloadURL` (`dmg`/`zip`/`pkg`), when known.
  var format: String?
}

/// Resolves the latest version of an app from its GitHub Releases feed.
enum GitHubReleaseSource {
  private struct Release: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case draft, prerelease
    }
  }

  static func latest(for recipe: UpdateRecipe) async throws -> ReleaseResult {
    guard recipe.check.kind == .githubReleases else { throw UpdateCheckError.unsupported }
    guard let repo = recipe.check.repo,
      let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")
    else {
      throw UpdateCheckError.missingRepo
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("OpenUpdater", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.badResponse(-1) }
    guard http.statusCode == 200 else {
      // GitHub reports rate limiting as 403/429 with no remaining quota.
      if http.statusCode == 403 || http.statusCode == 429,
        http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
      {
        throw UpdateCheckError.rateLimited
      }
      throw UpdateCheckError.badResponse(http.statusCode)
    }

    let releases = try JSONDecoder().decode([Release].self, from: data)
    // GitHub returns releases newest-first; take the first publishable one.
    guard
      let chosen = releases.first(where: {
        !$0.draft && (recipe.check.prereleases || !$0.prerelease)
      })
    else {
      throw UpdateCheckError.noReleases
    }

    let version = recipe.normalizeVersion(fromTag: chosen.tagName)
    var downloadURL: URL?
    if let download = recipe.download {
      downloadURL = URL(
        string: recipe.expand(download.urlTemplate, tag: chosen.tagName, version: version))
    }
    return ReleaseResult(
      tag: chosen.tagName,
      version: version,
      downloadURL: downloadURL,
      format: recipe.download?.format
    )
  }
}
