import XCTest
@testable import ReviewGateKit

final class VerificationPipelineTests: XCTestCase {

    private let pipeline = VerificationPipeline.standard()

    func testEmptyChangeSetShortCircuitsWithExplicitFinding() {
        let verdict = pipeline.evaluate(ChangeSet(files: []))
        XCTAssertEqual(verdict.routing, .agentReviewSufficient)
        XCTAssertEqual(verdict.riskLevel, .low)
        XCTAssertEqual(verdict.findings.count, 1)
        XCTAssertEqual(verdict.findings.first?.ruleIdentifier, "pipeline")
    }

    func testSmallRefactorWithTestsRoutesToAgentReview() {
        let verdict = pipeline.evaluate(diffText: SampleDiffs.smallRefactorWithTests)
        XCTAssertEqual(verdict.riskLevel, .low)
        XCTAssertEqual(verdict.routing, .agentReviewSufficient)
    }

    func testFeatureWithoutTestsRoutesToSingleHumanReview() {
        let verdict = pipeline.evaluate(diffText: SampleDiffs.featureWithoutTests)
        XCTAssertEqual(verdict.riskLevel, .moderate)
        XCTAssertEqual(verdict.routing, .singleHumanReview)
    }

    func testPaymentsHotfixRoutesToPairReviewDespiteTinySize() {
        let verdict = pipeline.evaluate(diffText: SampleDiffs.paymentsHotfix)
        XCTAssertEqual(verdict.riskLevel, .high)
        XCTAssertEqual(verdict.routing, .pairHumanReview)
        let escalations = verdict.findings.filter { $0.severity == .escalate }
        XCTAssertEqual(escalations.count, 1)
        XCTAssertEqual(escalations.first?.ruleIdentifier, "critical-path")
    }

    func testWorstSeverityWinsOverManyCleanFindings() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/Auth/TokenStore.swift", additions: 1, deletions: 1),
            FileChange(path: "Tests/AuthTests/TokenStoreTests.swift", additions: 12, deletions: 0)
        ])
        let verdict = pipeline.evaluate(changeSet)
        XCTAssertEqual(verdict.riskLevel, .high, "One escalation must dominate any number of clean findings")
        XCTAssertEqual(verdict.routing, .pairHumanReview)
    }

    func testFindingsPreserveRuleOrder() {
        let verdict = pipeline.evaluate(diffText: SampleDiffs.featureWithoutTests)
        let identifiers = verdict.findings.map(\.ruleIdentifier)
        XCTAssertEqual(identifiers.first, "diff-budget")
        guard identifiers.count >= 3 else {
            XCTFail("Expected at least three findings, got \(identifiers)")
            return
        }
        XCTAssertEqual(identifiers[1], "critical-path")
        XCTAssertEqual(identifiers[2], "test-presence")
    }

    func testRepeatedEvaluationIsDeterministic() {
        let first = pipeline.evaluate(diffText: SampleDiffs.featureWithoutTests)
        let second = pipeline.evaluate(diffText: SampleDiffs.featureWithoutTests)
        XCTAssertEqual(first, second)
    }

    func testEveryVerdictCarriesAnAuditTrail() {
        for diff in [SampleDiffs.smallRefactorWithTests, SampleDiffs.featureWithoutTests, SampleDiffs.paymentsHotfix] {
            let verdict = pipeline.evaluate(diffText: diff)
            XCTAssertFalse(verdict.findings.isEmpty, "A verdict with no findings is an unexplained verdict")
        }
    }

    func testCustomBudgetTightensRouting() {
        let strict = VerificationPipeline(rules: [DiffBudgetRule(maxLines: 5, maxFiles: 5)])
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/File.swift", additions: 6, deletions: 0)
        ])
        let verdict = strict.evaluate(changeSet)
        XCTAssertEqual(verdict.routing, .pairHumanReview)
    }
}
