//
//  UpdateManager.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 20/06/2026.
//

import AppKit
import Combine
import Foundation
import OSLog

/// Where an app's update information is sourced from.
enum UpdateSource: String, Codable {
  case githubRelease
  case sparkle
  case http
  case appStore
  case unknown
}

/// How often OpenUpdater automatically re-checks installed apps for new versions.
enum CheckFrequency: String, CaseIterable, Identifiable {
  case manual
  case daily
  case everyTwoDays
  case weekly
  case everyTwoWeeks
  case monthly

  var id: String { rawValue }

  var title: String {
    switch self {
    case .manual: return "Manual only"
    case .daily: return "Once a day"
    case .everyTwoDays: return "Once every 2 days"
    case .weekly: return "Once a week"
    case .everyTwoWeeks: return "Once every 2 weeks"
    case .monthly: return "Once a month"
    }
  }

  /// The minimum time between automatic checks, or `nil` for manual-only.
  var interval: TimeInterval? {
    let day: TimeInterval = 24 * 60 * 60
    switch self {
    case .manual: return nil
    case .daily: return day
    case .everyTwoDays: return 2 * day
    case .weekly: return 7 * day
    case .everyTwoWeeks: return 14 * day
    case .monthly: return 30 * day
    }
  }
}

/// A single installed application and what we know about its updates.
struct AppInfo: Identifiable, Hashable {
  /// Bundle identifier (`CFBundleIdentifier`).
  let id: String
  let name: String
  /// On-disk location of the `.app` bundle, used to load its icon.
  let url: URL
  var installedVersion: String
  /// Installed build number (`CFBundleVersion`) — Sparkle's authoritative version.
  var installedBuild: String?
  /// Sparkle appcast URL declared by the app (`SUFeedURL`), if any.
  let feedURL: URL?
  /// Latest known marketing version, populated by a registry lookup. `nil` until checked.
  var latestVersion: String?
  /// Latest known build number, when the source reports one (Sparkle).
  var latestBuild: String?
  /// Link to the latest release's notes, populated alongside `latestVersion`.
  var changelogURL: URL?
  /// The recipe's project/vendor homepage, used for the manual-update fallback
  /// when there's a version check but no automatic download.
  var homepageURL: URL?
  /// Where to download the update, and its archive format (`dmg`/`zip`/`pkg`).
  var downloadURL: URL?
  var downloadFormat: String?
  /// True for Mac App Store installs (a `_MASReceipt` is present). Such apps update
  /// through the App Store rather than a direct download.
  var isAppStoreApp = false
  /// For App Store apps: the `macappstore://` URL to open the product page.
  var appStoreURL: URL?
  var source: UpdateSource = .unknown
  /// Ignore prefs mirrored from `AppPreferences` (loaded in scan, updated on change).
  var ignored = false
  var ignoredVersion: String?
  /// Set when OpenUpdater ignores this app by default (preset list or a Steam game).
  /// Not user-removable; carries the reason shown in the ignore list.
  var builtInIgnoreReason: String?

  /// True when this app's update is hidden — either OpenUpdater ignores it by
  /// default, or the user hid the whole app or just the currently-latest version
  /// (which reappears once a newer one ships).
  var isIgnored: Bool {
    if builtInIgnoreReason != nil { return true }
    if ignored { return true }
    if let ignoredVersion { return ignoredVersion == latestVersion }
    return false
  }

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
  /// Bundle ids currently being re-scanned individually, for per-row feedback.
  @Published private(set) var rescanningIDs: Set<String> = []
  /// What the in-progress check is doing right now (recipe sync, current app), shown
  /// in the status bar. `nil` when no check is running.
  @Published private(set) var checkStatusDetail: String?

  func isRescanning(_ id: String) -> Bool { rescanningIDs.contains(id) }

  /// A single line for the status bar: an in-flight install, then an in-flight check,
  /// then the last-checked time as the resting default.
  var statusLine: String {
    if let app = installQueue.first {
      return "Updating \(app.name) — \(installPhase(for: app.id).statusLabel)"
    }
    if isChecking {
      return checkStatusDetail ?? "Checking for updates…"
    }
    if let lastChecked {
      return "Last checked \(lastChecked.formatted(date: .omitted, time: .shortened))"
    }
    return "Not checked yet"
  }

  /// Apps that currently have an update available (excluding ignored ones, and ones
  /// updated this session) — used to badge the menubar icon.
  var updates: [AppInfo] {
    apps.filter { $0.updateAvailable && !$0.isIgnored && !updatedThisSession.contains($0.id) }
  }

  /// Apps successfully updated this session, dropped from the list immediately rather
  /// than lingering on an "Updated" row. An app is cleared from this set once it's
  /// freshly re-checked (see `resolveLatest`), so it never flickers back mid-scan.
  @Published private var updatedThisSession: Set<String> = []

