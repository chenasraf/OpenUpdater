//
//  SystemIgnoreList.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation

/// Apps OpenUpdater ignores by default — independent of the user's own ignore list,
/// and not user-removable. Two kinds: a curated set of bundle ids (apps that update
/// themselves or are managed by the system) and Steam games (detected on disk), which
/// there's no point trying to update through OpenUpdater.
nonisolated enum SystemIgnoreList {
  /// Bundle ids that are always ignored, mapped to the reason shown to the user.
  /// Extend this list as new always-ignore apps come up. (Apple's own apps are
  /// covered by `isAppleApp`, so they don't need entries here.)
  static let presetBundleIDs: [String: String] = [
    "dev.casraf.OpenUpdater": "\(AppBranding.title) itself",
    // Shortcuts / helpers / uninstallers — nothing to update.
    "com.google.drivefs.shortcuts.docs": "Google Drive shortcut",
    "com.google.drivefs.shortcuts.sheets": "Google Drive shortcut",
    "com.google.drivefs.shortcuts.slides": "Google Drive shortcut",
    "com.anthropic.claude-code-url-handler": "Helper app",
    "com.amazon.SendToKindleUninstaller": "Uninstaller",
    // No bundle id of its own — scanned under its app name.
    "Proton Mail Uninstaller": "Uninstaller",
    // Apps that ship their own updater — no public source to track, and updating
    // them through OpenUpdater would fight their built-in mechanism.
    "com.runningwithcrayons.Alfred": "Updates itself",
    "com.amazon.Lassen": "Updates itself",
    "com.google.android.studio": "Updates itself",
    "com.anthropic.claudefordesktop": "Updates itself",
    "com.epicgames.EpicGamesLauncher": "Updates itself",
    "com.expressvpn.ExpressVPN": "Updates itself",
    "com.gog.galaxy": "Updates itself",
    "com.jagex.launcher": "Updates itself",
    "com.logi.optionsplus": "Updates itself",
    "com.corecode.MacUpdater": "Updates itself",
    "com.valvesoftware.steam": "Updates itself",
    "com.amazon.SendToKindle": "Updates itself",
    // No public update source found.
    "Qisda.DDPM": "No update source",
  ]

  static let appleAppReason = "Apple system app"
  static let steamGameReason = "Steam game"

  /// The reason OpenUpdater ignores this app by default, or `nil` if it's a normal,
  /// user-controlled app.
  static func reason(bundleID: String, url: URL) -> String? {
    if let preset = presetBundleIDs[bundleID] { return preset }
    if isAppleApp(bundleID: bundleID) { return appleAppReason }
    // CrossOver wraps Windows apps in helper bundles — managed by CrossOver, not us.
    if bundleID.hasPrefix("com.codeweavers.CrossOverHelper") { return "CrossOver app" }
    if isSteamGame(at: url) { return steamGameReason }
    return nil
  }

  /// Apple's own apps (Safari, Mail, and the rest of the OS apps) all use a
  /// `com.apple.` bundle identifier and update through macOS / the App Store, not us.
  static func isAppleApp(bundleID: String) -> Bool {
    bundleID == "com.apple" || bundleID.hasPrefix("com.apple.")
  }

  /// Heuristic Steam-game detection, covering the three shapes Steam apps take:
  ///   1. The bundle lives under a Steam library (`…/steamapps/…`).
  ///   2. It bundles the Steamworks SDK / ships a `steam_appid.txt` marker.
  ///   3. It's a Steam-generated shortcut whose tiny launcher runs `steam://run/<id>`.
  static func isSteamGame(at url: URL) -> Bool {
    if url.resolvingSymlinksInPath().path.contains("/steamapps/") { return true }

    let fileManager = FileManager.default
    let contents = url.appendingPathComponent("Contents")
    let markers = [
      "Frameworks/libsteam_api.dylib",
      "MacOS/libsteam_api.dylib",
      "Frameworks/Steamworks.framework",
      "MacOS/steam_appid.txt",
      "steam_appid.txt",
    ]
    if markers.contains(where: {
      fileManager.fileExists(atPath: contents.appendingPathComponent($0).path)
    }) {
      return true
    }

    if let launcher = launcherScript(of: url), launcher.contains("steam://") { return true }
    return false
  }

  /// The main executable's text, but only when it's small enough to be a launcher
  /// script (Steam shortcuts are a few lines) — never reads a real game binary.
  private static func launcherScript(of url: URL) -> String? {
    let infoPlist = url.appendingPathComponent("Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: infoPlist),
      let executable = info["CFBundleExecutable"] as? String
    else { return nil }

    let path = url.appendingPathComponent("Contents/MacOS/\(executable)").path
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      let size = attributes[.size] as? Int, size > 0, size <= 4096
    else { return nil }
    return try? String(contentsOfFile: path, encoding: .utf8)
  }
}
