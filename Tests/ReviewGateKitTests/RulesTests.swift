import XCTest
@testable import ReviewGateKit

final class DiffBudgetRuleTests: XCTestCase {

    private func changeSet(lines: Int, files: Int = 1) -> ChangeSet {
        precondition(files > 0)
        let perFile = lines / files
        let remainder = lines % files
        let fileChanges = (0..<files).map { index in
            FileChange(
                path: "Sources/App/File\(index).swift",
                additions: perFile + (index == 0 ? remainder : 0),
                deletions: 0
            )
        }
        return ChangeSet(files: fileChanges)
    }

    func testWithinBudgetIsInfo() {
        let findings = DiffBudgetRule().evaluate(changeSet(lines: 100))
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.severity, .info)
    }

    func testCautionBandAboveThreeQuartersOfBudget() {
        let findings = DiffBudgetRule().evaluate(changeSet(lines: 350))
        XCTAssertEqual(findings.first?.severity, .caution)
    }

    func testExactlyAtBudgetIsCautionNotEscalation() {
        let findings = DiffBudgetRule().evaluate(changeSet(lines: 400))
        XCTAssertEqual(findings.first?.severity, .caution, "The budget is inclusive; 400/400 is legal but hot")
    }

    func testOneLineOverBudgetEscalates() {
        let findings = DiffBudgetRule().evaluate(changeSet(lines: 401))
        XCTAssertEqual(findings.first?.severity, .escalate)
    }

    func testTooManyFilesEscalatesEvenWhenLinesAreSmall() {
        let findings = DiffBudgetRule().evaluate(changeSet(lines: 21, files: 21))
        XCTAssertEqual(findings.first?.severity, .escalate)
    }
}

final class CriticalPathRuleTests: XCTestCase {

    private let rule = CriticalPathRule(criticalPrefixes: ["Sources/Payments", "Sources/Auth"])

    func testCriticalPathHitEscalates() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/Payments/Refunds.swift", additions: 2, deletions: 1)
        ])
        let findings = rule.evaluate(changeSet)
        XCTAssertEqual(findings.first?.severity, .escalate)
        XCTAssertTrue(findings.first?.message.contains("Sources/Payments/Refunds.swift") ?? false)
    }

    func testTestFilesUnderCriticalPathAreExempt() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/Payments/Tests/RefundsTests.swift", additions: 20, deletions: 0)
        ])
        let findings = rule.evaluate(changeSet)
        XCTAssertEqual(findings.first?.severity, .info, "Strengthening tests around a critical path must not escalate")
    }

    func testNonCriticalChangeIsInfo() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/Feed/FeedView.swift", additions: 5, deletions: 5)
        ])
        XCTAssertEqual(rule.evaluate(changeSet).first?.severity, .info)
    }

    func testEmptyPrefixListProducesNoFindings() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/Payments/Refunds.swift", additions: 1, deletions: 0)
        ])
        XCTAssertTrue(CriticalPathRule(criticalPrefixes: []).evaluate(changeSet).isEmpty)
    }
}

final class TestPresenceRuleTests: XCTestCase {

    private let rule = TestPresenceRule()

    func testProductionWithoutTestsCautions() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/Feature.swift", additions: 30, deletions: 5)
        ])
        XCTAssertEqual(rule.evaluate(changeSet).first?.severity, .caution)
    }

    func testLargeProductionChangeWithoutTestsEscalates() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/BigFeature.swift", additions: 200, deletions: 0)
        ])
        XCTAssertEqual(rule.evaluate(changeSet).first?.severity, .escalate)
    }

    func testExactlyAtEscalationThresholdStaysCaution() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/Feature.swift", additions: 150, deletions: 0)
        ])
        XCTAssertEqual(rule.evaluate(changeSet).first?.severity, .caution)
    }

    func testTestOnlyChangeIsInfo() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Tests/AppTests/FeatureTests.swift", additions: 40, deletions: 2)
        ])
        XCTAssertEqual(rule.evaluate(changeSet).first?.severity, .info)
    }

    func testCodeWithTestsIsInfo() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/Feature.swift", additions: 30, deletions: 5),
            FileChange(path: "Tests/AppTests/FeatureTests.swift", additions: 25, deletions: 0)
        ])
        XCTAssertEqual(rule.evaluate(changeSet).first?.severity, .info)
    }
}

final class ChurnConcentrationRuleTests: XCTestCase {

    private let rule = ChurnConcentrationRule()

    func testConcentratedChurnCautions() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/Rewrite.swift", additions: 90, deletions: 0),
            FileChange(path: "Sources/App/Small.swift", additions: 10, deletions: 0)
        ])
        let findings = rule.evaluate(changeSet)
        XCTAssertEqual(findings.first?.severity, .caution)
    }

    func testBelowMinimumLinesStaysSilent() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/Rewrite.swift", additions: 45, deletions: 0),
            FileChange(path: "Sources/App/Small.swift", additions: 5, deletions: 0)
        ])
        XCTAssertTrue(rule.evaluate(changeSet).isEmpty, "Concentration only matters once the change is big enough to hide in")
    }

    func testBalancedChurnStaysSilent() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/A.swift", additions: 50, deletions: 0),
            FileChange(path: "Sources/App/B.swift", additions: 50, deletions: 0)
        ])
        XCTAssertTrue(rule.evaluate(changeSet).isEmpty)
    }
}
