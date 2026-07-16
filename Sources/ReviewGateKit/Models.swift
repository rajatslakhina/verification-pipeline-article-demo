import Foundation

/// How a file was changed in a diff.
public enum ChangeKind: Sendable, Equatable {
    case modified
    case added
    case deleted
    case renamed(from: String)
    case binary
}

/// One file's contribution to a change set.
public struct FileChange: Sendable, Equatable {
    public let path: String
    public let kind: ChangeKind
    public let additions: Int
    public let deletions: Int

    public init(path: String, kind: ChangeKind = .modified, additions: Int, deletions: Int) {
        self.path = path
        self.kind = kind
        // Negative counts are meaningless for a diff; clamp defensively rather than trap.
        self.additions = max(0, additions)
        self.deletions = max(0, deletions)
    }

    /// Total churn this file contributes (added + removed lines).
    public var churn: Int { additions + deletions }

    /// Whether this path looks like a test file.
    ///
    /// Deliberately conservative: a `Tests/` directory component or a
    /// `*Tests.swift` suffix. False negatives here are safer than false
    /// positives, because test files are exempt from critical-path escalation.
    public var isTestFile: Bool {
        path.contains("Tests/") || path.hasSuffix("Tests.swift")
    }
}

/// A parsed change set plus the derived metrics every rule works from.
public struct ChangeSet: Sendable, Equatable {
    public let files: [FileChange]

    public init(files: [FileChange]) {
        self.files = files
    }

    public var isEmpty: Bool { files.isEmpty }

    /// Total churn across all non-binary files.
    public var totalLinesChanged: Int {
        files.reduce(0) { total, file in
            file.kind == .binary ? total : total + file.churn
        }
    }

    public var filesTouched: Int { files.count }

    /// Churn in production (non-test, non-binary) files.
    public var productionLinesChanged: Int {
        files.reduce(0) { total, file in
            (file.kind == .binary || file.isTestFile) ? total : total + file.churn
        }
    }

    /// Churn in test files.
    public var testLinesChanged: Int {
        files.reduce(0) { total, file in
            (file.kind == .binary || !file.isTestFile) ? total : total + file.churn
        }
    }

    /// Share of total churn concentrated in the single most-churned file,
    /// in `0.0...1.0`. Returns 0 for an empty or churn-free change set —
    /// guarded against division by zero.
    public var churnConcentration: Double {
        let total = totalLinesChanged
        guard total > 0 else { return 0 }
        let maxChurn = files
            .filter { $0.kind != .binary }
            .map(\.churn)
            .max() ?? 0
        return Double(maxChurn) / Double(total)
    }
}
