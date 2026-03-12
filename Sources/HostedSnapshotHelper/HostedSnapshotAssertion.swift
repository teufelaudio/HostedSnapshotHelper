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

  @MainActor
  public func assertHostedSnapshot<Content: View>(
    of view: @autoclosure () -> Content,
    on config: ViewImageConfig = .iPhone13Pro,
    named name: String? = nil,
    wait: TimeInterval = 1,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
  ) {
    let image = renderHostedSnapshotImage(
      of: UIHostingController(rootView: view()),
      on: config,
      wait: wait
    )
    let failure = verifySnapshot(
      of: image,
      as: .image,
      named: name,
      snapshotDirectory: HostedSnapshotContext.snapshotDirectory,
      file: file,
      testName: HostedSnapshotContext.testName ?? testName,
      line: line
    )
    guard let failure else { return }
    XCTFail(failure, file: file, line: line)
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
    wait: TimeInterval
  ) -> UIImage {
    _ = config

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
    window.frame = sceneBounds
    window.overrideUserInterfaceStyle = .light
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
