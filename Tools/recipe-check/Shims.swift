//
//  Shims.swift
//  recipe-check
//
//  Foundation-only stand-ins for the two symbols the reused app sources reference
//  but that live in code the CLI deliberately doesn't pull in: AppBranding (a
//  SwiftUI file) and GitHubToken (Keychain). Keeping these here lets the real
//  sources compile untouched.
//

import Foundation

/// Product name, used as the network User-Agent. Mirrors the app's AppBranding.
nonisolated enum AppBranding {
  static let title = "OpenUpdater"
  static let repositoryURL = URL(string: "https://github.com/chenasraf/OpenUpdater")!
}

/// In the app this reads the optional GitHub PAT from the Keychain. In the CLI we
/// take it from the environment, so `GITHUB_TOKEN=… make recipe-check …` raises
/// GitHub's rate limit (60 → 5,000 req/hr) without a Keychain prompt.
nonisolated enum GitHubToken {
  static func load() -> String? {
    let env = ProcessInfo.processInfo.environment
    for key in ["GITHUB_TOKEN", "GH_TOKEN"] {
      if let value = env[key], !value.isEmpty { return value }
    }
    return nil
  }
}