  /// Apps that are ignored — by the user (whole app or a specific version) or by
  /// OpenUpdater's own built-in ignore list (preset apps, Steam games).
  var ignoredApps: [AppInfo] {
    apps.filter { $0.ignored || $0.ignoredVersion != nil || $0.builtInIgnoreReason != nil }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Apps we have no way to check — no recipe, no Sparkle feed, and not an App Store
  /// app — excluding ones OpenUpdater ignores by default (we don't want recipes for
  /// those). These are the candidates for new community recipes.
  var unsupportedApps: [AppInfo] {
    apps.filter { !isCheckable($0) && $0.builtInIgnoreReason == nil }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Recipes bundled with the app, keyed by bundle identifier.
  private let builtInRecipes: [String: UpdateRecipe]
  /// Recipes synced from GitHub at runtime (Application Support); override built-ins.
  private var remoteRecipes: [String: UpdateRecipe] = [:]
  /// Active recipes: built-in, with downloaded then enabled custom recipes layered on top.
  private var recipes: [String: UpdateRecipe]
  /// User-authored recipes from Application Support, for the Preferences list (includes
  /// disabled and invalid ones).
  @Published private(set) var customRecipes: [CustomRecipe] = []

  /// Set when the main window's "Create Custom Recipe" action wants the Preferences
  /// window to open Custom Recipes with this recipe selected. The two views live in
  /// separate windows, so this published property is how the request crosses over.
  @Published var pendingCustomRecipeID: String?

  /// Whether a full check has run this app session. The launch check keys off this
  /// (not `lastChecked`), so a cache-prefilled `lastChecked` doesn't suppress it.
  private var hasCheckedThisSession = false

  private static let checkFrequencyKey = "checkFrequency"
  private static let confirmQuitKey = "confirmQuitRunningApps"
  private static let checkOnLaunchKey = "checkForUpdatesOnLaunch"
  private static let autoUpdateRecipesKey = "autoUpdateRecipes"

  /// Whether to sync community recipes from GitHub before checks (default on).
  /// Mirrored by a toggle in General settings.
  static var autoUpdateRecipes: Bool {
    UserDefaults.standard.object(forKey: autoUpdateRecipesKey) as? Bool ?? true
  }

  /// The running app's marketing version (e.g. "0.9.0"), used to gate downloaded
  /// recipes that need a newer engine than this build.
  static var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  }

  /// Whether to ask before quitting a running app to update it (default on).
  /// Mirrored by the `confirmQuitRunningApps` toggle in General settings.
  static var confirmQuitRunningApps: Bool {
    UserDefaults.standard.object(forKey: confirmQuitKey) as? Bool ?? true
  }

  /// Whether to run a full update check at launch regardless of the periodic
  /// schedule (default on). Mirrored by a toggle in Updating settings.
  static var checkForUpdatesOnLaunch: Bool {
    UserDefaults.standard.object(forKey: checkOnLaunchKey) as? Bool ?? true
  }

  /// How often to automatically re-check installed apps in the background.
  /// Persisted to UserDefaults; changing it reschedules the heartbeat and runs a
  /// check immediately if one is already due under the new interval.
  @Published var checkFrequency: CheckFrequency {
    didSet {
      guard checkFrequency != oldValue else { return }
      UserDefaults.standard.set(checkFrequency.rawValue, forKey: Self.checkFrequencyKey)
      scheduleHeartbeat()
      Task { await runPeriodicCheckIfDue() }
    }
  }

  /// Repeating heartbeat driving periodic checks. It fires a few times an hour; the
  /// real decision (whether a check is due) compares `lastChecked` to the chosen
  /// interval, so it tolerates sleep/wake and relaunches gracefully.
  private var heartbeat: Timer?
  private static let heartbeatInterval: TimeInterval = 30 * 60

  static let log = Logger(subsystem: "dev.casraf.OpenUpdater", category: "updates")

  init() {
    let storedFrequency = UserDefaults.standard.string(forKey: Self.checkFrequencyKey)
    checkFrequency = storedFrequency.flatMap(CheckFrequency.init(rawValue:)) ?? .daily
    builtInRecipes = RecipeStore.loadAll()
    recipes = builtInRecipes
    remoteRecipes = RemoteRecipeStore.loadAll()
    loadCustomRecipes()
    scanInstalledApps()
    applyCachedResults()
    scheduleHeartbeat()
    Self.log.notice(
      "Loaded \(self.builtInRecipes.count, privacy: .public) built-in + \(self.remoteRecipes.count, privacy: .public) community + \(self.customRecipes.count, privacy: .public) custom recipe(s), scanned \(self.apps.count, privacy: .public) app(s)"
    )
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

  /// How many folder levels deep to look for apps. Level 1 is a top-level app
  /// (`/Applications/Foo.app`); level 2 catches apps nested one folder down
  /// (`/Applications/DDPM/DDPM.app`, `/Applications/Send to Kindle/….app`). Kept
  /// shallow on purpose so we don't traverse huge nested trees (e.g. game archives).
  private static let maxScanDepth = 2

  /// Walk each search path — including a couple of folder levels down, so apps nested
  /// in vendor folders are found too — and read every bundle's `Info.plist`.
  func scanInstalledApps() {
    let fileManager = FileManager.default
    var discovered: [String: AppInfo] = [:]

    for directory in searchPaths {
      let baseDepth = directory.pathComponents.count
      guard
        let enumerator = fileManager.enumerator(
          at: directory,
          includingPropertiesForKeys: nil,
          // Find `.app` bundles but never descend into them (or other packages).
          options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
      else { continue }

      for case let url as URL in enumerator {
        if url.pathExtension == "app" {
          // Keep the first bundle seen for a given identifier.
          if let app = appInfo(at: url, using: fileManager), discovered[app.id] == nil {
            discovered[app.id] = app
          }
        } else if url.pathComponents.count - baseDepth >= Self.maxScanDepth {
          // Don't descend past the scan depth into non-app folders.
          enumerator.skipDescendants()
        }
      }
    }

    apps = discovered.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    for index in apps.indices { applyIgnore(toAppAt: index) }
  }

  /// Build an `AppInfo` from an `.app` bundle, or `nil` if its `Info.plist` is unreadable.
  private func appInfo(at url: URL, using fileManager: FileManager) -> AppInfo? {
    guard let bundle = Bundle(url: url), let info = bundle.infoDictionary else { return nil }

    let fallbackName = url.deletingPathExtension().lastPathComponent
    // Treat present-but-empty plist strings as missing — some apps (e.g. Converseen)
    // ship a blank CFBundleIdentifier/CFBundleName, so a plain cast would yield "".
    func nonEmpty(_ key: String) -> String? {
      (info[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    let id = nonEmpty("CFBundleIdentifier") ?? fallbackName
    let name = nonEmpty("CFBundleDisplayName") ?? nonEmpty("CFBundleName") ?? fallbackName
    let build = nonEmpty("CFBundleVersion")
    // Some apps (e.g. FreeCAD) leave CFBundleShortVersionString empty — fall back to
    // the build/CFBundleVersion so we still have something to compare.
    let shortVersion = nonEmpty("CFBundleShortVersionString")
    var version = shortVersion ?? build ?? "—"
    // A recipe can override how the installed version is read — from a bundled
    // binary, a different plist key, or via a normalizing pattern — for apps that
    // ship a placeholder (WezTerm's "0.1.0") or an oddly-formatted version (Zoom).
    if let rule = recipes[id]?.installedVersion,
      let probed = InstalledVersionProbe.resolve(rule, appURL: url, info: info)
    {
      version = probed
    }
    // Sparkle apps advertise their appcast here — auto-detected, no recipe needed.
    let feedURL = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))

    var appInfo = AppInfo(
      id: id, name: name, url: url,
      installedVersion: version, installedBuild: build, feedURL: feedURL
    )
    // A recipe (built-in or custom) takes precedence over a default ignore, so
    // adding one re-enables an otherwise-ignored app.
    appInfo.builtInIgnoreReason =
      recipes[id] == nil ? SystemIgnoreList.reason(bundleID: id, url: url) : nil
    // App Store install markers: `_MASReceipt` for Mac apps, or `iTunesMetadata.plist`
    // in the wrapper of an iOS/iPad app running on Apple Silicon.
    appInfo.isAppStoreApp =
      fileManager.fileExists(
        atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
      || fileManager.fileExists(
        atPath: url.appendingPathComponent("Wrapper/iTunesMetadata.plist").path)
    return appInfo
  }

  /// Mirror the stored ignore prefs onto the in-memory `AppInfo`.
  private func applyIgnore(toAppAt index: Int) {
    let prefs = AppPreferences.load(for: apps[index].id)
    apps[index].ignored = prefs.ignored ?? false
    apps[index].ignoredVersion = prefs.ignoredVersion
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
    // Shield the work from caller cancellation. The launch check runs in the main
    // window's `.task`, which SwiftUI cancels when that window is restored/closed during
    // launch — that would otherwise abort the in-flight network lookups mid-batch and
    // leave a half-finished check (and many spurious failures). An unstructured Task
    // isn't cancelled by its creator, so the check always runs to completion; closing
    // the window mid-check no longer aborts it either.
    await Task { await self.runCheck() }.value
  }

  private func runCheck() async {
    defer { checkStatusDetail = nil }
    // Pull the latest community recipes first (best-effort) so this check uses them.
    await syncRemoteRecipes()

    var checkable = 0
    for app in apps where isCheckable(app) { checkable += 1 }
    Self.log.notice("Checking \(checkable, privacy: .public) checkable app(s)")

    var failures = 0
    var rateLimited = false
    var done = 0
    for index in apps.indices {
      guard isCheckable(apps[index]) else { continue }
      done += 1
      checkStatusDetail = "Checking \(apps[index].name) (\(done)/\(checkable))…"
      // Re-read the installed version from disk first, so an app updated since the
      // cached scan (by us or externally) is compared against what's actually
      // installed and drops off the updates list — matching a single-app re-scan.
      refreshInstalledVersion(id: apps[index].id)
      if let error = await resolveLatest(forAppAt: index) {
        failures += 1
        if case UpdateCheckError.rateLimited = error { rateLimited = true }
      }
    }

    lastChecked = Date()
    hasCheckedThisSession = true
    lastError = Self.errorSummary(failures: failures, rateLimited: rateLimited)
    saveCache()
    Self.log.notice(
      "Check done: \(self.updates.count, privacy: .public) update(s), \(failures, privacy: .public) failure(s)"
    )
  }

  /// Whether we have any way to check this app: a bundled recipe, a Sparkle feed,
  /// or an App Store receipt.
  private func isCheckable(_ app: AppInfo) -> Bool {
    recipes[app.id] != nil || app.feedURL != nil || app.isAppStoreApp
  }

  /// Resolve the latest version for the app at `index` and update its fields.
  /// Returns the error when the lookup failed; `nil` on success or "no update".
  private func resolveLatest(forAppAt index: Int) async -> Error? {
    let app = apps[index]
    let recipe = effectiveRecipe(for: app)
    guard isCheckable(app) else { return nil }

    do {
      let result: ReleaseResult
      let source: UpdateSource
      // Precedence: a Mac App Store install always updates through the App Store —
      // never replace it with a direct-download build, even when a recipe exists for
      // the same bundle id (e.g. Slack ships on both). Otherwise an explicit recipe
      // overrides a Sparkle feed, which overrides App Store auto-detection.
      if app.isAppStoreApp {
        result = try await AppStoreSource.latest(bundleID: app.id)
        source = .appStore
      } else if let recipe {
        switch recipe.check.kind {
        case .githubReleases:
          result = try await GitHubReleaseSource.latest(
            for: recipe, includePrereleases: includePrereleases(for: app))
          source = .githubRelease
        case .sparkle:
          guard let feed = recipe.check.feed, let feedURL = URL(string: recipe.resolveArch(feed))
          else { throw UpdateCheckError.missingFeed }
          result = try await SparkleSource.latest(feedURL: feedURL)
          source = .sparkle
        case .html, .xml, .json, .yaml, .redirect:
          result = try await HTTPVersionSource.latest(for: recipe)
          source = .http
        }
      } else if let feedURL = app.feedURL {
        result = try await SparkleSource.latest(feedURL: feedURL)
        source = .sparkle
      } else {
        result = try await AppStoreSource.latest(bundleID: app.id)
        source = .appStore
      }

      apps[index].latestVersion = result.version
      apps[index].latestBuild = result.build
      apps[index].source = source
      apps[index].downloadURL = result.downloadURL
      apps[index].downloadFormat = result.format
      apps[index].appStoreURL = result.appStoreURL
      // Freshly re-checked, so drop any "updated this session" suppression — the
      // normal version comparison now decides whether it's shown.
      updatedThisSession.remove(apps[index].id)
      if let homepage = recipe?.homepage { apps[index].homepageURL = URL(string: homepage) }
      if let changelogURL = result.changelogURL {
        apps[index].changelogURL = changelogURL
      } else if let recipe, let template = recipe.changelogTemplate {
        apps[index].changelogURL = URL(
          string: recipe.expand(template, tag: result.tag, version: result.version))
      }
      return nil
    } catch UpdateCheckError.noReleases {
      // No publishable build for this app — that's "no update", not a failure.
      return nil
    } catch {
      Self.log.error(
        "Check failed for \(app.id, privacy: .public): \(String(describing: error), privacy: .public)"
      )
      return error
    }
  }

  // MARK: - Re-scan a single app

  /// Re-scan one app: re-read its installed version from disk (to pick up an update
  /// applied outside OpenUpdater) and re-check its source for the latest version.
  /// Apps with no checkable source still get their installed version refreshed.
  func rescan(_ app: AppInfo) async {
    guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
    Self.log.notice("Re-scan \(app.id, privacy: .public)")
    rescanningIDs.insert(app.id)
    defer { rescanningIDs.remove(app.id) }
    refreshInstalledVersion(id: app.id)
    _ = await resolveLatest(forAppAt: index)
    saveCache()
  }

  /// Re-scan several apps (e.g. a multi-selection), one after another.
  func rescanApps(_ apps: [AppInfo]) async {
    for app in apps { await rescan(app) }
  }

  // MARK: - Pre-release preference

  /// Whether pre-releases are included for this app: the user's override if set,
  /// otherwise the recipe's `prereleases` default.
  func includePrereleases(for app: AppInfo) -> Bool {
    AppPreferences.load(for: app.id).includePrereleases
      ?? (effectiveRecipe(for: app)?.check.prereleases ?? false)
  }

  /// Whether the "Check for pre-releases" toggle applies (only GitHub today).
  func supportsPrereleases(_ app: AppInfo) -> Bool {
    effectiveRecipe(for: app)?.check.kind == .githubReleases
  }

  // MARK: - Release channels

  /// This app's recipe with the user's selected release channel overlaid. `nil`
  /// when the app has no recipe.
  func effectiveRecipe(for app: AppInfo) -> UpdateRecipe? {
    recipes[app.id]?.applyingChannel(AppPreferences.load(for: app.id).channel)
  }

  /// The release channels this app's recipe offers (empty when none).
  func channels(for app: AppInfo) -> [UpdateRecipe.Channel] {
    recipes[app.id]?.channelList ?? []
  }

  /// Whether to surface a channel picker (only when more than one channel exists).
  func supportsChannels(_ app: AppInfo) -> Bool {
    channels(for: app).count > 1
  }

  /// The selected channel id, resolved to the recipe's default when unset.
  func selectedChannel(for app: AppInfo) -> String {
    AppPreferences.load(for: app.id).channel
      ?? recipes[app.id]?.defaultChannelID ?? ""
  }

  /// Set the per-app release channel and immediately re-check that app.
  func setChannel(_ id: String, for app: AppInfo) async {
    AppPreferences.update(app.id) { $0.channel = id }
    guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
    _ = await resolveLatest(forAppAt: index)
    saveCache()
  }

  /// Set the per-app pre-release preference and immediately re-check that app.
  func setPrereleases(_ value: Bool, for app: AppInfo) async {
    AppPreferences.update(app.id) { $0.includePrereleases = value }
    guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
    _ = await resolveLatest(forAppAt: index)
    saveCache()
  }

  // MARK: - Ignore rules

  /// Never show this app as updatable.
  func ignoreApp(_ app: AppInfo) {
    changeIgnore(app.id) { $0.ignored = true }
  }

  /// Skip the currently-latest version (reappears when a newer one ships).
  func ignoreCurrentVersion(_ app: AppInfo) {
    guard let version = app.latestVersion else { return }
    changeIgnore(app.id) { $0.ignoredVersion = version }
  }

  /// Stop ignoring this app entirely (clears both app- and version-level ignores).
  func clearIgnore(for app: AppInfo) {
    changeIgnore(app.id) {
      $0.ignored = nil
      $0.ignoredVersion = nil
    }
  }

  /// Ignore several apps at once (e.g. a multi-selection).
  func ignoreApps(_ apps: [AppInfo]) {
    apps.forEach { ignoreApp($0) }
  }

  /// Ignore the current version of several apps at once.
  func ignoreCurrentVersions(_ apps: [AppInfo]) {
    apps.forEach { ignoreCurrentVersion($0) }
  }

  private func changeIgnore(_ id: String, _ change: (inout AppPreferences) -> Void) {
    AppPreferences.update(id, change)
    if let index = apps.firstIndex(where: { $0.id == id }) { applyIgnore(toAppAt: index) }
  }

  private static func errorSummary(failures: Int, rateLimited: Bool) -> String? {
    guard failures > 0 else { return nil }
    if rateLimited {
      return "GitHub's rate limit was reached. Try again in a little while."
    }
    return
      "Couldn't reach \(failures) update source\(failures == 1 ? "" : "s"). Check your connection and try again."
  }

  /// Run an initial check once per session (e.g. at launch / when the main window
  /// first appears). When "check on launch" is on, always run a full check so the
  /// list reflects reality at launch; otherwise only check if one is due under the
  /// chosen frequency — so a manual-only setting never auto-checks and a fresh
  /// cached result is reused.
  func checkForUpdatesIfNeeded() async {
    guard !hasCheckedThisSession, !isChecking else { return }
    if Self.checkForUpdatesOnLaunch {
      await checkForUpdates()
    } else {
      await runPeriodicCheckIfDue()
    }
  }

  // MARK: - Periodic checks

  /// (Re)start the background heartbeat for the current frequency. A manual-only
  /// frequency tears the timer down entirely.
  private func scheduleHeartbeat() {
    heartbeat?.invalidate()
    heartbeat = nil
    guard checkFrequency.interval != nil else { return }
    let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.runPeriodicCheckIfDue() }
    }
    timer.tolerance = 5 * 60
    RunLoop.main.add(timer, forMode: .common)
    heartbeat = timer
  }

  /// Run a check if the chosen interval has elapsed since the last one. No-op for
  /// manual-only, while a check is running, or when the last check is still fresh.
  func runPeriodicCheckIfDue() async {
    guard let interval = checkFrequency.interval, !isChecking else { return }
    if let lastChecked, Date().timeIntervalSince(lastChecked) < interval { return }
    Self.log.notice(
      "Periodic check due (frequency: \(self.checkFrequency.rawValue, privacy: .public))")
    await checkForUpdates()
  }

  // MARK: - Result cache

  /// Prefill apps with the last persisted check results so the previous state shows
  /// immediately at launch. The on-launch re-check refines it.
  private func applyCachedResults() {
    guard let cache = CheckCacheStore.load() else { return }
    lastChecked = cache.lastChecked
    for index in apps.indices {
      guard let entry = cache.apps[apps[index].id] else { continue }
      apps[index].latestVersion = entry.latestVersion
      apps[index].latestBuild = entry.latestBuild
      apps[index].changelogURL = entry.changelogURL
      apps[index].homepageURL = entry.homepageURL
      apps[index].downloadURL = entry.downloadURL
      apps[index].downloadFormat = entry.downloadFormat
      apps[index].appStoreURL = entry.appStoreURL
      apps[index].source = entry.source
    }
  }

  /// Persist the current resolved results so they're available on next launch.
  private func saveCache() {
    var entries: [String: CheckCache.Entry] = [:]
    for app in apps where app.latestVersion != nil || app.source != .unknown {
      entries[app.id] = CheckCache.Entry(
        latestVersion: app.latestVersion,
        latestBuild: app.latestBuild,
        changelogURL: app.changelogURL,
        homepageURL: app.homepageURL,
        downloadURL: app.downloadURL,
        downloadFormat: app.downloadFormat,
        appStoreURL: app.appStoreURL,
        source: app.source)
    }
    CheckCacheStore.save(CheckCache(lastChecked: lastChecked, apps: entries))
  }

  // MARK: - Custom recipes

  /// Reload custom recipes from disk and rebuild the active recipe set.
  private func loadCustomRecipes() {
    customRecipes = CustomRecipeStore.loadAll(builtInIDs: Set(builtInRecipes.keys))
    rebuildActiveRecipes()
  }

  /// Build the active set by layering, lowest to highest: built-in → downloaded
  /// (community) → enabled custom recipes. Each tier overrides the previous by id.
  private func rebuildActiveRecipes() {
    var merged = builtInRecipes
    merged.merge(remoteRecipes) { _, new in new }
    for custom in customRecipes where custom.enabled && custom.parseError == nil {
      if let recipe = CustomRecipeStore.decoded(custom.text) { merged[recipe.id] = recipe }
    }
    recipes = merged
  }

  /// Reload downloaded community recipes from disk and rebuild the active set.
  private func loadRemoteRecipes() {
    remoteRecipes = RemoteRecipeStore.loadAll()
    rebuildActiveRecipes()
  }

  /// Sync community recipes from GitHub (best-effort) and reload them if anything
  /// changed. Gated by the "Automatically update recipes" setting.
  func syncRemoteRecipes() async {
    guard Self.autoUpdateRecipes else { return }
    checkStatusDetail = "Syncing community recipes…"
    if await RemoteRecipeStore.sync(appVersion: Self.appVersion) {
      loadRemoteRecipes()
    }
  }

  /// Delete the downloaded community recipes (falling back to built-ins) and fetch a
  /// fresh copy. An explicit user action, so it re-downloads even when auto-update is
  /// off; if the re-download fails (offline), the built-in set stays in effect.
  func resetRemoteRecipes() async {
    RemoteRecipeStore.clear()
    loadRemoteRecipes()
    if await RemoteRecipeStore.sync(appVersion: Self.appVersion) {
      loadRemoteRecipes()
    }
    await checkForUpdates()
  }

  /// Re-resolve a single app after its recipe changed. Clears stale results if the
  /// app is no longer checkable (e.g. a custom recipe was removed or disabled).
  private func recheck(bundleID: String) async {
    guard let index = apps.firstIndex(where: { $0.id == bundleID }) else { return }
    // Adding/removing a recipe flips whether a default ignore applies.
    apps[index].builtInIgnoreReason =
      recipes[bundleID] == nil
      ? SystemIgnoreList.reason(bundleID: bundleID, url: apps[index].url) : nil
    if isCheckable(apps[index]) {
      _ = await resolveLatest(forAppAt: index)
    } else {
      apps[index].latestVersion = nil
      apps[index].latestBuild = nil
      apps[index].downloadURL = nil
      apps[index].appStoreURL = nil
      apps[index].changelogURL = nil
      apps[index].source = .unknown
    }
    saveCache()
  }

  /// Create a starter custom recipe for an unsupported app (disabled until finished).
  /// Returns its file stem (the bundle id); a no-op if one already exists.
  @discardableResult
  func createCustomRecipeDraft(for app: AppInfo) -> String {
    if !customRecipes.contains(where: { $0.fileStem == app.id }) {
      try? CustomRecipeStore.write(
        CustomRecipeStore.draft(id: app.id, name: app.name), toStem: app.id)
      loadCustomRecipes()
    }
    return app.id
  }

  /// Create a blank custom recipe with a placeholder id. Returns its file stem.
  @discardableResult
  func createCustomRecipe() -> String {
    var stem = "com.example.app"
    var counter = 1
    while customRecipes.contains(where: { $0.fileStem == stem }) {
      counter += 1
      stem = "com.example.app\(counter)"
    }
    try? CustomRecipeStore.write(CustomRecipeStore.draft(id: stem, name: "New App"), toStem: stem)
    loadCustomRecipes()
    return stem
  }

  /// Save edited recipe text. If its `id` changed, the file is renamed to match.
  /// Returns the (possibly new) file stem.
  @discardableResult
  func saveCustomRecipe(text: String, originalStem: String) -> String {
    let newStem = CustomRecipeStore.decoded(text)?.id ?? originalStem
    if newStem != originalStem { CustomRecipeStore.deleteStem(originalStem) }
    try? CustomRecipeStore.write(text, toStem: newStem)
    loadCustomRecipes()
    Task {
      await recheck(bundleID: originalStem)
      if newStem != originalStem { await recheck(bundleID: newStem) }
    }
    return newStem
  }

  /// Enable or disable a custom recipe (writes `enabled:` into its file).
  func setCustomRecipeEnabled(_ enabled: Bool, _ recipe: CustomRecipe) {
    let newText = CustomRecipeStore.text(recipe.text, settingEnabled: enabled)
    try? CustomRecipeStore.write(newText, toStem: recipe.fileStem)
    loadCustomRecipes()
    Task { await recheck(bundleID: recipe.id) }
  }

  /// Delete a custom recipe.
  func deleteCustomRecipe(_ recipe: CustomRecipe) {
    CustomRecipeStore.deleteStem(recipe.fileStem)
    loadCustomRecipes()
    Task { await recheck(bundleID: recipe.id) }
  }

  /// Open the "Add an app" issue form, pre-filled with the app's name and bundle id,
  /// and optionally the recipe YAML, so users can submit a finished recipe.
  func openRecipeIssue(name: String, bundleID: String, recipe: String? = nil) {
    var components = URLComponents(
      url: AppBranding.repositoryURL.appendingPathComponent("issues/new"),
      resolvingAgainstBaseURL: false)
    var items = [
      URLQueryItem(name: "template", value: "add_recipe.yml"),
      URLQueryItem(name: "title", value: "[Recipe]: \(name)"),
      URLQueryItem(name: "name", value: name),
      URLQueryItem(name: "bundle-id", value: bundleID),
    ]
    if let recipe, !recipe.isEmpty { items.append(URLQueryItem(name: "recipe", value: recipe)) }
    components?.queryItems = items
    if let url = components?.url { NSWorkspace.shared.open(url) }
  }

  // MARK: - Installing

  /// Progress of an in-flight install, keyed by bundle identifier.
  @Published private(set) var installPhases: [String: InstallPhase] = [:]
  /// Apps queued for install, in order. The head is the one currently installing;
  /// the rest wait their turn. Drained one at a time by `queueWorker`.
  @Published private(set) var installQueue: [AppInfo] = []

  func installPhase(for id: String) -> InstallPhase { installPhases[id] ?? .idle }

  /// True while anything is in the install queue (installing or waiting).
  var isInstalling: Bool { !installQueue.isEmpty }

  /// Whether `id` is currently installing or waiting in the queue.
  func isQueued(_ id: String) -> Bool { installQueue.contains { $0.id == id } }

  /// The single task draining the queue, or nil when idle.
  private var queueWorker: Task<Void, Never>?
  /// Running install tasks, keyed by bundle id, so they can be cancelled.
  private var installTasks: [String: Task<Void, Never>] = [:]

  /// Add `app` to the install queue (no-op if already queued) and make sure the
  /// worker is draining it. The app is inserted at its place in the update list
  /// rather than the end, so queue order follows the list the user sees — but it
  /// never jumps ahead of whatever's already installing.
  func enqueueInstall(_ app: AppInfo) {
    guard !isQueued(app.id) else { return }
    installPhases[app.id] = .queued

    let listIndex = Dictionary(updates.enumerated().map { ($1.id, $0) }) { a, _ in a }
    let newPlace = listIndex[app.id] ?? .max
    // Keep the not-yet-started items sorted by list position; skip the one already
    // installing so it stays at the head.
    var index = installQueue.count
    for (i, queued) in installQueue.enumerated() where installTasks[queued.id] == nil {
      if (listIndex[queued.id] ?? .max) > newPlace {
        index = i
        break
      }
    }
    installQueue.insert(app, at: index)
    startQueueWorker()
  }

  /// Drain the queue one app at a time, head first, until it's empty.
  private func startQueueWorker() {
    guard queueWorker == nil else { return }
    queueWorker = Task { [weak self] in
      guard let self else { return }
      while let app = self.installQueue.first {
        let id = app.id
        let task = Task { await self.installUpdate(app) }
        self.installTasks[id] = task
        await task.value
        self.installTasks[id] = nil
        // Drop the app we just finished (cancel may have removed it already).
        self.installQueue.removeAll { $0.id == id }
      }
      self.queueWorker = nil
    }
  }

  /// Remove `app` from the queue. If it's the one installing, cancel it (the install
  /// bails at its next cancellation check, then resets the row to idle); if it's only
  /// waiting, drop it from the queue and clear its queued state.
  func cancelInstall(_ app: AppInfo) {
    let id = app.id
    let isRunning = installTasks[id] != nil
    installQueue.removeAll { $0.id == id }
    if isRunning {
      installTasks[id]?.cancel()
    } else {
      installPhases[id] = .idle
    }
  }

  /// Stop a running "Update All"/"Update Selected": cancel the in-flight install and
  /// clear everything still waiting in the queue.
  func stopBatch() {
    let runningIDs = Set(installTasks.keys)
    for app in installQueue where !runningIDs.contains(app.id) {
      installPhases[app.id] = .idle
    }
    installQueue.removeAll { !runningIDs.contains($0.id) }
    installTasks.values.forEach { $0.cancel() }
  }

  /// For apps with a version check but no automatic download: ask the user how to
  /// proceed — open the project's homepage to download the new version themselves,
  /// or launch the app so its own updater can take over.
  func manualUpdate(_ app: AppInfo) {
    let alert = NSAlert()
    alert.messageText = "Update \(app.name) manually"
    let latest = app.latestVersion.map { " (\($0))" } ?? ""
    alert.informativeText =
      "A newer version\(latest) is available, but \(AppBranding.title) can't install it "
      + "automatically for this app. Open its homepage to download the update, or launch "
      + "\(app.name) to use its built-in updater."
    alert.addButton(withTitle: "Open Homepage")
    alert.addButton(withTitle: "Launch App")
    alert.addButton(withTitle: "Cancel")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      if let url = app.homepageURL ?? app.changelogURL { NSWorkspace.shared.open(url) }
    case .alertSecondButtonReturn:
      NSWorkspace.shared.open(app.url)
    default:
      break
    }
  }

  /// Open a Mac App Store app's product page in the App Store so the user can update
  /// it there (App Store apps can't be installed directly).
  func openInAppStore(_ app: AppInfo) {
    guard let url = app.appStoreURL ?? app.changelogURL else { return }
    NSWorkspace.shared.open(url)
  }

  /// Show the reason a failed install failed, with options to copy it or file a
  /// pre-filled bug report.
  func showInstallFailure(_ app: AppInfo, message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "\(app.name) couldn't be updated"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Report…")
    alert.addButton(withTitle: "Copy Details")
    alert.addButton(withTitle: "Close")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      reportInstallFailure(app, message: message)
    case .alertSecondButtonReturn:
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(message, forType: .string)
    default:
      break
    }
  }

  /// Open a pre-filled bug report for a failed install.
  private func reportInstallFailure(_ app: AppInfo, message: String) {
    let latest = app.latestVersion ?? "?"
    var components = URLComponents(
      url: AppBranding.repositoryURL.appendingPathComponent("issues/new"),
      resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "template", value: "bug_report.yml"),
      URLQueryItem(name: "title", value: "[Bug]: \(app.name) failed to update"),
      URLQueryItem(
        name: "summary",
        value:
          "Updating \(app.name) (\(app.installedVersion) → \(latest)) failed with:\n\n\(message)"),
      URLQueryItem(name: "app", value: "\(app.name) (\(app.id))"),
    ]
    if let url = components?.url { NSWorkspace.shared.open(url) }
  }

