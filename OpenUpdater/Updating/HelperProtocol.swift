//
//  HelperProtocol.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//
//  Shared XPC contract between the app and the privileged helper. Keep this file
//  identical to OpenUpdaterHelper/HelperProtocol.swift.
//

import Foundation

enum HelperConstants {
  /// Mach service the helper vends and the app connects to.
  static let machServiceName = "dev.casraf.OpenUpdater.Helper"
  /// LaunchDaemon plist embedded at Contents/Library/LaunchDaemons/<this>.
  static let daemonPlistName = "dev.casraf.OpenUpdater.Helper.plist"
  /// Bumped when the protocol/behavior changes, so the app can re-register a stale helper.
  static let version = "1"

  /// Code-signing requirement the HELPER enforces on callers: only our app, signed
  /// by our team, may command the root helper. This is the core security gate.
  static let clientRequirement =
    "identifier \"dev.casraf.OpenUpdater\" and anchor apple generic and "
    + "certificate leaf[subject.OU] = \"Y893L6NQP2\""
}

/// Privileged operations the helper performs as root on the app's behalf.
@objc protocol HelperProtocol {
  /// Run a downloaded `.pkg` through `/usr/sbin/installer`.
  func installPackage(atPath path: String, withReply reply: @escaping (Bool, String?) -> Void)

  /// Replace the app at `destination` with the already-extracted app at `staged`
  /// (used when `/Applications` isn't writable by the user).
  func replaceApp(
    atPath destination: String, withItemAtPath staged: String,
    withReply reply: @escaping (Bool, String?) -> Void)

  /// Handshake — returns the helper's `HelperConstants.version`.
  func getVersion(withReply reply: @escaping (String) -> Void)
}
