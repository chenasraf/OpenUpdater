//
//  main.swift
//  OpenUpdaterHelper
//
//  Created by Chen Asraf on 21/06/2026.
//
//  Root LaunchDaemon. Vends an XPC service that performs privileged installs for
//  the app. Only the app — verified by code-signing requirement — may connect.
//

import Foundation
import Security

final class HelperService: NSObject, NSXPCListenerDelegate, HelperProtocol {

  // MARK: NSXPCListenerDelegate

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    // SECURITY: only accept connections from our signed app. Without this, any
    // process could ask this root helper to install arbitrary packages.
    guard Self.isValidClient(connection) else { return false }

    connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
    connection.exportedObject = self
    connection.resume()
    return true
  }

  /// Verify the connecting process satisfies `HelperConstants.clientRequirement`
  /// (it's our app, signed by our team), using its audit token — which, unlike a
  /// PID, can't be spoofed or reused. `OUCopyAuditToken` comes from the ObjC shim
  /// (XPCAuditToken.h, imported via the helper's bridging header).
  private static func isValidClient(_ connection: NSXPCConnection) -> Bool {
    guard let tokenData = OUCopyAuditToken(connection) else { return false }

    var code: SecCode?
    let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
      let guest = code
    else { return false }

    var requirement: SecRequirement?
    guard
      SecRequirementCreateWithString(
        HelperConstants.clientRequirement as CFString, [], &requirement) == errSecSuccess,
      let requirement
    else { return false }

    return SecCodeCheckValidity(guest, [], requirement) == errSecSuccess
  }

  // MARK: HelperProtocol

  func getVersion(withReply reply: @escaping (String) -> Void) {
    reply(HelperConstants.version)
  }

  func installPackage(atPath path: String, withReply reply: @escaping (Bool, String?) -> Void) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
    process.arguments = ["-pkg", path, "-target", "/"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
      let output = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      if process.terminationStatus == 0 {
        reply(true, nil)
      } else {
        reply(
          false,
          String(data: output, encoding: .utf8) ?? "installer exited \(process.terminationStatus)")
      }
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func replaceApp(
    atPath destination: String, withItemAtPath staged: String,
    withReply reply: @escaping (Bool, String?) -> Void
  ) {
    let fm = FileManager.default
    let dest = URL(fileURLWithPath: destination)
    let new = URL(fileURLWithPath: staged)
    // The new app arrives from the app's temp dir, which may be on a different
    // volume than the destination. Stage a copy next to the destination first so
    // the swap is same-volume (atomic) and replaceItemAt can't fail cross-volume.
    let local = dest.deletingLastPathComponent()
      .appendingPathComponent(".\(dest.lastPathComponent).incoming")
    do {
      try? fm.removeItem(at: local)
      try fm.copyItem(at: new, to: local)
      if fm.fileExists(atPath: destination) {
        _ = try fm.replaceItemAt(dest, withItemAt: local)
      } else {
        try fm.moveItem(at: local, to: dest)
      }
      reply(true, nil)
    } catch {
      try? fm.removeItem(at: local)
      reply(false, error.localizedDescription)
    }
  }
}

let delegate = HelperService()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
dispatchMain()