  /// Apps that have an update AND something we can actually download/install.
  var installableUpdates: [AppInfo] { updates.filter { $0.downloadURL != nil } }

  /// Queue every available update for install, one at a time.
  func updateAll() {
    let targets = installableUpdates
    Self.log.notice("Batch update: \(targets.count, privacy: .public) app(s)")
    targets.forEach { enqueueInstall($0) }
  }

  /// Queue just the selected apps (by bundle id) for install, one at a time.
  func updateSelected(_ ids: Set<String>) {
    installableUpdates.filter { ids.contains($0.id) }.forEach { enqueueInstall($0) }
  }

  /// Download and install the update for `app`, reporting progress via `installPhases`.
  func installUpdate(_ app: AppInfo) async {
    guard let downloadURL = app.downloadURL else {
      installPhases[app.id] = .failed("No download is available for this app.")
      return
    }
    guard let format = app.downloadFormat.flatMap(ArchiveFormat.init(rawValue:)) else {
      installPhases[app.id] = .failed("Unsupported download format.")
      return
    }

    let id = app.id
    let destination = app.url
    Self.log.notice(
      "Installing \(id, privacy: .public) from \(downloadURL.absoluteString, privacy: .public)")

    do {
      installPhases[id] = .downloading(0)
      let archive = try await Installer.download(downloadURL) { fraction in
        Task { @MainActor in self.installPhases[id] = .downloading(fraction) }
      }
      Self.log.notice("install \(id, privacy: .public): downloaded")
      try Task.checkCancellation()

      // Quit any running copy first; relaunch it after a successful install.
      installPhases[id] = .quitting
      let quitOutcome = await quitRunningApp(bundleID: id, appName: app.name)
      if case .cancelled = quitOutcome {
        installPhases[id] = .idle
        Self.log.notice("install \(id, privacy: .public): cancelled at quit prompt")
        return
      }
      let wasRunning = quitOutcome == .quit
      Self.log.notice(
        "install \(id, privacy: .public): quit running app (was running: \(wasRunning, privacy: .public))"
      )
      try Task.checkCancellation()

      switch format {
      case .pkg:
        installPhases[id] = .installing
        Self.log.notice("install \(id, privacy: .public): running pkg installer")
        try await installPackage(archive)

      case .dmg, .zip, .tar:
        installPhases[id] = .extracting
        Self.log.notice(
          "install \(id, privacy: .public): extracting \(format.rawValue, privacy: .public)")
        let expectedName = destination.deletingPathExtension().lastPathComponent
        let newApp = try await Task.detached(priority: .userInitiated) {
          try Installer.extractApp(
            from: archive, format: format, expectedBundleID: id, expectedName: expectedName)
        }.value
        try Task.checkCancellation()

        installPhases[id] = .verifying
        Self.log.notice("install \(id, privacy: .public): verifying signature")
        await Task.detached(priority: .userInitiated) {
          Installer.clearQuarantineIfTrusted(newApp, installedAppForTrust: destination)
        }.value
        try Task.checkCancellation()

        installPhases[id] = .installing
        Self.log.notice("install \(id, privacy: .public): replacing app in place")
        try await replaceApp(newApp, at: destination)
      }

      // Squirrel.Mac self-updaters (Discord, Slack, …) stage a copy and reinstall it on
      // next launch, which would roll our update straight back. Clear any such pending
      // request before we relaunch, so what we just installed sticks.
      await Task.detached(priority: .userInitiated) {
        Installer.clearPendingSquirrelUpdate(for: destination)
      }.value

      refreshInstalledVersion(id: id)
      updatedThisSession.insert(id)
      installPhases[id] = .idle
      if wasRunning { relaunch(destination) }
      Self.log.notice("Installed \(id, privacy: .public)")
    } catch {
      if Task.isCancelled || (error as? URLError)?.code == .cancelled {
        installPhases[id] = .idle
        Self.log.notice("install \(id, privacy: .public): cancelled")
      } else {
        installPhases[id] = .failed(String(describing: error))
        Self.log.error(
          "Install failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)"
        )
      }
    }
  }

