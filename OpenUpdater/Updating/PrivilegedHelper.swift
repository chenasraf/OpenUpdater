//
//  PrivilegedHelper.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation
import ServiceManagement

enum HelperError: Error, CustomStringConvertible {
  case unavailable
  case failed(String)

  var description: String {
    switch self {
    case .unavailable: return "The privileged helper isn't available"
    case .failed(let message): return message
    }
  }
}

/// Manages the optional root helper that installs updates without an admin prompt
/// each time. Registered once via `SMAppService` (the user approves it once in
/// System Settings → Login Items), then reached over XPC. When it isn't installed
/// or approved, callers fall back to the per-install authorization prompt.
@MainActor
final class PrivilegedHelper {
  static let shared = PrivilegedHelper()

  private var connection: NSXPCConnection?
  private var service: SMAppService {
    SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
  }

  /// Current registration status (enabled / requiresApproval / notRegistered / notFound).
  var status: SMAppService.Status { service.status }
  var isEnabled: Bool { service.status == .enabled }

  /// Register the daemon. If it returns `.requiresApproval`, the user must enable
  /// OpenUpdater under System Settings → General → Login Items & Extensions.
  @discardableResult
  func register() throws -> SMAppService.Status {
    if service.status != .enabled {
      try service.register()
    }
    return service.status
  }

  func unregister() async throws {
    try await service.unregister()
    connection?.invalidate()
    connection = nil
  }

  // MARK: - XPC

  private func makeProxy(onError: @escaping (Error) -> Void) -> HelperProtocol? {
    let connection = activeConnection()
    return connection.remoteObjectProxyWithErrorHandler { error in
      onError(HelperError.failed(error.localizedDescription))
    } as? HelperProtocol
  }

  private func activeConnection() -> NSXPCConnection {
    if let connection { return connection }
    let new = NSXPCConnection(
      machServiceName: HelperConstants.machServiceName, options: .privileged)
    new.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
    new.invalidationHandler = { [weak self] in
      Task { @MainActor in self?.connection = nil }
    }
    new.resume()
    connection = new
    return new
  }

  /// Confirm the installed helper answers and matches our expected version.
  func ping() async -> Bool {
    await withCheckedContinuation { continuation in
      guard let proxy = makeProxy(onError: { _ in continuation.resume(returning: false) }) else {
        continuation.resume(returning: false)
        return
      }
      proxy.getVersion { version in
        continuation.resume(returning: version == HelperConstants.version)
      }
    }
  }

  func installPackage(at path: String) async throws {
    try await call { proxy, done in proxy.installPackage(atPath: path, withReply: done) }
  }

  func replaceApp(at destination: String, with staged: String) async throws {
    try await call { proxy, done in
      proxy.replaceApp(atPath: destination, withItemAtPath: staged, withReply: done)
    }
  }

  /// Bridge a `(Bool, String?)`-reply helper method to async/throws.
  private func call(
    _ body: @escaping (HelperProtocol, @escaping (Bool, String?) -> Void) -> Void
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      guard let proxy = makeProxy(onError: { continuation.resume(throwing: $0) }) else {
        continuation.resume(throwing: HelperError.unavailable)
        return
      }
      body(proxy) { ok, message in
        if ok {
          continuation.resume()
        } else {
          continuation.resume(throwing: HelperError.failed(message ?? "Operation failed"))
        }
      }
    }
  }
}
