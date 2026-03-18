import Foundation
import SwiftParser
import SwiftSyntax

private struct GenerationUnit {
  let packageRoot: URL
  let output: URL
  let suiteName: String
}

private struct TaggedHostedTest: Hashable {
  let filePath: String
  let imports: [String]
  let sourceFileName: String
  let sourceTypeName: String?
  let functionName: String
  let body: String
  let isThrowing: Bool
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

private final class ThrowingBodyCollector: SyntaxVisitor {
  private(set) var isThrowing = false

  override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
    self.isThrowing = true
    return .skipChildren
  }

  override func visit(_ node: ThrowStmtSyntax) -> SyntaxVisitorContinueKind {
    self.isThrowing = true
    return .skipChildren
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

    let throwingCollector = ThrowingBodyCollector(viewMode: .sourceAccurate)
    throwingCollector.walk(body)

    self.hostedTests.append(
      TaggedHostedTest(
        filePath: self.filePath,
        imports: self.imports,
        sourceFileName: self.sourceFileName,
        sourceTypeName: self.typeNameStack.last,
        functionName: node.name.text,
        body: normalizeIndentation(
          body.statements.description.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        isThrowing: throwingCollector.isThrowing
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

private func parseArguments() throws -> [GenerationUnit] {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard !arguments.isEmpty else {
    throw GeneratorError.usage(
      "Usage: HostedSnapshotRegistryGenerator (--package <path>)+ --output-dir <path>"
    )
  }

  var packageRoots: [String] = []
  var outputDirectory: String?
  var index = 0

  while index < arguments.count {
    let flag = arguments[index]
    guard index + 1 < arguments.count else {
      throw GeneratorError.usage("Missing value for argument: \(flag)")
    }
    let value = arguments[index + 1]

    switch flag {
    case "--package":
      packageRoots.append(value)
    case "--output-dir":
      if outputDirectory != nil {
        throw GeneratorError.usage("The --output-dir argument may only be provided once.")
      }
      outputDirectory = value
    default:
      throw GeneratorError.usage("Unknown argument: \(flag)")
    }

    index += 2
  }

  guard !packageRoots.isEmpty else {
    throw GeneratorError.usage("At least one --package argument is required.")
  }
  guard let outputDirectory else {
    throw GeneratorError.usage("The --output-dir argument is required.")
  }

  let outputDirectoryURL = URL(fileURLWithPath: outputDirectory)
  return packageRoots.map { packageRoot in
    let packageName = URL(fileURLWithPath: packageRoot)
      .lastPathComponent
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let safePackageName = sanitizeIdentifier(packageName)
    let suiteName = "\(safePackageName)HostedSnapshotTests"
    let outputFileName = "\(suiteName).generated.swift"
    return GenerationUnit(
      packageRoot: URL(fileURLWithPath: packageRoot),
      output: outputDirectoryURL.appending(path: outputFileName),
      suiteName: suiteName
    )
  }
}

private func collectTaggedHostedTests(in packageRoot: URL) throws -> [TaggedHostedTest] {
  let fileManager = FileManager.default
  guard let enumerator = fileManager.enumerator(
    at: packageRoot,
    includingPropertiesForKeys: [.isDirectoryKey],
    options: [.skipsHiddenFiles, .skipsPackageDescendants]
  ) else {
    return []
  }

  var hostedTests: [TaggedHostedTest] = []
  var errors: [String] = []

  for case let fileURL as URL in enumerator {
    if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
      values.isDirectory == true
    {
      switch fileURL.lastPathComponent {
      case ".build", ".git", ".swiftpm":
        enumerator.skipDescendants()
      default:
        break
      }
      continue
    }

    guard fileURL.pathExtension == "swift" else {
      continue
    }
    guard fileURL.pathComponents.contains("Tests") else {
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
  guard !identifier.isEmpty else {
    return "hostedSnapshot"
  }
  if let firstCharacter = identifier.first, firstCharacter.isNumber {
    return "_\(identifier)"
  }
  return identifier
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

private func renderTests(hostedTests: [TaggedHostedTest], suiteName: String) -> String {
  let imports = Set(hostedTests.flatMap(\.imports))
    .union(["import Testing"])
    .sorted()
    .joined(separator: "\n")

  let testMethods = hostedTests.map { hostedTest in
    let typeName = hostedTest.sourceTypeName ?? hostedTest.sourceFileName
    let generatedName = sanitizeIdentifier(
      "test_\(typeName)_\(hostedTest.functionName)"
    )
    let originalSnapshotDirectory = stringLiteral(snapshotDirectory(for: hostedTest))
    let originalTestName = stringLiteral(hostedTest.functionName)
    let tryPrefix = hostedTest.isThrowing ? "try " : ""
    let throwsClause = hostedTest.isThrowing ? " throws" : ""
    let wrappedBody = """
      \(tryPrefix)withHostedSnapshotContext(
        snapshotDirectory: \(originalSnapshotDirectory),
        testName: \(originalTestName)
      ) {
      \(indent(hostedTest.body, spaces: 2))
      }
    """

    return """
      @Test
      @MainActor
      func \(generatedName)()\(throwsClause) {
    \(indent(wrappedBody, spaces: 4))
      }
    """
  }
  .joined(separator: "\n\n")

  return """
  // This file is generated by HostedSnapshotRegistryGenerator.

  \(imports)

  @Suite
  struct \(suiteName) {
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
  for generationUnit in try parseArguments() {
    let hostedTests = try collectTaggedHostedTests(in: generationUnit.packageRoot)
    let output = renderTests(hostedTests: hostedTests, suiteName: generationUnit.suiteName)
    try writeOutput(output, to: generationUnit.output)
  }
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