  /// Install a `.pkg` via the root helper (no prompt) when it's enabled, else fall
  /// back to the system installer behind an admin authorization prompt.
  private func installPackage(_ archive: URL) async throws {
    if await PrivilegedHelper.shared.ensureReady() {
      try await PrivilegedHelper.shared.installPackage(at: archive.path)
    } else {
      try await Task.detached(priority: .userInitiated) { try Installer.installPkg(archive) }.value
    }
  }

  /// Replace an app in place. If the location isn't user-writable (admin-owned),
  /// retry through the root helper when it's enabled.
  private func replaceApp(_ newApp: URL, at destination: URL) async throws {
    do {
      try await Task.detached(priority: .userInitiated) {
        try Installer.replaceApp(at: destination, with: newApp)
      }.value
    } catch InstallError.notWritable {
      if await PrivilegedHelper.shared.ensureReady() {
        try await PrivilegedHelper.shared.replaceApp(at: destination.path, with: newApp.path)
      } else if await PrivilegedHelper.shared.needsReinstall() {
        throw HelperError.needsReinstall
      } else {
        // No root helper (e.g. a managed standard user who can't approve the daemon):
        // fall back to an admin authorization prompt, which endpoint privilege-management
        // tools can elevate per policy without a local-admin password.
        try await Task.detached(priority: .userInitiated) {
          try Installer.replaceAppWithAuthorization(at: destination, with: newApp)
        }.value
      }
    }
  }

