//
//  SystemArch.swift
//  OpenUpdater
//
//  Created by Chen Asraf on 21/06/2026.
//

import Foundation

/// The Mac's native CPU architecture, used to pick arch-specific downloads.
enum SystemArch {
  /// `"arm64"` on Apple Silicon (even when the app runs under Rosetta),
  /// otherwise `"x86_64"`.
  static let current: String = {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0, value == 1 {
      return "arm64"
    }
    return "x86_64"
  }()
}
