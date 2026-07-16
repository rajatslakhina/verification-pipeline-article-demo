import Foundation

/// Parses unified diff text (the `git diff` format) into a ``ChangeSet``.
///
/// This is a line-classifying parser, not a full patch applier: it extracts
/// exactly what the verification rules need — per-file paths, change kinds,
/// and addition/deletion counts — and ignores everything else. Header lines
/// (`+++`, `---`, `index`) are never counted as churn because counting only
/// starts once a `@@` hunk marker has been seen for the current file.
public enum DiffParser {

    public static func parse(_ diffText: String) -> ChangeSet {
        var files: [FileChange] = []
        var current: PartialFile?
        var inHunk = false

        func flush() {
            if let finished = current {
                files.append(finished.finalized())
            }
            current = nil
            inHunk = false
        }

        for rawLine in diffText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("diff --git ") {
                flush()
                current = PartialFile(path: Self.headerPath(from: line))
                continue
            }

            guard var file = current else { continue }

            if line.hasPrefix("new file mode") {
                file.explicitKind = .added
            } else if line.hasPrefix("deleted file mode") {
                file.explicitKind = .deleted
            } else if line.hasPrefix("rename from ") {
                file.renamedFrom = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                file.path = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                file.isBinary = true
            } else if line.hasPrefix("@@") {
                inHunk = true
            } else if inHunk {
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    file.additions += 1
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    file.deletions += 1
                }
            }

            current = file
        }

        flush()
        return ChangeSet(files: files)
    }

    /// Extracts the post-change path from a `diff --git a/old b/new` header.
    /// Falls back to the raw remainder of the header if the `b/` marker is
    /// missing, so a malformed header degrades to an odd path — never a crash.
    private static func headerPath(from headerLine: String) -> String {
        let remainder = String(headerLine.dropFirst("diff --git ".count))
        if let markerRange = remainder.range(of: " b/", options: .backwards) {
            return String(remainder[markerRange.upperBound...])
        }
        return remainder
    }

    private struct PartialFile {
        var path: String
        var explicitKind: ChangeKind?
        var renamedFrom: String?
        var isBinary = false
        var additions = 0
        var deletions = 0

        func finalized() -> FileChange {
            let kind: ChangeKind
            if isBinary {
                kind = .binary
            } else if let renamedFrom {
                kind = .renamed(from: renamedFrom)
            } else if let explicitKind {
                kind = explicitKind
            } else {
                kind = .modified
            }
            return FileChange(path: path, kind: kind, additions: additions, deletions: deletions)
        }
    }
}
