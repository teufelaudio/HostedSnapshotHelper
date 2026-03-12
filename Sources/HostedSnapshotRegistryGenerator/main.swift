import Foundation
import SwiftParser
import SwiftSyntax

private struct TaggedHostedTest: Hashable {
  let filePath: String
  let imports: [String]
  let sourceFileName: String
  let sourceTypeName: String?
  let functionName: String
  let body: String
}

private enum GeneratorError: Error, CustomStringConvertible {
  case usage(String)
  case validation([String])

  var description: String {
    switch self {
    case let .usage(message):
      return message
    case let .validation(errors):
      return errors.joined(separator: "\n")
    }
  }
}

private final class HostedSnapshotCallCollector: SyntaxVisitor {
  private(set) var callCount = 0

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    if node.calledExpression.trimmedDescription == "assertHostedSnapshot" {
      self.callCount += 1
      return .skipChildren
    }
    return .visitChildren
  }
}

private final class TaggedHostedTestCollector: SyntaxVisitor {
  private let filePath: String
  private let sourceFileName: String
  private(set) var hostedTests: [TaggedHostedTest] = []
  private(set) var errors: [String] = []
  private(set) var imports: [String] = []
  private var typeNameStack: [String] = []

  init(filePath: String) {
    self.filePath = filePath
    self.sourceFileName = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    let path = node.path.trimmedDescription
    if ["Testing", "SnapshotTesting"].contains(path) {
      return .skipChildren
    }
    self.imports.append(node.trimmedDescription)
    return .skipChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    self.typeNameStack.append(node.name.text)
    return .visitChildren
  }

  override func visitPost(_ node: StructDeclSyntax) {
    _ = self.typeNameStack.popLast()
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    self.typeNameStack.append(node.name.text)
    return .visitChildren
  }

  override func visitPost(_ node: ClassDeclSyntax) {
    _ = self.typeNameStack.popLast()
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    self.typeNameStack.append(node.name.text)
    return .visitChildren
  }

  override func visitPost(_ node: EnumDeclSyntax) {
    _ = self.typeNameStack.popLast()
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    guard self.isTaggedHostedSnapshotTest(node) else {
      return .skipChildren
    }

    guard let body = node.body else {
      self.errors.append("\(self.filePath): tagged test '\(node.name.text)' is missing a body.")
      return .skipChildren
    }

    let callCollector = HostedSnapshotCallCollector(viewMode: .sourceAccurate)
    callCollector.walk(body)

    guard callCollector.callCount == 1 else {
      self.errors.append(
        "\(self.filePath): tagged test '\(node.name.text)' must contain exactly one assertHostedSnapshot(...) call."
      )
      return .skipChildren
    }

    self.hostedTests.append(
      TaggedHostedTest(
        filePath: self.filePath,
        imports: self.imports,
        sourceFileName: self.sourceFileName,
        sourceTypeName: self.typeNameStack.last,
        functionName: node.name.text,
        body: normalizeIndentation(
          body.statements.description.trimmingCharacters(in: .whitespacesAndNewlines)
        )
      )
    )

    return .skipChildren
  }

  private func isTaggedHostedSnapshotTest(_ node: FunctionDeclSyntax) -> Bool {
    node.attributes.contains { element in
      guard let attribute = element.as(AttributeSyntax.self) else {
        return false
      }
      return attribute.attributeName.trimmedDescription == "Test"
        && attribute.trimmedDescription.contains(".requiresKeyWindow")
    }
  }
}

private func parseArguments() throws -> (packageRoot: URL, output: URL) {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard arguments.count == 4 else {
    throw GeneratorError.usage(
      "Usage: HostedSnapshotRegistryGenerator --package-root <path> --output <path>"
    )
  }

  var packageRoot: String?
  var output: String?
  var index = 0

  while index < arguments.count {
    let flag = arguments[index]
    let value = arguments[index + 1]
    switch flag {
    case "--package-root":
      packageRoot = value
    case "--output":
      output = value
    default:
      throw GeneratorError.usage("Unknown argument: \(flag)")
    }
    index += 2
  }

  guard let packageRoot, let output else {
    throw GeneratorError.usage("Both --package-root and --output are required.")
  }

  return (
    packageRoot: URL(fileURLWithPath: packageRoot),
    output: URL(fileURLWithPath: output)
  )
}

