import SwiftUI
import SwiftData

/// Transparent readiness surface (Gap 3: opaque scores). Shows the qualitative
/// verdict, the input components (HRV / resting HR / sleep) with their direction
/// vs the 7-day baseline, and one concrete load adjustment. No black-box number,
/// no false precision. Hides entirely on cold start (no Health data yet) rather
/// than inventing a score.
@MainActor
struct RecoveryCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var detail: RecoveryDetail?

    var body: some View {
        Group {
            if let detail, detail.hasData {
                card(detail)
            } else {
                EmptyView()
            }
        }
        .task { recompute() }
    }

    private func recompute() {
        guard let profile = profiles.first else { detail = nil; return }
        detail = RecoveryGate(modelContext: modelContext).evaluateDetailed(profile: profile)
    }

    private func card(_ d: RecoveryDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("READINESS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(d.headline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint(d.recommendation))
            }

            Text(d.reason)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(d.components) { component in
                    componentChip(component)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: icon(d.recommendation))
                    .font(.caption)
                Text(d.loadAdjustment)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint(d.recommendation))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Readiness: \(d.headline). \(d.reason). \(d.loadAdjustment).")
    }

    private func componentChip(_ c: RecoveryComponent) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: arrow(c.direction))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(c.isFavorable ? .green : .orange)
                    .accessibilityHidden(true)
                Text(c.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(c.valueText)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            if let baseline = c.baselineText {
                Text(baseline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .dojoCardSurface()
    }

    private func tint(_ recommendation: RecoveryRecommendation) -> Color {
        switch recommendation {
        case .normal:    return .green
        case .downgrade: return .orange
        case .rest:      return .red
        }
    }

    private func icon(_ recommendation: RecoveryRecommendation) -> String {
        switch recommendation {
        case .normal:    return "checkmark.circle.fill"
        case .downgrade: return "arrow.down.circle.fill"
        case .rest:      return "bed.double.fill"
        }
    }

    private func arrow(_ direction: RecoveryComponent.Direction) -> String {
        switch direction {
        case .up:   return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "minus"
        }
    }
}

#Preview {
    // swiftlint:disable force_try
    let container = try! ModelContainer(
        for: AppSchema.schema(),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    let context = container.mainContext
    let profile = UserProfile()
    context.insert(profile)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    // Seed a few days of HK signals so the card has data to render.
    for i in 0..<5 {
        let log = DailyLog(date: cal.date(byAdding: .day, value: -i, to: Date())!)
        log.hrvRmssd = i == 0 ? 42 : 58
        log.restingHR = i == 0 ? 56 : 50
        log.sleepHours = i == 0 ? 5.2 : 7.4
        context.insert(log)
    }
    return List {
        RecoveryCard()
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    .modelContainer(container)
    // swiftlint:enable force_try
}
