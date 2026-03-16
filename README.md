# HostedSnapshotHelper

`HostedSnapshotHelper` lets you keep snapshot tests in a Swift package while re-running the key-window cases inside a host app test target.

This is useful for UI that does not render correctly in a package-only snapshot test, such as:

- `.sheet`
- `.fullScreenCover`
- `.alert`
- confirmation dialogs
- anything else that needs a real key window

The host app is only used for rendering. Recorded PNGs are still written back to the package that owns the tests.

## Why

If you snapshot a SwiftUI view directly from a package test, a presented sheet or alert is often missing from the image because there is no real key window:

```swift
@Test
func testSheetOpenState() {
  let sut = FeatureView(isSheetPresented: true)

  assertSnapshot(
    of: sut,
    as: .image(layout: .device(config: .iPhoneSe))
  )
}
```

`HostedSnapshotHelper` solves this by:

1. marking key-window tests in the package
2. generating matching XCTest methods in a host app test target
3. rendering those tests in a real app window
4. saving the resulting snapshots back into the package's `__Snapshots__` folder

## What It Contains

- `HostedSnapshotHelper`
  A library product for package tests and generated host-app tests.
- `HostedSnapshotRegistryGenerator`
  An executable that scans package test sources and generates the host-app XCTest file.

## Package Installation

Add the package to the package-under-test and to the host app project:

- GitHub: `https://github.com/teufelaudio/HostedSnapshotHelper`
- local checkout during development: `.package(path: "../HostedSnapshotHelper")`

Until the first tagged release exists, use a branch-based dependency such as:

```swift
.package(url: "https://github.com/teufelaudio/HostedSnapshotHelper", branch: "main")
```

After the first release, prefer a versioned dependency.

The package itself currently supports:

- iOS 26+
- macOS 13+

## Package Under Test

Add `HostedSnapshotHelper` to the package that owns the Swift Testing snapshot tests.

Example:

```swift
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "FeaturePackage",
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.0.0"),
    .package(url: "https://github.com/teufelaudio/HostedSnapshotHelper", branch: "main"),
  ],
  targets: [
    .target(name: "Feature"),
    .testTarget(
      name: "FeatureTests",
      dependencies: [
        "Feature",
        .product(name: "HostedSnapshotHelper", package: "HostedSnapshotHelper"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ]
    ),
  ]
)
```

## Writing Tests

Keep ordinary snapshots unchanged:

```swift
import SnapshotTesting
import Testing
import Feature

@MainActor
struct FeatureSnapshotTests {
  @Test
  func testClosedState() {
    let sut = FeatureView()

    assertSnapshot(
      of: sut,
      as: .image(layout: .device(config: .iPhoneSe))
    )
  }
}
```

For key-window cases, split them into their own tests and use `assertHostedSnapshot(of:)`:

```swift
import SnapshotTesting
import Testing
import Feature
import HostedSnapshotHelper

@MainActor
struct FeatureSnapshotTests {
  @Test(.requiresKeyWindow)
  func testSheetOpenState() {
    let sut = FeatureView(isSheetPresented: true)
    assertHostedSnapshot(of: sut)
  }
}
```

You can also provide a custom disable message:

```swift
@Test(.requiresKeyWindow("Hosted snapshots run in the app-hosted test suite."))
func testSheetOpenState() {
  let sut = FeatureView(isSheetPresented: true)
  assertHostedSnapshot(of: sut)
}
```

And you can customize hosted assertions similarly to `assertSnapshot(...)` wrappers:

```swift
assertHostedSnapshot(
  of: sut,
  devices: [
    ("iPhoneSE3rdGen", .iPhoneSE3rdGen),
    ("iPadPro12_9", .iPadPro12_9(.portrait)),
  ],
  style: [.light, .dark],
  wait: 0.5,
  named: "dark",
  record: nil,
  timeout: 5
)
```

### What `.requiresKeyWindow` Does

`.requiresKeyWindow` is a custom `Testing` trait provided by this package.

In the package test target it behaves like:

- disable this test by default
- keep it discoverable by the generator

If you want to run those package tests directly anyway, set:

```sh
RUN_HOSTED_PACKAGE_TESTS=1
```

## Generator Rules

The generator scans the package's `Tests` directory and looks for `@Test` declarations containing `.requiresKeyWindow`.

