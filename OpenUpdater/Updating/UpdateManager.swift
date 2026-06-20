//
//  UpdateManager.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import Combine
import Foundation
import OSLog

/// Where an app's update information is sourced from.
enum UpdateSource {
    case homebrew
    case githubRelease
    case sparkle
    case unknown
}

/// A single installed application and what we know about its updates.
struct AppInfo: Identifiable, Hashable {
    /// Bundle identifier (`CFBundleIdentifier`).
    let id: String
    let name: String
    /// On-disk location of the `.app` bundle, used to load its icon.
    let url: URL
    let installedVersion: String
    /// Installed build number (`CFBundleVersion`) — Sparkle's authoritative version.
    let installedBuild: String?
    /// Sparkle appcast URL declared by the app (`SUFeedURL`), if any.
    let feedURL: URL?
    /// Latest known marketing version, populated by a registry lookup. `nil` until checked.
    var latestVersion: String?
    /// Latest known build number, when the source reports one (Sparkle).
    var latestBuild: String?
    /// Link to the latest release's notes, populated alongside `latestVersion`.
    var changelogURL: URL?
    var source: UpdateSource = .unknown

    var updateAvailable: Bool {
        // Sparkle apps are versioned by build number (CFBundleVersion), matching
        // Sparkle's own comparator — their marketing string can be non-monotonic
        // (e.g. a git hash), so compare builds when both are known.
        if source == .sparkle, let latestBuild, let installedBuild {
            return VersionCompare.isNewer(latestBuild, than: installedBuild)
        }
        guard let latestVersion else { return false }
        return VersionCompare.isNewer(latestVersion, than: installedVersion)
    }
}

/// Shared model layer backing both the menubar popover and the main window.
@MainActor
final class UpdateManager: ObservableObject {
    /// Every app discovered in `/Applications`, sorted by display name.
    @Published private(set) var apps: [AppInfo] = []
    /// True while `checkForUpdates()` is running.
    @Published private(set) var isChecking = false
    /// When the last update check finished, or `nil` if none has run this session.
    @Published private(set) var lastChecked: Date?
    /// A user-facing summary of the last check's failures, or `nil` if it was clean.
    @Published private(set) var lastError: String?

    /// Apps that currently have an update available — used to badge the menubar icon.
    var updates: [AppInfo] {
        apps.filter(\.updateAvailable)
    }

    /// Update recipes bundled with the app, keyed by bundle identifier.
    private let recipes: [String: UpdateRecipe]

    static let log = Logger(subsystem: "dev.casraf.OpenUpdater", category: "updates")

    init() {
        recipes = RecipeStore.loadAll()
        scanInstalledApps()
        Self.log.notice("Loaded \(self.recipes.count, privacy: .public) recipe(s), scanned \(self.apps.count, privacy: .public) app(s)")
    }

    /// Directories scanned for installed apps, in precedence order. A system-wide
    /// install in `/Applications` wins over a per-user one with the same bundle ID.
    private var searchPaths: [URL] {
        let fileManager = FileManager.default
        var paths = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        if let userApps = fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first {
            paths.append(userApps)
        }
        return paths
    }

    /// Walk each search path and read every bundle's `Info.plist`.
    func scanInstalledApps() {
        let fileManager = FileManager.default
        var discovered: [String: AppInfo] = [:]

        for directory in searchPaths {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let info = bundle.infoDictionary else { continue }

                let fallbackName = url.deletingPathExtension().lastPathComponent
                let id = info["CFBundleIdentifier"] as? String ?? fallbackName
                let name = info["CFBundleDisplayName"] as? String
                    ?? info["CFBundleName"] as? String
                    ?? fallbackName
                let version = info["CFBundleShortVersionString"] as? String ?? "—"
                let build = info["CFBundleVersion"] as? String
                // Sparkle apps advertise their appcast here — auto-detected, no recipe needed.
                let feedURL = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))

                // Keep the first bundle seen for a given identifier.
                if discovered[id] == nil {
                    discovered[id] = AppInfo(
                        id: id, name: name, url: url,
                        installedVersion: version, installedBuild: build, feedURL: feedURL
                    )
                }
            }
        }

        apps = discovered.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Look up the latest version for every installed app we can check — those
    /// with a bundled recipe, or those that advertise a Sparkle feed (`SUFeedURL`).
    ///
    /// A recipe takes precedence over a Sparkle feed, letting a recipe override an
    /// app's own updater. A single failed lookup never aborts the batch — it just
    /// leaves that app's `latestVersion` unchanged.
    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var checkable = 0
        for app in apps where recipes[app.id] != nil || app.feedURL != nil { checkable += 1 }
        Self.log.notice("Checking \(checkable, privacy: .public) checkable app(s)")

        var failures = 0
        var rateLimited = false
        for index in apps.indices {
            let app = apps[index]
            let recipe = recipes[app.id]
            guard recipe != nil || app.feedURL != nil else { continue }

            do {
                let result: ReleaseResult
                let source: UpdateSource
                if let recipe {
                    switch recipe.check.kind {
                    case .githubReleases:
                        result = try await GitHubReleaseSource.latest(for: recipe)
                        source = .githubRelease
                    case .sparkle:
                        guard let feed = recipe.check.feed, let feedURL = URL(string: feed) else {
                            throw UpdateCheckError.missingFeed
                        }
                        result = try await SparkleSource.latest(feedURL: feedURL)
                        source = .sparkle
                    }
                } else {
                    // No recipe, but the app advertises its own Sparkle feed.
                    result = try await SparkleSource.latest(feedURL: app.feedURL!)
                    source = .sparkle
                }

                apps[index].latestVersion = result.version
                apps[index].latestBuild = result.build
                apps[index].source = source
                if let changelogURL = result.changelogURL {
                    apps[index].changelogURL = changelogURL
                } else if let recipe, let template = recipe.changelogTemplate {
                    apps[index].changelogURL = URL(string: recipe.expand(
                        template, tag: result.tag, version: result.version
                    ))
                }
            } catch UpdateCheckError.noReleases {
                // No publishable build for this app — that's "no update", not a failure.
                continue
            } catch {
                failures += 1
                if case UpdateCheckError.rateLimited = error { rateLimited = true }
                Self.log.error("Check failed for \(app.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        lastChecked = Date()
        lastError = Self.errorSummary(failures: failures, rateLimited: rateLimited)
        Self.log.notice("Check done: \(self.updates.count, privacy: .public) update(s), \(failures, privacy: .public) failure(s)")
    }

    private static func errorSummary(failures: Int, rateLimited: Bool) -> String? {
        guard failures > 0 else { return nil }
        if rateLimited {
            return "GitHub's rate limit was reached. Try again in a little while."
        }
        return "Couldn't reach \(failures) update source\(failures == 1 ? "" : "s"). Check your connection and try again."
    }

    /// Run an initial check once per session (e.g. when the main window first appears).
    func checkForUpdatesIfNeeded() async {
        guard lastChecked == nil, !isChecking else { return }
        await checkForUpdates()
    }
}
