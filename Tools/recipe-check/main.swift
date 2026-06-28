//
//  main.swift
//  recipe-check
//
//  A developer CLI that runs OpenUpdater's REAL recipe-resolution logic (the same
//  GitHubReleaseSource / SparkleSource / HTTPVersionSource / AppStoreSource the app
//  uses) against a single recipe file and logs what it finds. Optionally downloads
//  and extracts the result to confirm the download URL yields the expected app.
//
//  Usage:
//    recipe-check <bundle-id> [--prereleases] [--download] [--recipes-dir DIR]
//

import Foundation
import Yams

// MARK: - Output helpers

func out(_ line: String = "") { print(line) }
func section(_ title: String) { print("\n── \(title) ─────────────────────────────") }
func errLine(_ line: String) { FileHandle.standardError.write(Data((line + "\n").utf8)) }

func usage() -> Never {
  out(
    """
    usage: recipe-check <bundle-id> [options]

      <bundle-id>          recipe to test, e.g. com.1password.1password
                           (loaded from <recipes-dir>/<bundle-id>.yml)

    options:
      -p, --prereleases    include pre-release/beta tags (github_releases)
      -d, --download       also download + extract the result and verify the
                           extracted bundle id matches the recipe
      -c, --channel ID     for multi-channel recipes (ESR/LTS/Still/…), resolve
                           this channel instead of the default (first) one
          --recipes-dir D  directory holding the .yml recipes
                           (default: OpenUpdater/Recipes)
      -h, --help           show this help

    env:
      GITHUB_TOKEN / GH_TOKEN   used as a GitHub PAT to raise the rate limit
    """)
  exit(64)
}

func fail(_ message: String) -> Never {
  errLine("error: \(message)")
  exit(64)
}

// MARK: - Arguments

struct Options {
  var id: String
  var prereleases = false
  var download = false
  var channel: String?
  var recipesDir = "OpenUpdater/Recipes"
}

func parseOptions() -> Options {
  var id: String?
  var prereleases = false
  var download = false
  var channel: String?
  var recipesDir = "OpenUpdater/Recipes"

  let args = Array(CommandLine.arguments.dropFirst())
  var index = 0
  while index < args.count {
    let arg = args[index]
    switch arg {
    case "-p", "--prereleases": prereleases = true
    case "-d", "--download": download = true
    case "-c", "--channel":
      index += 1
      guard index < args.count else { fail("--channel needs a value") }
      channel = args[index]
    case "--recipes-dir":
      index += 1
      guard index < args.count else { fail("--recipes-dir needs a value") }
      recipesDir = args[index]
    case "-h", "--help": usage()
    default:
      if arg.hasPrefix("-") { fail("unknown option: \(arg)") }
      if id == nil { id = arg } else { fail("unexpected argument: \(arg)") }
    }
    index += 1
  }

  guard let id else { usage() }
  return Options(
    id: id, prereleases: prereleases, download: download, channel: channel,
    recipesDir: recipesDir)
}

// MARK: - Resolution (mirrors UpdateManager.resolveLatest's recipe dispatch)

func resolve(_ recipe: UpdateRecipe, prereleases: Bool) async throws -> ReleaseResult {
  switch recipe.check.kind {
  case .githubReleases:
    return try await GitHubReleaseSource.latest(for: recipe, includePrereleases: prereleases)
  case .sparkle:
    guard let feed = recipe.check.feed, let feedURL = URL(string: recipe.resolveArch(feed)) else {
      throw UpdateCheckError.missingFeed
    }
    return try await SparkleSource.latest(feedURL: feedURL)
  case .html, .xml, .json, .yaml, .redirect:
    return try await HTTPVersionSource.latest(for: recipe)
  }
}

// MARK: - Download verification

func byteString(_ url: URL) -> String {
  let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
  return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
}

func bundleShortVersion(_ app: URL) -> String? {
  let plist = app.appendingPathComponent("Contents/Info.plist")
  guard let data = try? Data(contentsOf: plist),
    let object = try? PropertyListSerialization.propertyList(from: data, format: nil)
      as? [String: Any]
  else { return nil }
  return object["CFBundleShortVersionString"] as? String
}

