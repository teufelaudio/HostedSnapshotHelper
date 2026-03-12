import Foundation
import Testing

extension Tag {
  @Tag public static var requiresKeyWindow: Self
}

extension Trait where Self == ConditionTrait {
  public static var requiresKeyWindow: Self {
    requiresKeyWindow("Hosted snapshots run in the app-hosted test suite.")
  }

  public static func requiresKeyWindow(
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) -> Self {
    .disabled(
      if: ProcessInfo.processInfo.environment["RUN_HOSTED_PACKAGE_TESTS"] != "1",
      comment ?? "Hosted snapshots run in the app-hosted test suite.",
      sourceLocation: sourceLocation
    )
  }
}
