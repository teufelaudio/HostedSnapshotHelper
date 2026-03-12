// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "HostedSnapshotHelper",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "HostedSnapshotHelper",
      targets: ["HostedSnapshotHelper"]
    ),
    .executable(
      name: "HostedSnapshotRegistryGenerator",
      targets: ["HostedSnapshotRegistryGenerator"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/pointfreeco/swift-snapshot-testing",
      from: "1.0.0"
    ),
    .package(
      url: "https://github.com/swiftlang/swift-syntax",
      from: "602.0.0"
    ),
  ],
  targets: [
    .target(
      name: "HostedSnapshotHelper",
      dependencies: [
        .product(
          name: "SnapshotTesting",
          package: "swift-snapshot-testing"
        ),
      ]
    ),
    .executableTarget(
      name: "HostedSnapshotRegistryGenerator",
      dependencies: [
        .product(
          name: "SwiftParser",
          package: "swift-syntax"
        ),
        .product(
          name: "SwiftSyntax",
          package: "swift-syntax"
        ),
      ]
    ),
  ]
)
