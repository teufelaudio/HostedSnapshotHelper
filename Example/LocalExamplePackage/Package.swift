// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "LocalExamplePackage",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "LocalExamplePackage",
      targets: ["LocalExamplePackage"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/pointfreeco/swift-snapshot-testing",
      from: "1.0.0"
    ),
    .package(
      path: "../.."
    ),
  ],
  targets: [
    .target(
      name: "LocalExamplePackage",
      path: "Sources"
    ),
    .testTarget(
      name: "LocalExamplePackageTests",
      dependencies: [
        "LocalExamplePackage",
        .product(
          name: "HostedSnapshotHelper",
          package: "HostedSnapshotHelper"
        ),
        .product(
          name: "SnapshotTesting",
          package: "swift-snapshot-testing"
        ),
      ],
      exclude: [
        "__Snapshots__",
      ]
    ),
  ]
)
