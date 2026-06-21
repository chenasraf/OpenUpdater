//
//  Installer.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation

enum ArchiveFormat: String {
  case dmg
  case zip
  case pkg

  /// Infer from a filename/URL extension (e.g. an appcast enclosure URL).
  init?(inferringFrom url: URL) {
    switch url.pathExtension.lowercased() {
    case "dmg": self = .dmg
    case "zip": self = .zip
    case "pkg", "mpkg": self = .pkg
    default: return nil
    }
  }
}

enum InstallError: Error, CustomStringConvertible {
  case unsupportedFormat(String)
  case downloadFailed(Int)
  case noAppInArchive
  case bundleIDMismatch(expected: String, found: String?)
  case toolFailed(String, String)
  case notWritable(URL)
  case installerFailed(String)

  var description: String {
    switch self {
    case .unsupportedFormat(let f): return "Can't install \(f) archives yet"
    case .downloadFailed(let code): return "Download failed (HTTP \(code))"
    case .noAppInArchive: return "No app found in the download"
    case .bundleIDMismatch(let expected, let found):
      return "Downloaded app is \(found ?? "unknown"), expected \(expected)"
    case .toolFailed(let tool, _): return "\(tool) failed"
    case .notWritable(let url): return "No permission to replace \(url.lastPathComponent)"
    case .installerFailed(let message):
      let lower = message.lowercased()
      if lower.contains("-128") || lower.contains("cancel") { return "Installation was cancelled" }
      return "The installer failed"
    }
  }
}

/// Downloads an app update and installs it in place. Decoupled from the app model:
/// callers pass primitives so this can be exercised in isolation.
///
/// Not sandbox-safe — requires writing to the app's directory and running
/// `hdiutil`/`ditto`, which is why the app ships without the App Sandbox.
enum Installer {
  /// Download the archive to a temporary file, reporting fractional progress
  /// (0…1) as bytes arrive. `hdiutil`/`ditto` detect format by content, so the
  /// downloaded file doesn't need a particular extension.
  static func download(_ url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws
    -> URL
  {
    let delegate = DownloadDelegate(onProgress: onProgress)
    return try await withCheckedThrowingContinuation { continuation in
      delegate.continuation = continuation
      let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
      delegate.session = session
      session.downloadTask(with: url).resume()
    }
  }

  /// Run a downloaded `.pkg` through the system installer. This needs admin
  /// rights, so it's run via an authorization prompt — the password dialog is the
  /// user's consent (a package can run arbitrary install scripts). The temp file
  /// has a UUID name, so the path is safe to embed in the AppleScript/shell.
  static func installPkg(_ pkg: URL) throws {
    let shellCommand = "/usr/sbin/installer -pkg '\(pkg.path)' -target /"
    let appleScript = "do shell script \"\(shellCommand)\" with administrator privileges"
    do {
      try run("/usr/bin/osascript", ["-e", appleScript])
    } catch InstallError.toolFailed(_, let output) {
      throw InstallError.installerFailed(output)
    }
  }

  /// Strip the quarantine flag IFF the new app is validly signed by the same
  /// team as the installed app — i.e. a trusted same-developer update, so it
  /// launches without a Gatekeeper prompt. Anything else keeps quarantine so
  /// Gatekeeper vets it on first launch (this never bypasses security).
  static func clearQuarantineIfTrusted(_ newApp: URL, installedAppForTrust installed: URL) {
    guard signatureIsValid(newApp) else { return }
    guard let team = teamIdentifier(newApp), team == teamIdentifier(installed) else { return }
    try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
  }

  /// Extract `archive` and return the contained `.app` whose bundle ID matches
  /// `expectedBundleID`. The returned app lives in a fresh temp directory.
  static func extractApp(from archive: URL, format: ArchiveFormat, expectedBundleID: String) throws
    -> URL
  {
    let work = try makeTempDir()
    let app: URL
    switch format {
    case .zip:
      try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
      app = try locateApp(in: work)
    case .dmg:
      app = try extractFromDMG(archive, into: work)
    case .pkg:
      throw InstallError.unsupportedFormat("pkg")
    }

    let foundID = bundleID(of: app)
    guard foundID == expectedBundleID else {
      throw InstallError.bundleIDMismatch(expected: expectedBundleID, found: foundID)
    }
    return app
  }

  /// Replace the app at `destination` with `newApp`, sending the old one to the
  /// Trash. Uses `replaceItemAt` for an in-place, same-volume swap.
  static func replaceApp(at destination: URL, with newApp: URL) throws {
    let directory = destination.deletingLastPathComponent()
    guard FileManager.default.isWritableFile(atPath: directory.path) else {
      throw InstallError.notWritable(destination)
    }

    // Stage a copy next to the destination (same volume) so the swap is atomic.
    let staged = directory.appendingPathComponent(".\(destination.lastPathComponent).incoming")
    try? FileManager.default.removeItem(at: staged)
    try FileManager.default.copyItem(at: newApp, to: staged)

    do {
      _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
    } catch {
      // replaceItemAt moves the original aside; if the destination is missing
      // (fresh install), fall back to a plain move.
      try? FileManager.default.removeItem(at: staged)
      throw error
    }
  }

  // MARK: - Helpers

  private static func extractFromDMG(_ dmg: URL, into work: URL) throws -> URL {
    let mount = try makeTempDir().appendingPathComponent("mnt")
    try run(
      "/usr/bin/hdiutil",
      [
        "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path,
      ])
    defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

    let sourceApp = try locateApp(in: mount)
    // Copy the app off the read-only image with ditto (preserves signing).
    let dest = work.appendingPathComponent(sourceApp.lastPathComponent)
    try run("/usr/bin/ditto", [sourceApp.path, dest.path])
    return dest
  }

  /// Find the first `.app` bundle in `directory` (shallow, then one level deep).
  private static func locateApp(in directory: URL) throws -> URL {
    let fm = FileManager.default
    let top = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    if let app = top.first(where: { $0.pathExtension == "app" }) { return app }
    for sub in top where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    {
      let nested = (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil)) ?? []
      if let app = nested.first(where: { $0.pathExtension == "app" }) { return app }
    }
    throw InstallError.noAppInArchive
  }

