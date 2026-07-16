import Foundation

/// Severity of a single rule finding.
///
/// `escalate` is the only severity that forces two human reviewers; a rule
/// should reserve it for findings where an unnoticed defect is expensive
/// (critical paths, blown budgets), not merely inconvenient.
public enum Severity: Int, Sendable, Comparable, CaseIterable {
    case info = 0
    case caution = 1
    case escalate = 2

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One rule's judgment about a change set, with a human-readable reason.
/// Findings are the audit trail: every routing verdict can be traced back
/// to the exact rule and message that produced it.
public struct RuleFinding: Sendable, Equatable {
    public let ruleIdentifier: String
    public let severity: Severity
    public let message: String

    public init(ruleIdentifier: String, severity: Severity, message: String) {
        self.ruleIdentifier = ruleIdentifier
        self.severity = severity
        self.message = message
    }
}

/// A verification rule. Rules are pure functions over a ``ChangeSet``:
/// no I/O, no shared state, so the pipeline's output is deterministic
/// for a given diff — a property the tests pin down explicitly.
public protocol ReviewRule: Sendable {
    var identifier: String { get }
    func evaluate(_ changeSet: ChangeSet) -> [RuleFinding]
}

// MARK: - Diff budget

/// Enforces a size budget on the change set. The premise: review quality
/// degrades sharply past a few hundred lines, so oversized diffs are a
/// verification problem even when every individual line is fine.
public struct DiffBudgetRule: ReviewRule {
    public let identifier = "diff-budget"
    public let maxLines: Int
    public let maxFiles: Int

    public init(maxLines: Int = 400, maxFiles: Int = 20) {
        self.maxLines = max(1, maxLines)
        self.maxFiles = max(1, maxFiles)
    }

    public func evaluate(_ changeSet: ChangeSet) -> [RuleFinding] {
        let lines = changeSet.totalLinesChanged
        let fileCount = changeSet.filesTouched

        if lines > maxLines || fileCount > maxFiles {
            return [RuleFinding(
                ruleIdentifier: identifier,
                severity: .escalate,
                message: "Change exceeds review budget: \(lines)/\(maxLines) lines, \(fileCount)/\(maxFiles) files. Split it before asking anyone to verify it."
            )]
        }

        // Warn inside the top quarter of the budget: the diff is legal but
        // approaching the size where review attention measurably decays.
        let cautionFloor = (maxLines * 3) / 4
        if lines > cautionFloor {
            return [RuleFinding(
                ruleIdentifier: identifier,
                severity: .caution,
                message: "Change is at \(lines) of a \(maxLines)-line budget — close to the ceiling where review quality drops."
            )]
        }

        return [RuleFinding(
            ruleIdentifier: identifier,
            severity: .info,
            message: "Within budget: \(lines) lines across \(fileCount) file(s)."
        )]
    }
}

// MARK: - Critical paths

/// Escalates any change that touches a configured critical area
/// (payments, auth, migrations…). Test files are exempt: strengthening
/// tests around a critical path should never make review heavier.
public struct CriticalPathRule: ReviewRule {
    public let identifier = "critical-path"
    public let criticalPrefixes: [String]

    public init(criticalPrefixes: [String]) {
        self.criticalPrefixes = criticalPrefixes
    }

    public func evaluate(_ changeSet: ChangeSet) -> [RuleFinding] {
        guard !criticalPrefixes.isEmpty else { return [] }

        let touched = changeSet.files.filter { file in
            !file.isTestFile && criticalPrefixes.contains { file.path.hasPrefix($0) }
        }

        guard !touched.isEmpty else {
            return [RuleFinding(
                ruleIdentifier: identifier,
                severity: .info,
                message: "No critical paths touched."
            )]
        }

        let paths = touched.map(\.path).sorted().joined(separator: ", ")
        return [RuleFinding(
            ruleIdentifier: identifier,
            severity: .escalate,
            message: "Touches critical path(s): \(paths). Two reviewers required regardless of size."
        )]
    }
}

// MARK: - Test presence

/// Checks whether production changes arrive with test changes.
/// Production-only diffs get a caution; past `escalateAboveLines` of
/// untested production churn, the finding escalates — at that size,
/// "trust me" is no longer a verification strategy.
public struct TestPresenceRule: ReviewRule {
    public let identifier = "test-presence"
    public let escalateAboveLines: Int

    public init(escalateAboveLines: Int = 150) {
        self.escalateAboveLines = max(1, escalateAboveLines)
    }

    public func evaluate(_ changeSet: ChangeSet) -> [RuleFinding] {
        let productionLines = changeSet.productionLinesChanged
        let testLines = changeSet.testLinesChanged

        if productionLines == 0 && testLines > 0 {
            return [RuleFinding(
                ruleIdentifier: identifier,
                severity: .info,
                message: "Test-only change (\(testLines) lines) — verification is strengthening, not weakening."
            )]
        }

        if productionLines > 0 && testLines == 0 {
            let severity: Severity = productionLines > escalateAboveLines ? .escalate : .caution
            return [RuleFinding(
                ruleIdentifier: identifier,
                severity: severity,
                message: "\(productionLines) production line(s) changed with zero test changes."
            )]
        }

        if productionLines > 0 {
            return [RuleFinding(
                ruleIdentifier: identifier,
                severity: .info,
                message: "Tests updated alongside code (\(testLines) test lines for \(productionLines) production lines)."
            )]
        }

        return []
    }
}

// MARK: - Churn concentration

/// Flags change sets where most of the churn lands in a single file.
/// Concentrated churn usually means a rewrite hiding inside a "small" PR —
/// the reviewer sees few files and underestimates the blast radius.
public struct ChurnConcentrationRule: ReviewRule {
    public let identifier = "churn-concentration"
    public let threshold: Double
    public let minimumLines: Int

    public init(threshold: Double = 0.6, minimumLines: Int = 80) {
        self.threshold = min(1.0, max(0.0, threshold))
        self.minimumLines = max(1, minimumLines)
    }

    public func evaluate(_ changeSet: ChangeSet) -> [RuleFinding] {
        let total = changeSet.totalLinesChanged
        guard total >= minimumLines else { return [] }

        let concentration = changeSet.churnConcentration
        guard concentration >= threshold else { return [] }

        let percent = Int((concentration * 100).rounded())
        return [RuleFinding(
            ruleIdentifier: identifier,
            severity: .caution,
            message: "\(percent)% of \(total) changed lines sit in one file — likely a rewrite disguised as an edit."
        )]
    }
}
