//
//  HelperProtocol.swift
//  OpenUpdaterHelper
//
//  Created by Chen Asraf on 21/06/2026.
//
//  Shared XPC contract. Keep this identical to
//  OpenUpdater/Updating/HelperProtocol.swift.
//

import Foundation

enum HelperConstants {
  static let machServiceName = "dev.casraf.OpenUpdater.Helper"
  static let daemonPlistName = "dev.casraf.OpenUpdater.Helper.plist"
  static let version = "2"

  static let clientRequirement =
    "identifier \"dev.casraf.OpenUpdater\" and anchor apple generic and "
    + "certificate leaf[subject.OU] = \"Y893L6NQP2\""
}

@objc protocol HelperProtocol {
  func installPackage(atPath path: String, withReply reply: @escaping (Bool, String?) -> Void)

  func replaceApp(
    atPath destination: String, withItemAtPath staged: String,
    withReply reply: @escaping (Bool, String?) -> Void)

  func getVersion(withReply reply: @escaping (String) -> Void)
}
