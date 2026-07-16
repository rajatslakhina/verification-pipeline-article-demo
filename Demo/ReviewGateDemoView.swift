import SwiftUI
import ReviewGateKit

/// Interactive tour of the verification pipeline: pick one of three
/// realistic diffs and watch the gate stack produce a routing verdict
/// with its full audit trail.
struct ReviewGateDemoView: View {

    private enum Sample: String, CaseIterable, Identifiable {
        case refactor = "Refactor + tests"
        case feature = "Feature, no tests"
        case payments = "Payments hotfix"

        var id: String { rawValue }

        var diffText: String {
            switch self {
            case .refactor: return SampleDiffs.smallRefactorWithTests
            case .feature: return SampleDiffs.featureWithoutTests
            case .payments: return SampleDiffs.paymentsHotfix
            }
        }

        var subtitle: String {
            switch self {
            case .refactor: return "5 production lines, 4 test lines"
            case .feature: return "14 production lines, 0 test lines"
            case .payments: return "5 lines inside Sources/Payments"
            }
        }
    }

    @State private var selectedSample: Sample = .refactor

    private let pipeline = VerificationPipeline.standard()

    private var verdict: ReviewVerdict {
        pipeline.evaluate(diffText: selectedSample.diffText)
    }

    var body: some View {
        List {
            Section("Incoming change") {
                Picker("Sample diff", selection: $selectedSample) {
                    ForEach(Sample.allCases) { sample in
                        Text(sample.rawValue).tag(sample)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedSample.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Routing verdict") {
                verdictCard
            }

            Section("Audit trail") {
                ForEach(Array(verdict.findings.enumerated()), id: \.offset) { _, finding in
                    findingRow(finding)
                }
            }
        }
        .navigationTitle("ReviewGateKit")
    }

    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: routingSymbol)
                    .font(.title2)
                    .foregroundStyle(riskColor)
                VStack(alignment: .leading) {
                    Text(routingTitle)
                        .font(.headline)
                    Text("Risk: \(riskLabel)")
                        .font(.subheadline)
                        .foregroundStyle(riskColor)
                }
            }
            Text(routingExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func findingRow(_ finding: RuleFinding) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(finding.ruleIdentifier)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(severityColor(finding.severity).opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                Text(severityLabel(finding.severity))
                    .font(.caption.bold())
                    .foregroundStyle(severityColor(finding.severity))
            }
            Text(finding.message)
                .font(.footnote)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Presentation helpers

    private var routingTitle: String {
        switch verdict.routing {
        case .agentReviewSufficient: return "Agent review sufficient"
        case .singleHumanReview: return "One human reviewer"
        case .pairHumanReview: return "Pair review required"
        }
    }

    private var routingExplanation: String {
        switch verdict.routing {
        case .agentReviewSufficient:
            return "Automated checks plus an agent pass cover this change. Human attention is saved for riskier work."
        case .singleHumanReview:
            return "One reviewer, with the agent's pre-review as context. The caution findings below say why."
        case .pairHumanReview:
            return "Two humans sign off. Agent output is input to their review, never a substitute for it."
        }
    }

    private var routingSymbol: String {
        switch verdict.routing {
        case .agentReviewSufficient: return "checkmark.shield"
        case .singleHumanReview: return "person.crop.circle.badge.checkmark"
        case .pairHumanReview: return "person.2.circle"
        }
    }

    private var riskLabel: String {
        switch verdict.riskLevel {
        case .low: return "low"
        case .moderate: return "moderate"
        case .high: return "high"
        }
    }

    private var riskColor: Color {
        switch verdict.riskLevel {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        }
    }

    private func severityColor(_ severity: Severity) -> Color {
        switch severity {
        case .info: return .green
        case .caution: return .orange
        case .escalate: return .red
        }
    }

    private func severityLabel(_ severity: Severity) -> String {
        switch severity {
        case .info: return "INFO"
        case .caution: return "CAUTION"
        case .escalate: return "ESCALATE"
        }
    }
}

#Preview {
    NavigationStack {
        ReviewGateDemoView()
    }
}
