//
//  AppStoreSource.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation

/// Resolves the latest version of a Mac App Store app via Apple's public iTunes
/// lookup API. App Store apps can't be installed directly — the result carries a
/// `macappstore://` URL so the user can update through the App Store.
///
/// Detected automatically (no recipe) for any app bundle that carries a
/// `Contents/_MASReceipt/receipt`, the marker of an App Store install.
enum AppStoreSource {
  static func latest(bundleID: String) async throws -> ReleaseResult {
    // Try the user's storefront first; fall back to the default (US) store for apps
    // that aren't listed in their region.
    let region = Locale.current.region?.identifier.lowercased()
    if let result = try await lookup(bundleID: bundleID, country: region) { return result }
    if region != nil, let result = try await lookup(bundleID: bundleID, country: nil) {
      return result
    }
    throw UpdateCheckError.noReleases
  }

  private static func lookup(bundleID: String, country: String?) async throws -> ReleaseResult? {
    var components = URLComponents(string: "https://itunes.apple.com/lookup")!
    components.queryItems = [
      URLQueryItem(name: "bundleId", value: bundleID),
      URLQueryItem(name: "entity", value: "macSoftware"),
    ]
    if let country { components.queryItems?.append(URLQueryItem(name: "country", value: country)) }
    guard let url = components.url else { throw UpdateCheckError.missingURL }

    var request = URLRequest(url: url)
    request.setValue(AppBranding.title, forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.badResponse(-1) }
    guard http.statusCode == 200 else { throw UpdateCheckError.badResponse(http.statusCode) }

    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let results = root["results"] as? [[String: Any]],
      let first = results.first,
      let version = first["version"] as? String
    else { return nil }

    let trackURL = first["trackViewUrl"] as? String
    var appStoreURL: URL?
    if let trackURL {
      // macappstore:// opens the App Store app straight to the product page.
      appStoreURL = URL(
        string: trackURL.replacingOccurrences(of: "https://", with: "macappstore://"))
    } else if let trackID = first["trackId"] as? Int {
      appStoreURL = URL(string: "macappstore://apps.apple.com/app/id\(trackID)")
    }

    return ReleaseResult(
      tag: version,
      version: version,
      changelogURL: trackURL.flatMap(URL.init(string:)),
      appStoreURL: appStoreURL
    )
  }
}
