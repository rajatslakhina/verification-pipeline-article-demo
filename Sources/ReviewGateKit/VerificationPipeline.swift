import Foundation

/// Aggregate risk of a change set, derived from the worst finding severity.
public enum RiskLevel: Int, Sendable, Comparable, CaseIterable {
    case low = 0
    case moderate = 1
    case high = 2

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Where a change goes next. This is the pipeline's whole point:
/// review capacity is finite, so it gets *allocated by policy* —
/// cheap verification for low-risk changes, expensive human attention
/// reserved for the changes that can actually hurt.
public enum ReviewRouting: Sendable, Equatable {
    /// Automated checks plus an agent review pass are sufficient.
    case agentReviewSufficient
    /// One human reviewer, agent pre-review recommended.
    case singleHumanReview
    /// Two human reviewers; agent output is input, never sign-off.
    case pairHumanReview
}

/// The pipeline's verdict for one change set: a routing decision, an
/// aggregate risk level, and the complete ordered audit trail of findings
/// that produced them. Nothing in the verdict is unexplained.
public struct ReviewVerdict: Sendable, Equatable {
    public let routing: ReviewRouting
    public let riskLevel: RiskLevel
    public let findings: [RuleFinding]

    public init(routing: ReviewRouting, riskLevel: RiskLevel, findings: [RuleFinding]) {
        self.routing = routing
        self.riskLevel = riskLevel
        self.findings = findings
    }
}

/// Runs a fixed, ordered list of ``ReviewRule``s over a change set and maps
/// the worst severity to a routing decision.
///
/// Design choices, stated so they can be disagreed with:
/// - **Rules are ordered and findings preserve that order.** The audit trail
///   reads the same way every time; CI output and agent-review context stay
///   diff-stable.
/// - **Worst severity wins.** A single `escalate` routes to pair review no
///   matter how clean everything else is. Averaging severities was rejected:
///   a payments change doesn't get cheaper review because the README diff
///   next to it was tidy.
/// - **Empty change sets short-circuit** to agent-sufficient with an explicit
///   info finding — the verdict still explains itself.
public struct VerificationPipeline: Sendable {
    public let rules: [any ReviewRule]

    public init(rules: [any ReviewRule]) {
        self.rules = rules
    }

    /// The default gate stack: budget → critical paths → tests → churn shape.
    public static func standard(
        criticalPrefixes: [String] = ["Sources/Payments", "Sources/Auth"],
        maxLines: Int = 400,
        maxFiles: Int = 20
    ) -> VerificationPipeline {
        VerificationPipeline(rules: [
            DiffBudgetRule(maxLines: maxLines, maxFiles: maxFiles),
            CriticalPathRule(criticalPrefixes: criticalPrefixes),
            TestPresenceRule(),
            ChurnConcentrationRule()
        ])
    }

    public func evaluate(_ changeSet: ChangeSet) -> ReviewVerdict {
        guard !changeSet.isEmpty else {
            return ReviewVerdict(
                routing: .agentReviewSufficient,
                riskLevel: .low,
                findings: [RuleFinding(
                    ruleIdentifier: "pipeline",
                    severity: .info,
                    message: "Empty change set — nothing to verify."
                )]
            )
        }

        var findings: [RuleFinding] = []
        for rule in rules {
            findings.append(contentsOf: rule.evaluate(changeSet))
        }

        let worst = findings.map(\.severity).max() ?? .info
        let risk: RiskLevel
        let routing: ReviewRouting
        switch worst {
        case .escalate:
            risk = .high
            routing = .pairHumanReview
        case .caution:
            risk = .moderate
            routing = .singleHumanReview
        case .info:
            risk = .low
            routing = .agentReviewSufficient
        }

        return ReviewVerdict(routing: routing, riskLevel: risk, findings: findings)
    }

    /// Convenience: parse raw unified-diff text and evaluate it in one call.
    public func evaluate(diffText: String) -> ReviewVerdict {
        evaluate(DiffParser.parse(diffText))
    }
}
