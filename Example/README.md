# HostedSnapshotHelper Example Project

This folder contains a complete example host app setup that uses `HostedSnapshotHelper` end-to-end:

- `LocalExamplePackage/` is the package under test.
- `SnapshotsInPackages/` is the iOS host app target.
- `SnapshotsInPackagesTests/LocalExamplePackageHostedSnapshotTests.generated.swift` is generated from the package tests.

## Notes

- The example package intentionally uses plain SwiftUI state and bindings (no TCA).
- `LocalExamplePackage/Tests/LocalExamplePackageTests/FooViewSnapshotTests.swift` keeps one normal snapshot test and two hosted snapshot tests.
- Hosted tests are tagged with `.requiresKeyWindow` and call `assertHostedSnapshot(of:)` directly (optionally with `on`, `named`, `record`, `timeout`, etc.).
- The app target has a build phase that runs `HostedSnapshotRegistryGenerator` before tests build.
- Snapshots are still written to `LocalExamplePackage/Tests/LocalExamplePackageTests/__Snapshots__/...`.

## Open and Run

1. Open `SnapshotsInPackages.xcodeproj`.
2. Select an iOS simulator destination.
3. Run the `SnapshotsInPackagesTests` test target.

The generated host tests replay the tagged package tests with a real key window.
