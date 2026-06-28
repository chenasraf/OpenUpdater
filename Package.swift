// swift-tools-version:5.9
//
// This manifest exists ONLY to build the `recipe-check` developer CLI (see
// Tools/recipe-check and `make recipe-check`). It compiles the app's REAL
// recipe-resolution sources unchanged so the CLI exercises the same logic the
// shipping app does. The app itself is built from OpenUpdater.xcodeproj, not this
// package — `xcodebuild -project` ignores this file.
import PackageDescription

let package = Package(
  name: "recipe-check",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams", from: "6.2.2")
  ],
  targets: [
    .executableTarget(
      name: "recipe-check",
      dependencies: ["Yams"],
      path: ".",
      sources: [
        // The app's real resolution logic, reused verbatim.
        "OpenUpdater/Updating/GitHubReleaseSource.swift",
        "OpenUpdater/Updating/SparkleSource.swift",
        "OpenUpdater/Updating/HTTPVersionSource.swift",
        "OpenUpdater/Updating/AppStoreSource.swift",
        "OpenUpdater/Updating/UpdateRecipe.swift",
        "OpenUpdater/Updating/SystemArch.swift",
        "OpenUpdater/Updating/Installer.swift",
        // The CLI driver + Foundation-only shims for the two UI/Keychain symbols
        // the sources reference (AppBranding, GitHubToken).
        "Tools/recipe-check",
      ]
    )
  ]
)
