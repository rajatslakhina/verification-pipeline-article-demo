import XCTest
@testable import ReviewGateKit

final class DiffParserTests: XCTestCase {

    func testEmptyDiffProducesEmptyChangeSet() {
        let changeSet = DiffParser.parse("")
        XCTAssertTrue(changeSet.isEmpty)
        XCTAssertEqual(changeSet.totalLinesChanged, 0)
        XCTAssertEqual(changeSet.churnConcentration, 0)
    }

    func testSampleRefactorCountsAdditionsAndDeletionsExactly() {
        let changeSet = DiffParser.parse(SampleDiffs.smallRefactorWithTests)
        XCTAssertEqual(changeSet.files.count, 2)

        guard let production = changeSet.files.first, let tests = changeSet.files.last else {
            XCTFail("Expected two parsed files")
            return
        }
        XCTAssertEqual(production.path, "Sources/FeedKit/FeedFormatter.swift")
        XCTAssertEqual(production.additions, 3)
        XCTAssertEqual(production.deletions, 2)
        XCTAssertFalse(production.isTestFile)

        XCTAssertEqual(tests.path, "Tests/FeedKitTests/FeedFormatterTests.swift")
        XCTAssertEqual(tests.additions, 4)
        XCTAssertEqual(tests.deletions, 0)
        XCTAssertTrue(tests.isTestFile)
    }

    func testHeaderLinesAreNeverCountedAsChurn() {
        let diff = """
        diff --git a/Sources/App/File.swift b/Sources/App/File.swift
        index 1234567..89abcde 100644
        --- a/Sources/App/File.swift
        +++ b/Sources/App/File.swift
        @@ -1,3 +1,3 @@
         context
        -old line
        +new line
        """
        let changeSet = DiffParser.parse(diff)
        guard let file = changeSet.files.first else {
            XCTFail("Expected one parsed file")
            return
        }
        XCTAssertEqual(file.additions, 1, "The +++ header must not count as an addition")
        XCTAssertEqual(file.deletions, 1, "The --- header must not count as a deletion")
    }

    func testRenameUpdatesPathAndKind() {
        let diff = """
        diff --git a/Sources/App/OldName.swift b/Sources/App/NewName.swift
        similarity index 96%
        rename from Sources/App/OldName.swift
        rename to Sources/App/NewName.swift
        """
        let changeSet = DiffParser.parse(diff)
        guard let file = changeSet.files.first else {
            XCTFail("Expected one parsed file")
            return
        }
        XCTAssertEqual(file.path, "Sources/App/NewName.swift")
        XCTAssertEqual(file.kind, .renamed(from: "Sources/App/OldName.swift"))
        XCTAssertEqual(file.churn, 0)
    }

    func testBinaryFileIsExcludedFromLineTotals() {
        let diff = """
        diff --git a/Assets/logo.png b/Assets/logo.png
        index 1111111..2222222 100644
        Binary files a/Assets/logo.png and b/Assets/logo.png differ
        diff --git a/Sources/App/File.swift b/Sources/App/File.swift
        index 3333333..4444444 100644
        --- a/Sources/App/File.swift
        +++ b/Sources/App/File.swift
        @@ -1,2 +1,2 @@
        -old
        +new
        """
        let changeSet = DiffParser.parse(diff)
        XCTAssertEqual(changeSet.files.count, 2)
        XCTAssertEqual(changeSet.files.first?.kind, .binary)
        XCTAssertEqual(changeSet.totalLinesChanged, 2, "Binary churn must not inflate line totals")
    }

    func testNewAndDeletedFileKinds() {
        let diff = """
        diff --git a/Sources/App/Fresh.swift b/Sources/App/Fresh.swift
        new file mode 100644
        index 0000000..1111111
        --- /dev/null
        +++ b/Sources/App/Fresh.swift
        @@ -0,0 +1,2 @@
        +line one
        +line two
        diff --git a/Sources/App/Gone.swift b/Sources/App/Gone.swift
        deleted file mode 100644
        index 2222222..0000000
        --- a/Sources/App/Gone.swift
        +++ /dev/null
        @@ -1,1 +0,0 @@
        -goodbye
        """
        let changeSet = DiffParser.parse(diff)
        XCTAssertEqual(changeSet.files.count, 2)
        XCTAssertEqual(changeSet.files.first?.kind, .added)
        XCTAssertEqual(changeSet.files.first?.additions, 2)
        XCTAssertEqual(changeSet.files.last?.kind, .deleted)
        XCTAssertEqual(changeSet.files.last?.deletions, 1)
    }

    func testContentBeforeFirstHeaderIsIgnored() {
        let diff = """
        + stray line that is not part of any file
        - another stray line
        diff --git a/Sources/App/File.swift b/Sources/App/File.swift
        --- a/Sources/App/File.swift
        +++ b/Sources/App/File.swift
        @@ -1,1 +1,1 @@
        -old
        +new
        """
        let changeSet = DiffParser.parse(diff)
        XCTAssertEqual(changeSet.files.count, 1)
        XCTAssertEqual(changeSet.totalLinesChanged, 2)
    }

    func testMalformedHeaderDegradesGracefully() {
        let changeSet = DiffParser.parse("diff --git nonsense-with-no-b-marker")
        XCTAssertEqual(changeSet.files.count, 1)
        XCTAssertEqual(changeSet.files.first?.churn, 0)
    }
}

final class ChangeSetMetricsTests: XCTestCase {

    func testChurnConcentrationIsOneForSingleFile() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/Only.swift", additions: 10, deletions: 5)
        ])
        XCTAssertEqual(changeSet.churnConcentration, 1.0, accuracy: 0.0001)
    }

    func testChurnConcentrationGuardsDivisionByZero() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/Untouched.swift", additions: 0, deletions: 0)
        ])
        XCTAssertEqual(changeSet.churnConcentration, 0)
    }

    func testNegativeCountsAreClampedToZero() {
        let file = FileChange(path: "Sources/App/File.swift", additions: -3, deletions: -7)
        XCTAssertEqual(file.additions, 0)
        XCTAssertEqual(file.deletions, 0)
        XCTAssertEqual(file.churn, 0)
    }

    func testTestFileClassification() {
        XCTAssertTrue(FileChange(path: "Tests/AppTests/FlowTests.swift", additions: 1, deletions: 0).isTestFile)
        XCTAssertTrue(FileChange(path: "Sources/App/SnapshotTests.swift", additions: 1, deletions: 0).isTestFile)
        XCTAssertFalse(FileChange(path: "Sources/App/Testable.swift", additions: 1, deletions: 0).isTestFile)
    }

    func testProductionAndTestLineSplit() {
        let changeSet = ChangeSet(files: [
            FileChange(path: "Sources/App/File.swift", additions: 6, deletions: 2),
            FileChange(path: "Tests/AppTests/FileTests.swift", additions: 5, deletions: 0),
            FileChange(path: "Assets/logo.png", kind: .binary, additions: 0, deletions: 0)
        ])
        XCTAssertEqual(changeSet.productionLinesChanged, 8)
        XCTAssertEqual(changeSet.testLinesChanged, 5)
        XCTAssertEqual(changeSet.totalLinesChanged, 13)
    }
}