private func collectTaggedHostedTests(in packageRoot: URL) throws -> [TaggedHostedTest] {
  let testsRoot = packageRoot.appending(path: "Tests")
  let fileManager = FileManager.default
  guard let enumerator = fileManager.enumerator(
    at: testsRoot,
    includingPropertiesForKeys: nil
  ) else {
    return []
  }

  var hostedTests: [TaggedHostedTest] = []
  var errors: [String] = []

  for case let fileURL as URL in enumerator {
    guard fileURL.pathExtension == "swift" else {
      continue
    }

    let source = try String(contentsOf: fileURL, encoding: .utf8)
    let collector = TaggedHostedTestCollector(filePath: fileURL.path)
    collector.walk(Parser.parse(source: source))
    hostedTests.append(contentsOf: collector.hostedTests)
    errors.append(contentsOf: collector.errors)
  }

  let duplicateTests = Dictionary(grouping: hostedTests) {
    "\($0.sourceFileName)::\($0.sourceTypeName ?? "_")::\($0.functionName)"
  }
  .filter { $0.value.count > 1 }
  .keys
  .sorted()

  if !duplicateTests.isEmpty {
    errors.append(
      duplicateTests
        .map { "Duplicate hosted snapshot test found: \($0)" }
        .joined(separator: "\n")
    )
  }

  if !errors.isEmpty {
    throw GeneratorError.validation(errors)
  }

  return hostedTests.sorted {
    ($0.sourceFileName, $0.sourceTypeName ?? "", $0.functionName, $0.filePath)
      < ($1.sourceFileName, $1.sourceTypeName ?? "", $1.functionName, $1.filePath)
  }
}

private func sanitizeIdentifier(_ rawValue: String) -> String {
  let sanitized = rawValue.map { character -> Character in
    switch character {
    case "a"..."z", "A"..."Z", "0"..."9":
      return character
    default:
      return "_"
    }
  }

  let identifier = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
  return identifier.isEmpty ? "hostedSnapshot" : identifier
}

private func indent(_ text: String, spaces: Int) -> String {
  let prefix = String(repeating: " ", count: spaces)
  return text
    .split(separator: "\n", omittingEmptySubsequences: false)
    .map { line in
      line.isEmpty ? "" : "\(prefix)\(line)"
    }
    .joined(separator: "\n")
}

private func normalizeIndentation(_ text: String) -> String {
  let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
  let contentLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  let minimumIndent = contentLines
    .map { line in
      line.prefix { $0 == " " || $0 == "\t" }.count
    }
    .min() ?? 0

  return lines
    .map { line in
      guard !line.isEmpty else {
        return ""
      }
      return String(line.dropFirst(minimumIndent))
    }
    .joined(separator: "\n")
}

private func stringLiteral(_ rawValue: String) -> String {
  var literal = "\""
  for character in rawValue {
    switch character {
    case "\\":
      literal += "\\\\"
    case "\"":
      literal += "\\\""
    case "\n":
      literal += "\\n"
    case "\r":
      literal += "\\r"
    case "\t":
      literal += "\\t"
    default:
      literal.append(character)
    }
  }
  literal += "\""
  return literal
}

private func snapshotDirectory(for hostedTest: TaggedHostedTest) -> String {
  let fileURL = URL(fileURLWithPath: hostedTest.filePath)
  return fileURL.deletingLastPathComponent()
    .appending(path: "__Snapshots__")
    .appending(path: hostedTest.sourceFileName)
    .path
}

private func renderTests(hostedTests: [TaggedHostedTest]) -> String {
  let imports = Set(hostedTests.flatMap(\.imports))
    .union(["import XCTest"])
    .sorted()
    .joined(separator: "\n")

  let testMethods = hostedTests.map { hostedTest in
    let typeName = hostedTest.sourceTypeName ?? hostedTest.sourceFileName
    let generatedName = sanitizeIdentifier(
      "test_\(typeName)_\(hostedTest.functionName)"
    )
    let originalSnapshotDirectory = stringLiteral(snapshotDirectory(for: hostedTest))
    let originalTestName = stringLiteral(hostedTest.functionName)
    let wrappedBody = """
      withHostedSnapshotContext(
        snapshotDirectory: \(originalSnapshotDirectory),
        testName: \(originalTestName)
      ) {
      \(indent(hostedTest.body, spaces: 2))
      }
    """

    return """
      @MainActor
      func \(generatedName)() {
    \(indent(wrappedBody, spaces: 4))
      }
    """
  }
  .joined(separator: "\n\n")

  return """
  // This file is generated by HostedSnapshotRegistryGenerator.

  \(imports)

  final class GeneratedHostedSnapshotTests: XCTestCase {
  \(indent(testMethods, spaces: 2))
  }
  """
}

private func writeOutput(_ content: String, to outputURL: URL) throws {
  let fileManager = FileManager.default
  try fileManager.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  if let current = try? String(contentsOf: outputURL, encoding: .utf8), current == content {
    return
  }

  let temporaryURL = outputURL.deletingLastPathComponent()
    .appending(path: "\(outputURL.lastPathComponent).tmp")

  try content.write(to: temporaryURL, atomically: true, encoding: .utf8)

  if fileManager.fileExists(atPath: outputURL.path) {
    try fileManager.removeItem(at: outputURL)
  }

  try fileManager.moveItem(at: temporaryURL, to: outputURL)
}

do {
  let arguments = try parseArguments()
  let hostedTests = try collectTaggedHostedTests(in: arguments.packageRoot)
  let output = renderTests(hostedTests: hostedTests)
  try writeOutput(output, to: arguments.output)
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
