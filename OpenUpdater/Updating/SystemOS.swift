//
//  SystemOS.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 14/11/2026.
//

import Foundation

/// The running macOS version, used to pick OS-specific downloads.
enum SystemOS {
  /// The major macOS version, e.g. `"26"` on Tahoe.
  static let major = String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
}
