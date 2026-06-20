//
//  UpdateManager.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import Combine
import Foundation

/// Where an app's update information is sourced from.
enum UpdateSource {
    case homebrew
    case githubRelease
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
    /// Latest known version, populated by a registry lookup. `nil` until checked.
    var latestVersion: String?
    var source: UpdateSource = .unknown

    var updateAvailable: Bool {
        guard let latestVersion else { return false }
        return latestVersion != installedVersion
    }
}

/// Shared model layer backing both the menubar popover and the main window.
@MainActor
final class UpdateManager: ObservableObject {
    /// Every app discovered in `/Applications`, sorted by display name.
    @Published private(set) var apps: [AppInfo] = []
    /// True while `checkForUpdates()` is running.
    @Published private(set) var isChecking = false

    /// Apps that currently have an update available — used to badge the menubar icon.
    var updates: [AppInfo] {
        apps.filter(\.updateAvailable)
    }

    init() {
        scanInstalledApps()
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

                // Keep the first bundle seen for a given identifier.
                if discovered[id] == nil {
                    discovered[id] = AppInfo(id: id, name: name, url: url, installedVersion: version)
                }
            }
        }

        apps = discovered.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Fetch the latest available version for each installed app.
    ///
    /// Stub for now: flips `isChecking` and simulates a short network delay.
    /// Real registry lookups (Homebrew Casks, GitHub Releases) land here later.
    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }
}