For each hosted test, it requires:

- exactly one `assertHostedSnapshot(...)` call
- a self-contained test body that can be replayed in the host app test target

It preserves:

- the test body
- non-`Testing` and non-`SnapshotTesting` imports from the source file
- the original package snapshot directory
- the original package test name

That last point is important: hosted snapshots are rendered in the app, but saved in the package's snapshot folder.

## Host App Integration

Add the package to the host app Xcode project and link `HostedSnapshotHelper` in the host app test target.

The host app test target must also be able to import the package-under-test.

Typical setup:

- app target imports the feature package normally
- app test target links `HostedSnapshotHelper`
- generated XCTest file is written into the app test target's source directory

## Xcode Build Phase

Add a Run Script build phase so the host app regenerates the hosted test file before building tests.

Example:

```sh
set -eu

OUTPUT_FILE="${SRCROOT}/MyAppTests/HostedSnapshotTests.generated.swift"
PACKAGE_ROOT="${SRCROOT}/FeaturePackage"
HELPER_ROOT="${SRCROOT}/HostedSnapshotHelper"

env -u SDKROOT -u PLATFORM_NAME -u EFFECTIVE_PLATFORM_NAME -u ARCHS \
  xcrun --sdk macosx swift run \
  --package-path "$HELPER_ROOT" \
  HostedSnapshotRegistryGenerator \
  --package-root "$PACKAGE_ROOT" \
  --output "$OUTPUT_FILE"
```

Notes:

- use `xcrun --sdk macosx swift run`
  The generator is a macOS host tool, not an iOS binary.
- unset `SDKROOT`, `PLATFORM_NAME`, `EFFECTIVE_PLATFORM_NAME`, and `ARCHS`
  Xcode can leak iOS build settings into `swift run`, which breaks SwiftPM manifest evaluation.
- write the generated file into the host app test target directory
- if you integrate `HostedSnapshotHelper` as a remote Xcode package instead of a sibling checkout, `HELPER_ROOT` is typically:
  `"$SOURCEPACKAGES_DIR_PATH/checkouts/HostedSnapshotHelper"`

## Generated XCTest File

The generated file contains XCTest methods that replay the tagged package tests inside the host app test target.

Those generated tests call into `assertHostedSnapshot(of:)`, which:

- creates a temporary key `UIWindow`
- renders the view in a real app scene
- waits for presentation to settle
- captures the full hosted window
- saves the image into the package snapshot directory

## API Summary

Library:

```swift
extension Trait where Self == ConditionTrait {
  public static var requiresKeyWindow: Self { get }
  public static func requiresKeyWindow(
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self
}

@MainActor
public func assertHostedSnapshot<Content: View>(
  of view: @autoclosure () -> Content,
  devices: [HostedSnapshotDevice] = [("iPhone13Pro", .iPhone13Pro)],
  style: Set<ColorScheme> = [.light],
  wait: TimeInterval = 1,
  named name: String? = nil,
  record recording: Bool? = nil,
  timeout: TimeInterval = 5,
  precision: Float = 1,
  perceptualPrecision: Float = 1,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
)

@MainActor
public func assertHostedSnapshot<Content: View>(
  of view: @autoclosure () -> Content,
  on config: ViewImageConfig = .iPhone13Pro,
  style: UIUserInterfaceStyle = .light,
  wait: TimeInterval = 1,
  named name: String? = nil,
  record recording: Bool? = nil,
  timeout: TimeInterval = 5,
  precision: Float = 1,
  perceptualPrecision: Float = 1,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
)
```

Executable:

```sh
HostedSnapshotRegistryGenerator --package-root <path> --output <path>
```

## Constraints

- hosted tests must call `assertHostedSnapshot(...)` directly
- the generator currently expects exactly one hosted assertion per tagged test
- tagged tests should avoid extra wrappers around the hosted assertion
- any imports used by the tagged package test must also be valid in the host app test target

## Xcode Tips

If you want package tests to show normal run controls in Xcode:

- open a workspace that contains both the host app project and the Swift package
- select the package scheme when running package tests directly
- use an iOS Simulator destination

If the package tests are wrapped in `#if canImport(UIKit)`, they will not appear when the active destination is `My Mac`.