  private static func bundleID(of app: URL) -> String? {
    let plist = app.appendingPathComponent("Contents/Info.plist")
    return (NSDictionary(contentsOf: plist) as? [String: Any])?["CFBundleIdentifier"] as? String
  }

  private static func signatureIsValid(_ app: URL) -> Bool {
    (try? run("/usr/bin/codesign", ["--verify", "--strict", app.path])) != nil
  }

  /// The Developer ID team identifier from an app's code signature, or `nil` if
  /// unsigned / not set. `codesign -dvv` prints this to stderr (merged in `run`).
  private static func teamIdentifier(_ app: URL) -> String? {
    guard let output = try? run("/usr/bin/codesign", ["-dvv", app.path]) else { return nil }
    for line in output.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
      let value = line.dropFirst("TeamIdentifier=".count)
      return value == "not set" ? nil : String(value)
    }
    return nil
  }

  private static func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("OpenUpdater-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  @discardableResult
  private static func run(_ tool: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(data: output, encoding: .utf8) ?? ""
    if process.terminationStatus != 0 {
      throw InstallError.toolFailed((tool as NSString).lastPathComponent, text)
    }
    return text
  }
}

/// Bridges `URLSessionDownloadDelegate` callbacks to async/await with progress.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let onProgress: @Sendable (Double) -> Void
  var continuation: CheckedContinuation<URL, Error>?
  var session: URLSession?
  private var lastPercent = -1

  init(onProgress: @escaping @Sendable (Double) -> Void) {
    self.onProgress = onProgress
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    let percent = Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
    guard percent != lastPercent else { return }  // throttle to whole percents
    lastPercent = percent
    onProgress(Double(percent) / 100)
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // The HTTP error body still "downloads" successfully — check the status.
    if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
      continuation?.resume(throwing: InstallError.downloadFailed(http.statusCode))
      continuation = nil
      return
    }
    // `location` is removed once this returns, so move it out synchronously.
    do {
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try FileManager.default.moveItem(at: location, to: destination)
      continuation?.resume(returning: destination)
    } catch {
      continuation?.resume(throwing: error)
    }
    continuation = nil
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error, continuation != nil {
      continuation?.resume(throwing: error)
      continuation = nil
    }
    session.finishTasksAndInvalidate()
  }
}
