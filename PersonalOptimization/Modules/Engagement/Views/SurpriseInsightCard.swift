import SwiftUI
import SwiftData

/// Variable-reward surprise card. Appears on the unpredictable schedule decided
/// by SurpriseInsightService and is hidden otherwise. Deliberately styled unlike
/// the routine daily Coach card so it reads as an earned bonus, not a fixture.
@MainActor
struct SurpriseInsightCard: View {
    @Environment(\.modelContext) private var modelContext

    /// Preview/test injection. When set, the card renders this surprise and skips
    /// the schedule decision.
    private let injected: SurpriseInsight?

    @State private var surprise: SurpriseInsight?

    init(injected: SurpriseInsight? = nil) {
        self.injected = injected
    }

    private var shown: SurpriseInsight? { injected ?? surprise }

    var body: some View {
        Group {
            if let shown {
                card(shown)
            } else {
                EmptyView()
            }
        }
        .task {
            guard injected == nil else { return }
            decide()
        }
    }

    private func decide() {
        let service = SurpriseInsightService(modelContext: modelContext)
        if let s = service.surpriseForToday() {
            surprise = s
            service.markShown(body: s.body)
        }
    }

    private func card(_ s: SurpriseInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("A SURPRISE FOR YOU")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(s.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.18), Color.blue.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.purple.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Surprise insight: \(s.body)")
    }
}

#Preview {
    // swiftlint:disable force_try
    let container = try! ModelContainer(
        for: AppSchema.schema(),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    return List {
        SurpriseInsightCard(injected: SurpriseInsight(body: "You move more on the days you sleep 7+ hours. The pattern is real, and it is yours."))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    .modelContainer(container)
    // swiftlint:enable force_try
}
