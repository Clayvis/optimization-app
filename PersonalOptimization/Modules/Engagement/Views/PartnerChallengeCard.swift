import SwiftUI
import SwiftData

/// Apple-Fitness-style weekly challenge card for the paired dyad: two point
/// bars (protocol points, same rules as the master metric), the leader line,
/// and my daily points dots. Hidden until a partner is paired, so single-user
/// installs never see it; renders "waiting" copy until the partner's
/// same-week score syncs through the zone (live with the CloudKit
/// implementation, decision 007).
@MainActor
struct PartnerChallengeCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    /// Overrides the zone for previews/tests; production resolves the default
    /// (Noop today, CloudKit once wired).
    private let zoneOverride: PartnerSharedZone?

    @State private var standing: ChallengeStanding?

    init(zoneOverride: PartnerSharedZone? = nil) {
        self.zoneOverride = zoneOverride
    }

    private var paired: Bool {
        profiles.first?.partnerRecordID != nil
    }

    var body: some View {
        Group {
            if paired, let standing {
                card(standing)
            } else {
                EmptyView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard paired else { return }
        let service = PartnerService(modelContext: modelContext,
                                     zone: zoneOverride ?? NoopPartnerSharedZone())
        // MARK: try? justified - a zone fetch failure renders the card hidden this pass; next appearance retries.
        standing = try? await service.challengeStanding()
    }

    @ViewBuilder
    private func card(_ s: ChallengeStanding) -> some View {
        let myPoints = s.week.totalPoints
        let scaleMax = max(myPoints, s.partnerPoints ?? 0, 1)

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SectionEyebrow(title: "Weekly challenge", tint: Theme.kin)
                Spacer()
                Text(s.daysRemaining == 1 ? "last day" : "\(s.daysRemaining) days left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            pointsBar(label: "You", points: myPoints, scaleMax: scaleMax, tint: Theme.kurenai)
            if let partnerPoints = s.partnerPoints {
                pointsBar(label: "Her", points: partnerPoints, scaleMax: scaleMax, tint: Theme.murasaki)
            } else {
                Text(s.partnerStale
                     ? "Waiting on her week to sync."
                     : "Waiting for her first score.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let leader = s.leader {
                Text(leaderLine(leader))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            dailyDots(s.week)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(s))
    }

    @ViewBuilder
    private func pointsBar(label: String, points: Int, scaleMax: Int, tint: Color) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inkSunken)
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(8, geo.size.width * CGFloat(points) / CGFloat(scaleMax)))
                }
            }
            .frame(height: 12)
            Text("\(points)")
                .font(.body.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    /// My points per elapsed day, Mon..today. Small honest dots: the number
    /// of domains closed each day, no smoothing.
    @ViewBuilder
    private func dailyDots(_ week: ChallengeWeek) -> some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(Array(week.dailyPoints.enumerated()), id: \.offset) { _, points in
                Text("\(points)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(points > 0 ? Theme.matcha : Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.inkSunken))
            }
            Spacer()
            Text("pts/day")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func leaderLine(_ leader: ChallengeLeader) -> String {
        switch leader {
        case .me(let by):      return "You lead by \(by)."
        case .partner(let by): return "She leads by \(by). Close your day."
        case .tied:            return "Dead even."
        }
    }

    private func accessibilitySummary(_ s: ChallengeStanding) -> String {
        var parts = ["Weekly challenge. You have \(s.week.totalPoints) points."]
        if let partner = s.partnerPoints {
            parts.append("Partner has \(partner) points.")
        }
        parts.append("\(s.daysRemaining) days remaining.")
        return parts.joined(separator: " ")
    }
}

#Preview {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let profile = UserProfile(name: "Clay")
    profile.partnerRecordID = "wife-record"
    container.mainContext.insert(profile)

    let zone = MemoryPartnerSharedZone()
    let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    zone.preloadPartner(PartnerSharedRecord(
        userID: "wife-record",
        currentStreak: 9,
        masterMetric: 0.75,
        mascotState: "proud",
        challengeWeekStart: weekStart,
        challengeWeekPoints: 14
    ))

    return ScrollView {
        PartnerChallengeCard(zoneOverride: zone)
            .padding()
    }
    .dojoBackground()
    .modelContainer(container)
}
