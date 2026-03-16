import Foundation
import SnapshotTesting
import SwiftUI
import XCTest

#if canImport(UIKit)
  import UIKit

  @MainActor
  private enum HostedSnapshotContext {
    static var snapshotDirectory: String?
    static var testName: String?
  }

  public typealias HostedSnapshotDevice = (name: String, device: ViewImageConfig)

  private let defaultHostedSnapshotDevices: [HostedSnapshotDevice] = [
    ("iPhone13Pro", .iPhone13Pro),
  ]

  @MainActor
  public func assertHostedSnapshot<Content: View>(
    of view: @autoclosure () -> Content,
    devices: [HostedSnapshotDevice] = defaultHostedSnapshotDevices,
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
  ) {
    for config in devices {
      for colorScheme in style {
        let suffix = switch colorScheme {
        case .light: "-light"
        case .dark: "-dark"
        @unknown default: fatalError("Unhandled ColorScheme \(colorScheme)")
        }
        let uiStyle: UIUserInterfaceStyle = switch colorScheme {
        case .light: .light
        case .dark: .dark
        @unknown default: .unspecified
        }

        let image = renderHostedSnapshotImage(
          of: UIHostingController(rootView: view()),
          on: config.device,
          style: uiStyle,
          wait: wait
        )
        let failure = verifySnapshot(
          of: image,
          as: .image(precision: precision, perceptualPrecision: perceptualPrecision),
          named: name,
          record: recording,
          snapshotDirectory: HostedSnapshotContext.snapshotDirectory,
          timeout: timeout,
          fileID: fileID,
          file: filePath,
          testName: "\(HostedSnapshotContext.testName ?? testName)-\(config.name)\(suffix)",
          line: line,
          column: column
        )
        guard let failure else { continue }
        XCTFail(failure, file: filePath, line: line)
      }
    }
  }

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
  ) {
    let image = renderHostedSnapshotImage(
      of: UIHostingController(rootView: view()),
      on: config,
      style: style,
      wait: wait
    )
    let failure = verifySnapshot(
      of: image,
      as: .image(precision: precision, perceptualPrecision: perceptualPrecision),
      named: name,
      record: recording,
      snapshotDirectory: HostedSnapshotContext.snapshotDirectory,
      timeout: timeout,
      fileID: fileID,
      file: filePath,
      testName: HostedSnapshotContext.testName ?? testName,
      line: line,
      column: column
    )
    guard let failure else { return }
    XCTFail(failure, file: filePath, line: line)
  }

  @MainActor
  public func withHostedSnapshotContext<Result>(
    snapshotDirectory: String,
    testName: String,
    operation: () throws -> Result
  ) rethrows -> Result {
    let previousSnapshotDirectory = HostedSnapshotContext.snapshotDirectory
    let previousTestName = HostedSnapshotContext.testName

    HostedSnapshotContext.snapshotDirectory = snapshotDirectory
    HostedSnapshotContext.testName = testName

    defer {
      HostedSnapshotContext.snapshotDirectory = previousSnapshotDirectory
      HostedSnapshotContext.testName = previousTestName
    }

    return try operation()
  }

  @MainActor
  private func renderHostedSnapshotImage(
    of viewController: UIViewController,
    on config: ViewImageConfig,
    style: UIUserInterfaceStyle = .light,
    wait: TimeInterval
  ) -> UIImage {
    guard
      let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first
    else {
      preconditionFailure("Hosted snapshots require a UIWindowScene.")
    }

    let originalKeyWindow = windowScene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: windowScene)
    let sceneBounds = windowScene.coordinateSpace.bounds
    let windowSize = config.size ?? sceneBounds.size
    window.frame = CGRect(origin: .zero, size: windowSize)
    window.overrideUserInterfaceStyle = style
    window.rootViewController = viewController

    viewController.view.backgroundColor = .clear
    viewController.loadViewIfNeeded()
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    viewController.view.frame = window.bounds
    viewController.view.setNeedsLayout()
    viewController.view.layoutIfNeeded()

    if wait > 0 {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: wait))
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    let image = renderer.image { rendererContext in
      if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
        window.layer.render(in: rendererContext.cgContext)
      }
    }

    window.rootViewController?.dismiss(animated: false)
    window.isHidden = true
    window.rootViewController = nil
    originalKeyWindow?.makeKeyAndVisible()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

    return image
  }
#endif
