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
  case tar  // .tar and compressed tarballs (.tar.gz/.tgz/.tar.xz/.tar.bz2)

  /// Infer from a filename/URL extension (e.g. an appcast enclosure URL).
  init?(inferringFrom url: URL) {
    // Tarballs use a compound extension (.tar.gz, .tgz); `pathExtension` only sees the
    // final component, so match the whole filename for those.
    let name = url.lastPathComponent.lowercased()
    if name.hasSuffix(".tar") || name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz")
      || name.hasSuffix(".tar.xz") || name.hasSuffix(".tar.bz2")
    {
      self = .tar
      return
    }
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
  case notAnArchive

  var description: String {
    switch self {
    case .unsupportedFormat(let f): return "Can't install \(f) archives yet"
    case .downloadFailed(let code): return "Download failed (HTTP \(code))"
    case .noAppInArchive: return "No app found in the download"
    case .notAnArchive: return "The download wasn't a valid archive (got a web page?)"
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
///
/// `nonisolated` is REQUIRED: the project defaults to `@MainActor` isolation, so
/// without this the heavy `hdiutil`/`ditto` copies (and the blocking subprocess
/// waits) would hop back to the main thread inside `Task.detached` and freeze the
/// UI on large apps.
nonisolated enum Installer {
  /// Download the archive to a temporary file, reporting fractional progress
  /// (0…1) as bytes arrive. The temp file keeps the source URL's extension —
  /// dmg/zip are content-sniffed, but `installer` needs a `.pkg` path.
  static func download(_ url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws
    -> URL
  {
    let delegate = DownloadDelegate(onProgress: onProgress)
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    delegate.session = session
    let task = session.downloadTask(with: url)
    // Cancelling the install Task aborts the download (resumes with URLError.cancelled).
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        delegate.continuation = continuation
        task.resume()
      }
    } onCancel: {
      task.cancel()
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
    _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
  }

  /// Extract `archive` and return the contained `.app`, verifying it's the app we
  /// expect. Matches on bundle id; if the download has none (some Qt builds, e.g.
  /// Converseen, ship an empty `CFBundleIdentifier`), falls back to matching the
  /// app's name (case-insensitive) against the installed one. The returned app
  /// lives in a fresh temp directory.
  static func extractApp(
    from archive: URL, format: ArchiveFormat, expectedBundleID: String, expectedName: String
  ) throws -> URL {
    // A misconfigured recipe can yield an HTML landing page instead of the binary;
    // fail clearly here rather than as a cryptic "hdiutil/ditto failed".
    if looksLikeHTML(archive) { throw InstallError.notAnArchive }

    let work = try makeTempDir()
    let app: URL
    switch format {
    case .zip:
      try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
      app = try locateApp(in: work)
    case .tar:
      // bsdtar detects gzip/xz/bzip2 from the content, so `-xf` covers every tarball
      // regardless of the temp file's extension.
      try run("/usr/bin/tar", ["-xf", archive.path, "-C", work.path])
      app = try locateApp(in: work)
    case .dmg:
      app = try extractFromDMG(archive, into: work)
    case .pkg:
      throw InstallError.unsupportedFormat("pkg")
    }

    if let foundID = bundleID(of: app), !foundID.isEmpty {
      guard foundID == expectedBundleID else {
        throw InstallError.bundleIDMismatch(expected: expectedBundleID, found: foundID)
      }
    } else {
      let foundName = app.deletingPathExtension().lastPathComponent
      guard foundName.compare(expectedName, options: .caseInsensitive) == .orderedSame else {
        throw InstallError.bundleIDMismatch(
          expected: expectedBundleID, found: "\(foundName) (no bundle id)")
      }
    }
    return app
  }

  /// Replace the app at `destination` with `newApp`, sending the old one to the
  /// Trash. Uses `replaceItemAt` for an in-place, same-volume swap.
  static func replaceApp(at destination: URL, with newApp: URL) throws {
    let directory = destination.deletingLastPathComponent()
    // Replacing needs write access to both the containing directory and the existing
    // bundle — some apps (e.g. Google Chrome, left root-owned by Keystone) sit in a
    // writable /Applications but are themselves owned by another user.
    let existing = FileManager.default.fileExists(atPath: destination.path)
    guard FileManager.default.isWritableFile(atPath: directory.path),
      !existing || FileManager.default.isWritableFile(atPath: destination.path)
    else {
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
      // Surface permission failures as `.notWritable` so the caller can retry the
      // swap through the privileged helper instead of treating it as fatal.
      if isPermissionDenied(error) { throw InstallError.notWritable(destination) }
      throw error
    }
  }

  /// Squirrel.Mac apps (Discord, Slack, and most Electron apps) self-update through a
  /// `ShipIt` helper: the app stages a copy of an update and writes a pending request
  /// that, on its next launch, copies that staged bundle over the app in `/Applications`.
  /// After we replace such an app in place, that pending request rolls our update right
  /// back to the staged (now stale) version — exactly the "update, re-scan, same version"
  /// loop. Remove any pending request that targets the app we just installed, along with
  /// the staged bundle it points at, so our update sticks. Matched by the request's
  /// `targetBundleURL` so we never touch another app's pending update.
  static func clearPendingSquirrelUpdate(for installedApp: URL) {
    guard isSquirrelApp(installedApp) else { return }
    let fm = FileManager.default
    let targetPath = installedApp.standardizedFileURL.path

    // Squirrel keeps its state in a per-app directory under Application Support (e.g.
    // Discord's `~/Library/Application Support/discord/`) or Caches.
    let roots =
      fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      + fm.urls(for: .cachesDirectory, in: .userDomainMask)
    for root in roots {
      let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
      for dir in dirs {
        let request = dir.appendingPathComponent("ShipIt_request.json")
        guard let data = try? Data(contentsOf: request),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let targetString = json["targetBundleURL"] as? String,
          URL(string: targetString)?.standardizedFileURL.path == targetPath
        else { continue }
        // Drop the staged bundle this request would have reinstalled (…/app-<version>/).
        if let updateString = json["updateBundleURL"] as? String,
          let staged = URL(string: updateString)?.deletingLastPathComponent(),
          staged.lastPathComponent.hasPrefix("app-")
        {
          try? fm.removeItem(at: staged)
        }
        try? fm.removeItem(at: request)
      }
    }
  }

  /// Whether `app` bundles Squirrel.Mac — the self-update framework most Electron apps
  /// ship (`Contents/Frameworks/Squirrel.framework`).
  private static func isSquirrelApp(_ app: URL) -> Bool {
    FileManager.default.fileExists(
      atPath: app.appendingPathComponent("Contents/Frameworks/Squirrel.framework").path)
  }

  /// Whether `error` (or any error it wraps) is a permission-denied failure —
  /// Cocoa's `NSFileWriteNoPermissionError` or POSIX `EACCES`/`EPERM`.
  private static func isPermissionDenied(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError {
      return true
    }
    if nsError.domain == NSPOSIXErrorDomain,
      nsError.code == Int(EACCES) || nsError.code == Int(EPERM)
    {
      return true
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      return isPermissionDenied(underlying)
    }
    return false
  }

  // MARK: - Helpers

  private static func extractFromDMG(_ dmg: URL, into work: URL) throws -> URL {
    let mount = try makeTempDir().appendingPathComponent("mnt")
    try attachDMG(dmg, at: mount)
    defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

    let sourceApp = try locateApp(in: mount)
    // Copy the app off the read-only image with ditto (preserves signing).
    let dest = work.appendingPathComponent(sourceApp.lastPathComponent)
    try run("/usr/bin/ditto", [sourceApp.path, dest.path])
    return dest
  }

  /// Attach a disk image, auto-accepting any software license agreement (some
  /// dmgs, e.g. Cura and FreeCAD, have an SLA that makes `hdiutil` wait forever for
  /// a "Y" on stdin). We feed it "y" and discard the (potentially large) agreement
  /// text.
  private static func attachDMG(_ dmg: URL, at mount: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    process.arguments = [
      "attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-noautoopen",
      "-mountpoint", mount.path,
    ]
    // hdiutil shows a long SLA through a pager ($PAGER, default `more`), and the "y"
    // keystrokes never escape it, so the attach hangs until the timeout. Forcing
    // `PAGER=cat` makes hdiutil dump the agreement and read our "y" at the prompt.
    var environment = ProcessInfo.processInfo.environment
    environment["PAGER"] = "cat"
    process.environment = environment
    let input = Pipe()
    let errorPipe = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice  // discard the SLA text (can be large)
    process.standardError = errorPipe

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    // Accept the agreement; the extra lines are harmless if there's no SLA.
    input.fileHandleForWriting.write(Data(String(repeating: "y\n", count: 1000).utf8))
    try? input.fileHandleForWriting.close()

    if finished.wait(timeout: .now() + 300) == .timedOut {
      process.terminate()
      throw InstallError.toolFailed("hdiutil", "timed out attaching disk image")
    }
    if process.terminationStatus != 0 {
      let message =
        String(
          data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw InstallError.toolFailed("hdiutil", message)
    }
  }

  /// True if the file's first bytes look like an HTML/XML document (a download
  /// that resolved to a web page rather than the real archive).
  private static func looksLikeHTML(_ file: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
    defer { try? handle.close() }
    let head = (try? handle.read(upToCount: 512)) ?? Data()
    guard let text = String(data: head, encoding: .utf8) else { return false }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.hasPrefix("<!doctype html") || trimmed.hasPrefix("<html")
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
      .appendingPathComponent("\(AppBranding.title)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Run a tool and return its combined output. Always called off the main thread
  /// (the cooperative pool), so blocking here is fine. A `timeout` bounds hung tools
  /// — e.g. `hdiutil` waiting forever on a disk image's license agreement — so an
  /// install can't linger indefinitely. (Output is small for the tools we run, so
  /// reading after exit can't deadlock on a full pipe buffer.)
  @discardableResult
  private static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 600) throws
    -> String
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()

    if finished.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      throw InstallError.toolFailed(
        (tool as NSString).lastPathComponent, "timed out after \(Int(timeout))s")
    }

    let output = pipe.fileHandleForReading.readDataToEndOfFile()
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
      var destination = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      // Preserve the source extension. dmg/zip are content-sniffed, but `installer`
      // rejects a `.pkg` whose path has no recognizable package extension.
      if let ext = downloadTask.originalRequest?.url?.pathExtension, !ext.isEmpty {
        destination.appendPathExtension(ext)
      }
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
