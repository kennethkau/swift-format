//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftFormat
import XCTest

final class ConfigurationCodingTests: XCTestCase {
  func testNonPositiveLineLengthAndTabWidthAreRejected() {
    // Non-positive geometry must fail at the configuration boundary, not trap inside the pretty
    // printer.
    let invalid: [(key: String, value: Int)] = [
      ("lineLength", -5), ("lineLength", 0), ("tabWidth", -1), ("tabWidth", 0),
    ]
    for (key, value) in invalid {
      let json = #"{"\#(key)": \#(value)}"#
      XCTAssertThrowsError(
        try Configuration(data: Data(json.utf8)),
        "\(key) = \(value) must be rejected"
      ) { error in
        guard case DecodingError.dataCorrupted = error else {
          return XCTFail("expected dataCorrupted for \(key) = \(value), got \(error)")
        }
      }
    }
    XCTAssertNoThrow(try Configuration(data: Data(#"{"lineLength": 1, "tabWidth": 1}"#.utf8)))
  }

  func testDefaultConfigurationEncodeDecodeIsAFixedPoint() throws {
    // `dump-configuration` and the API encode/decode round trip must not lose information: for
    // the default configuration, encoding and re-decoding must yield an equal configuration.
    let original = Configuration()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Configuration.self, from: data)
    XCTAssertEqual(decoded, original)
  }

  func testFullyNonDefaultConfigurationEncodeDecodeIsAFixedPoint() throws {
    // A configuration in which every option differs from its default catches any key dropped
    // from `encode(to:)` without a hand-maintained key list: the re-decoded value would fall
    // back to the default for the missing key and fail the comparison.
    let original = makeFullyNonDefaultConfiguration()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Configuration.self, from: data)
    XCTAssertEqual(decoded, original)
  }

  /// A configuration in which every top-level option, nested option, and rule enablement
  /// differs from its default.
  private func makeFullyNonDefaultConfiguration() -> Configuration {
    var configuration = Configuration()

    configuration.maximumBlankLines = 2
    configuration.lineLength = 120
    configuration.spacesBeforeEndOfLineComments = 1
    configuration.tabWidth = 4
    configuration.indentation = .tabs(4)
    configuration.respectsExistingLineBreaks = false
    configuration.lineBreakBeforeControlFlowKeywords = true
    configuration.lineBreakBeforeEachArgument = true
    configuration.lineBreakBeforeEachGenericRequirement = true
    configuration.lineBreakBetweenDeclarationAttributes = true
    configuration.lineBreakBeforeEachChainComponent = true
    configuration.attachLoneDeclarationAttributes = true
    configuration.prioritizeKeepingFunctionOutputTogether = true
    configuration.indentConditionalCompilationBlocks = false
    configuration.lineBreakAroundMultilineExpressionChainComponents = true
    configuration.fileScopedDeclarationPrivacy.accessLevel = .fileprivate
    configuration.indentSwitchCaseLabels = true
    configuration.spacesAroundRangeFormationOperators = true
    configuration.noAssignmentInExpressions.allowedFunctions = ["customAllowedFunction"]
    configuration.multilineTrailingCommaBehavior = .alwaysUsed
    configuration.multiElementCollectionTrailingCommas = false
    configuration.collectionElementLayout = .onePerLine
    configuration.magicTrailingComma = true
    configuration.forceBrokenArgumentsInMultilineArrayLiterals = true
    configuration.forceBrokenClosureBodies = true
    configuration.forceBrokenCodeBlockBodies = true
    configuration.reflowMultilineStringLiterals = .onlyLinesOverLength
    configuration.indentBlankLines = true
    configuration.orderedImports.includeConditionalImports = true
    configuration.orderedImports.shouldGroupImports = false
    configuration.swiftTestingNamingConventions.forbidSuiteWithoutParameters = true
    configuration.swiftTestingNamingConventions.forbidSuiteDescription = true
    configuration.swiftTestingNamingConventions.forbidTestDescription = true
    configuration.swiftTestingNamingConventions.requireRawIdentifierTestNames = true
    configuration.blankLinePolicy.betweenDeclarations = .exactlyOne
    configuration.blankLinePolicy.scopeEdges = .none
    configuration.blankLinePolicy.members = .none
    configuration.blankLinePolicy.marks = MarkBlankLinePolicy(before: .none, after: .exactlyOne)
    configuration.blankLinePolicy.switchCases = .none
    configuration.blankLinePolicy.afterCaseLabel = .optional
    configuration.blankLinePolicy.attributes = .optional
    configuration.blankLinePolicy.expressions = .optional
    configuration.blankLinePolicy.conditionalCompilationEdges = .optional
    configuration.blankLinePolicy.guardPrologue = .optional
    configuration.blankLinePolicy.beforeElse = .optional
    configuration.blankLinePolicy.statements = .none
    configuration.iterateToFixpoint = true

    configuration.rules["DoNotUseSemicolons"] = false
    configuration.rules["NeverForceUnwrap"] = true
    configuration.rules["RedundantSelf"] = true

    return configuration
  }
}
