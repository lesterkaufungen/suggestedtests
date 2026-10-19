// swift-tools-version:5.10
import Foundation
import PackageDescription

// The published package (the suggestedtests-swift split repo) bundles the
// prebuilt native bridge in Sources/SuggestedTests/Prebuilt (tool/stage.sh
// swift). A monorepo checkout has no such directory and loads the libraries
// from native/prebuilt instead.
let bundled = FileManager.default.fileExists(
  atPath: Context.packageDirectory + "/Sources/SuggestedTests/Prebuilt")

let package = Package(
  name: "SuggestedTests",
  platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
  products: [
    .library(name: "SuggestedTests", targets: ["SuggestedTests"])
  ],
  targets: [
    .target(
      name: "SuggestedTests",
      resources: bundled ? [.copy("Prebuilt")] : [],
      swiftSettings: bundled ? [.define("SUGGESTEDTESTS_BUNDLED")] : []
    ),
    // Started by the tests in a fresh process: the bridge's startup report goes
    // to that process's stderr.
    .executableTarget(
      name: "SuggestedTestsReportCheck",
      dependencies: ["SuggestedTests"],
      path: "Tests/SuggestedTestsReportCheck"
    ),
    .testTarget(name: "SuggestedTestsTests", dependencies: ["SuggestedTests"]),
    .testTarget(name: "ExampleTests", dependencies: ["SuggestedTests"]),
  ]
)
