//
//  GitHubReleaseSource.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation

/// Context captured at the point a check fails, so the in-app log can show what
/// was actually requested and what we tried to read — request URL, HTTP method
/// and status, and (for parse failures) the field and the pattern/key path used.
struct CheckContext {
  var url: URL?
  var method: String = "GET"
  var statusCode: Int?
  /// What we tried to read out of the response (e.g. "version", a placeholder name).
  var extracting: String?
  /// The regex pattern or JSON/YAML key path used to read it.
  var selector: String?
  /// The precise cause, phrased for the user — e.g. "the pattern matched nothing in
  /// the response" or "no value at that key path". Distinguishes a recipe mistake
  /// (bad regex/path) from an environmental failure.
  var note: String?

  init(
    url: URL? = nil, method: String = "GET", statusCode: Int? = nil,
    extracting: String? = nil, selector: String? = nil, note: String? = nil
  ) {
    self.url = url
    self.method = method
    self.statusCode = statusCode
    self.extracting = extracting
    self.selector = selector
    self.note = note
  }
}

enum UpdateCheckError: Error, CustomStringConvertible {
  case unsupported
  case missingRepo
  case missingFeed
  case missingURL
  case extractionFailed(String, CheckContext)
  case rateLimited
  case badResponse(Int, CheckContext)
  case transport(Error, CheckContext)
  case noReleases

  var description: String {
    switch self {
    case .unsupported: return "unsupported source type"
    case .missingRepo: return "recipe is missing a repo"
    case .missingFeed: return "recipe is missing a feed URL"
    case .missingURL: return "recipe is missing a url"
    case .extractionFailed(let what, _): return "couldn't extract \(what)"
    case .rateLimited: return "GitHub rate limit reached"
    case .badResponse(let code, _): return code < 0 ? "not an HTTP response" : "HTTP \(code)"
    case .transport(let error, _): return (error as NSError).localizedDescription
    case .noReleases: return "no matching release"
    }
  }

  /// Whether this error reflects a transient/environmental problem (vs. a bad recipe).
  var isTransient: Bool {
    switch self {
    case .rateLimited, .badResponse, .transport: return true
    case .unsupported, .missingRepo, .missingFeed, .missingURL, .extractionFailed, .noReleases:
      return false
    }
  }

  /// The request/parse context, when this error carries one.
  var context: CheckContext? {
    switch self {
    case .badResponse(_, let context), .extractionFailed(_, let context),
      .transport(_, let context):
      return context
    case .unsupported, .missingRepo, .missingFeed, .missingURL, .rateLimited, .noReleases:
      return nil
    }
  }
}

/// Shared HTTP layer for the version sources: sends a request with the app's
/// User-Agent and maps transport and malformed-response failures into
/// `UpdateCheckError`s that carry the request URL and method for the log.
enum HTTPClient {
  static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let context = CheckContext(url: request.url, method: request.httpMethod ?? "GET")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch let error as UpdateCheckError {
      throw error
    } catch {
      throw UpdateCheckError.transport(error, context)
    }
    guard let http = response as? HTTPURLResponse else {
      throw UpdateCheckError.badResponse(-1, context)
    }
    return (data, http)
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
  /// For Mac App Store apps: the `macappstore://` URL to open the product page.
  var appStoreURL: URL?
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

  static func latest(for recipe: UpdateRecipe, includePrereleases: Bool) async throws
    -> ReleaseResult
  {
    guard recipe.check.kind == .githubReleases else { throw UpdateCheckError.unsupported }
    guard let repo = recipe.check.repo,
      let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")
    else {
      throw UpdateCheckError.missingRepo
    }

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue(AppBranding.title, forHTTPHeaderField: "User-Agent")
    // An optional personal access token lifts the limit from 60 to 5,000 req/hr.
    if let token = GitHubToken.load() {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, http) = try await HTTPClient.send(request)
    guard http.statusCode == 200 else {
      // GitHub reports rate limiting as 403/429 with no remaining quota.
      if http.statusCode == 403 || http.statusCode == 429,
        http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
      {
        throw UpdateCheckError.rateLimited
      }
      throw UpdateCheckError.badResponse(
        http.statusCode, CheckContext(url: url, statusCode: http.statusCode))
    }

    let releases = try JSONDecoder().decode([Release].self, from: data)
    // GitHub returns releases newest-first; take the first publishable one that also
    // passes the recipe's tag filters (so rolling tags like "continuous" are skipped).
    guard
      let chosen = releases.first(where: {
        !$0.draft && (includePrereleases || !$0.prerelease) && recipe.check.tagAllowed($0.tagName)
      })
    else {
      throw UpdateCheckError.noReleases
    }

    let version = recipe.normalizeVersion(fromTag: chosen.tagName)
    var downloadURL: URL?
    if let template = recipe.download?.urlTemplate {
      downloadURL = URL(string: recipe.expand(template, tag: chosen.tagName, version: version))
    }
    return ReleaseResult(
      tag: chosen.tagName,
      version: version,
      downloadURL: downloadURL,
      format: recipe.download?.format
    )
  }
}
