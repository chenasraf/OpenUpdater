//
//  GitHubToken.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation
import Security

/// Stores the optional GitHub personal access token in the macOS Keychain
/// (encrypted at rest). The token can't be hashed — it has to be sent verbatim in
/// the `Authorization` header — so the Keychain is the right secure store.
enum GitHubToken {
  private static let service = "dev.casraf.OpenUpdater"
  private static let account = "github-token"

  static func load() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let token = String(data: data, encoding: .utf8),
      !token.isEmpty
    else { return nil }
    return token
  }

  /// Save the token, or clear it when blank. Returns success.
  @discardableResult
  static func save(_ token: String) -> Bool {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return clear() }

    let identity: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let data = Data(trimmed.utf8)
    let update = SecItemUpdate(
      identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if update == errSecItemNotFound {
      var add = identity
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    return update == errSecSuccess
  }

  @discardableResult
  static func clear() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  static var exists: Bool { load() != nil }
}
