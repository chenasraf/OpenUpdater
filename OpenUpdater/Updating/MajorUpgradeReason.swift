//
//  MajorUpgradeReason.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 28/07/2026.
//

import Foundation

/// Resolves a recipe's `manual_major_upgrades_reason` into the sentence shown in the
/// "major version upgrade" warning. A recognized preset key maps to a built-in message
/// (so common cases read consistently and can be localized in one place); anything else
/// is free text used verbatim.
nonisolated enum MajorUpgradeReason {
  /// Preset reason keys and the message each expands to. Extend as common reasons come
  /// up; document new keys in `docs/recipe-template.yml`.
  static let presets: [String: String] = [
    "paid_license": "A new major version of this app usually requires buying a new license.",
    "subscription": "A new major version may need a new or upgraded subscription.",
    "breaking_changes":
      "A new major version may include breaking changes worth reviewing before you upgrade.",
  ]

  /// The message for a recipe's `manual_major_upgrades_reason`: the built-in text for a
  /// known preset key (case-insensitive), otherwise the raw value used verbatim.
  static func message(for raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return presets[trimmed.lowercased()] ?? trimmed
  }
}