func verifyDownload(recipe: UpdateRecipe, result: ReleaseResult) async -> Int32 {
  section("Download")
  guard let url = result.downloadURL else {
    out("no download URL (check-only recipe) — nothing to verify")
    return 0
  }
  guard
    let format = result.format.flatMap(ArchiveFormat.init(rawValue:))
      ?? ArchiveFormat(inferringFrom: url)
  else {
    errLine("cannot determine archive format for \(url.absoluteString)")
    return 3
  }

  out("url:     \(url.absoluteString)")
  out("format:  \(format.rawValue)")
  let downloaded: URL
  do {
    downloaded = try await Installer.download(url) { _ in }
  } catch {
    errLine("download failed: \(error)")
    return 3
  }
  out("size:    \(byteString(downloaded))")

  do {
    let app = try Installer.extractApp(
      from: downloaded, format: format,
      expectedBundleID: recipe.id, expectedName: recipe.name ?? recipe.id)
    out("app:     \(app.path)")
    if let version = bundleShortVersion(app) { out("bundle:  \(version)") }
    out("OK — extracted app's bundle id matches \(recipe.id)")
  } catch {
    errLine("extract/verify failed: \(error)")
    return 3
  }
  return 0
}

// MARK: - Run

func run() async -> Int32 {
  let options = parseOptions()
  let path = "\(options.recipesDir)/\(options.id).yml"

  guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
    errLine("error: no recipe at \(path)")
    return 1
  }

  let base: UpdateRecipe
  do {
    base = try YAMLDecoder().decode(UpdateRecipe.self, from: text)
  } catch {
    errLine("error: failed to parse \(path): \(error)")
    return 1
  }

  // Resolve the release channel up front: a channel can replace the entire `check`
  // block (e.g. Firefox ESR switches from html to a JSON source), so the dispatch
  // below must run against the channel-overlaid recipe, exactly like the app's
  // UpdateManager.effectiveRecipe.
  let channels = base.channelList
  if let requested = options.channel, channels.isEmpty {
    errLine("warning: \(base.id) defines no channels; ignoring --channel \(requested)")
  } else if let requested = options.channel,
    !channels.contains(where: { $0.id == requested })
  {
    errLine(
      "warning: no channel '\(requested)' — known: "
        + channels.map(\.id).joined(separator: ", ") + "; using default")
  }
  let selectedChannel = base.channel(id: options.channel)
  let recipe = base.applyingChannel(options.channel)

  section("Recipe")
  out("id:       \(recipe.id)")
  if let name = recipe.name { out("name:     \(name)") }
  if !channels.isEmpty {
    let list = channels.map { channel in
      let label = channel.name.map { "\(channel.id) (\($0))" } ?? channel.id
      return channel.id == selectedChannel?.id ? "\(label) *" : label
    }
    out("channels: \(list.joined(separator: ", "))   (* = selected)")
  }
  out("source:   \(recipe.check.kind.rawValue)")
  switch recipe.check.kind {
  case .githubReleases: recipe.check.repo.map { out("repo:     \($0)") }
  case .sparkle: recipe.check.feed.map { out("feed:     \($0)") }
  default: recipe.check.url.map { out("url:      \($0)") }
  }
  if GitHubToken.load() != nil { out("token:    using $GITHUB_TOKEN") }
  if options.prereleases { out("prerel:   included") }

  let result: ReleaseResult
  do {
    result = try await resolve(recipe, prereleases: options.prereleases)
  } catch {
    errLine("\nCHECK FAILED: \(error)")
    return 2
  }

  section("Result")
  out("raw tag:   \(result.tag)")
  out("version:   \(result.version)")
  result.build.map { out("build:     \($0)") }
  out("download:  \(result.downloadURL?.absoluteString ?? "—  (check-only)")")
  result.format.map { out("format:    \($0)") }
  // Mirror UpdateManager.resolveLatest: the source's own changelog wins, otherwise
  // fall back to the recipe's expanded changelog template (github/sparkle/appstore
  // sources don't set one themselves).
  let changelog =
    result.changelogURL?.absoluteString
    ?? recipe.changelogTemplate.map { recipe.expand($0, tag: result.tag, version: result.version) }
  changelog.map { out("changelog: \($0)") }
  result.appStoreURL.map { out("appstore:  \($0.absoluteString)") }

  if options.download {
    let code = await verifyDownload(recipe: recipe, result: result)
    if code != 0 { return code }
  }

  return 0
}

exit(await run())
