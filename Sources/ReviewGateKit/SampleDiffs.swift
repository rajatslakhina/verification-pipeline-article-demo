import Foundation

/// Realistic unified diffs shared by the demo app and the test suite,
/// so what you see in the demo is exactly what the tests pin down.
public enum SampleDiffs {

    /// A tidy refactor with tests updated alongside: 5 production lines,
    /// 4 test lines, no critical paths. Expected: low risk, agent-sufficient.
    public static let smallRefactorWithTests = """
    diff --git a/Sources/FeedKit/FeedFormatter.swift b/Sources/FeedKit/FeedFormatter.swift
    index 1a2b3c4..5d6e7f8 100644
    --- a/Sources/FeedKit/FeedFormatter.swift
    +++ b/Sources/FeedKit/FeedFormatter.swift
    @@ -10,9 +10,11 @@ struct FeedFormatter {
         func formattedTitle(for item: FeedItem) -> String {
    -        let title = item.title ?? ""
    -        let byline = makeByline(item)
    +        let title = item.resolvedTitle
    +        let byline = Byline(item).rendered
    +        let footer = Footer(item).rendered
             return assemble(title, byline)
         }
    diff --git a/Tests/FeedKitTests/FeedFormatterTests.swift b/Tests/FeedKitTests/FeedFormatterTests.swift
    index 9a8b7c6..5f4e3d2 100644
    --- a/Tests/FeedKitTests/FeedFormatterTests.swift
    +++ b/Tests/FeedKitTests/FeedFormatterTests.swift
    @@ -20,4 +20,8 @@ final class FeedFormatterTests: XCTestCase {
         }
    +
    +    func testResolvedTitleFallsBackToHeadline() {
    +        XCTAssertEqual(FeedFormatter().formattedTitle(for: .headlineOnlyFixture), "Headline")
    +    }
     }
    """

    /// A feature landing without any test changes: two production files,
    /// zero test files. Expected: moderate risk, single human review.
    public static let featureWithoutTests = """
    diff --git a/Sources/Search/SearchRanker.swift b/Sources/Search/SearchRanker.swift
    index 1111aaa..2222bbb 100644
    --- a/Sources/Search/SearchRanker.swift
    +++ b/Sources/Search/SearchRanker.swift
    @@ -5,6 +5,14 @@ struct SearchRanker {
         func rank(_ results: [SearchResult]) -> [SearchResult] {
    -        results.sorted { $0.score > $1.score }
    +        let boosted = results.map(applyRecencyBoost)
    +        return boosted.sorted { lhs, rhs in
    +            if lhs.score == rhs.score {
    +                return lhs.updatedAt > rhs.updatedAt
    +            }
    +            return lhs.score > rhs.score
    +        }
         }
    +
    +    private func applyRecencyBoost(_ result: SearchResult) -> SearchResult {
    diff --git a/Sources/Search/SearchResultsViewModel.swift b/Sources/Search/SearchResultsViewModel.swift
    index 3333ccc..4444ddd 100644
    --- a/Sources/Search/SearchResultsViewModel.swift
    +++ b/Sources/Search/SearchResultsViewModel.swift
    @@ -12,5 +12,9 @@ final class SearchResultsViewModel {
         func refresh() async {
    -        results = await service.search(query)
    +        let ranked = ranker.rank(await service.search(query))
    +        results = ranked
    +        lastRefreshed = clock.now
         }
    """

    /// A one-line-looking hotfix that lands inside the payments path with
    /// no tests. Expected: high risk, pair review — size never overrides
    /// criticality.
    public static let paymentsHotfix = """
    diff --git a/Sources/Payments/PaymentAuthorizer.swift b/Sources/Payments/PaymentAuthorizer.swift
    index aaaa111..bbbb222 100644
    --- a/Sources/Payments/PaymentAuthorizer.swift
    +++ b/Sources/Payments/PaymentAuthorizer.swift
    @@ -30,7 +30,10 @@ struct PaymentAuthorizer {
         func authorize(_ request: PaymentRequest) async throws -> AuthorizationToken {
    -        try await gateway.authorize(request)
    +        var request = request
    +        request.retryPolicy = .idempotentOnly
    +        let token = try await gateway.authorize(request)
    +        return token
         }
    """
}