  /// Outcome of asking a running app to quit before an install.
  enum QuitOutcome: Equatable {
    /// The app wasn't running — nothing to quit, nothing to relaunch.
    case notRunning
    /// The app was running and has been terminated — relaunch it after installing.
    case quit
    /// The user declined the quit prompt — abort the install.
    case cancelled
  }

  /// Terminate any running instances of `bundleID` and wait briefly for them to
  /// exit. When `confirmQuitRunningApps` is on, ask first and abort if declined.
  private func quitRunningApp(bundleID: String, appName: String) async -> QuitOutcome {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    guard !running.isEmpty else { return .notRunning }

    if Self.confirmQuitRunningApps {
      let alert = NSAlert()
      alert.messageText = "Quit \(appName) to update?"
      alert.informativeText =
        "\(appName) is open. \(AppBranding.title) needs to quit it to install the update, "
        + "then reopens it afterwards."
      alert.addButton(withTitle: "Quit and Update")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
    }

    running.forEach { $0.terminate() }
    // Wait up to ~5s for a graceful quit before proceeding regardless.
    for _ in 0..<25 {
      if running.allSatisfy(\.isTerminated) { break }
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
    return .quit
  }

  private func relaunch(_ appURL: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
  }

  /// Re-read an app's `Info.plist` from disk so its installed version reflects what's
  /// actually on disk — used after our own install, and on an individual re-scan to
  /// pick up an update applied outside OpenUpdater.
  private func refreshInstalledVersion(id: String) {
    guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
    let plist = apps[index].url.appendingPathComponent("Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else { return }
    let build = info["CFBundleVersion"] as? String
    // Mirror the scan's fallback: some apps leave the short version string empty.
    let shortVersion = (info["CFBundleShortVersionString"] as? String).flatMap {
      $0.isEmpty ? nil : $0
    }
    var version = shortVersion ?? build ?? apps[index].installedVersion
    // Honor a recipe's installed-version override (e.g. WezTerm, Zoom), so a refresh
    // doesn't revert to the raw plist value.
    if let rule = recipes[id]?.installedVersion,
      let probed = InstalledVersionProbe.resolve(rule, appURL: apps[index].url, info: info)
    {
      version = probed
    }
    apps[index].installedVersion = version
    apps[index].installedBuild = build
  }
}

/// Where an in-flight install currently is.
enum InstallPhase: Equatable {
  case idle
  case queued  // waiting in the install queue, not started yet
  case downloading(Double)  // fraction complete, 0…1
  case extracting
  case verifying
  case quitting
  case installing
  case failed(String)

  /// Short label for the status bar.
  var statusLabel: String {
    switch self {
    case .idle: return "Idle"
    case .queued: return "Queued"
    case .downloading(let fraction): return "Downloading \(Int(fraction * 100))%"
    case .extracting: return "Extracting"
    case .verifying: return "Verifying"
    case .quitting: return "Quitting app"
    case .installing: return "Installing"
    case .failed: return "Failed"
    }
  }
}
