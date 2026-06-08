import SwiftUI
import SwiftData

/// Cooperative spouse-dyad card (build sheet section 3): shared visibility, the
/// joint streak, and a one-tap nudge. Framed as "we both closed today," never a
/// competition. Hidden until a partner is paired and has published a snapshot.
///
/// The v1.0 reality is single-user: the live CloudKit shared zone is deferred to
/// a paid Apple Developer account (decision 007), so this card stays hidden in
/// production today. It is fully wired against the `PartnerSharedZone` seam, so
/// it lights up with one PR (the live zone) once the account lands.
@MainActor
struct PartnerStatusCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    /// Overrides the zone for previews/tests. Production uses the default Noop
    /// zone (single-user), so the card renders nothing.
    private let zoneOverride: PartnerSharedZone?

    @State private var status: JointStreakStatus?
    @State private var incomingNudge: PartnerNudge?
    @State private var nudgeSent = false

    init(zoneOverride: PartnerSharedZone? = nil) {
        self.zoneOverride = zoneOverride
    }

    var body: some View {
        Group {
            if let status, status.partnerPaired {
                card(status)
            } else {
                EmptyView()
            }
        }
        .task { await load() }
    }

    private func service() -> PartnerService {
        PartnerService(modelContext: modelContext, zone: zoneOverride ?? NoopPartnerSharedZone())
    }

    private func load() async {
        let service = service()
        let partner = try? await service.partnerSnapshot()
        incomingNudge = try? await service.pendingNudge()
        let counters = modelContext.fetchOrEmpty(FetchDescriptor<StreakCounter>())
        let master = counters.first { $0.domain == StreakDomain.protocolAdherence.rawValue }
        let ownStreak = master?.currentStreak ?? 0
        let ownClosedToday = master?.lastCompletedDate.map { Calendar.current.isDateInToday($0) } ?? false
        status = PartnerService.jointStatus(
            ownStreak: ownStreak,
            ownClosedToday: ownClosedToday,
            partner: partner,
            calendar: UserCalendar.current(modelContext: modelContext)
        )
    }

    private func card(_ s: JointStreakStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TOGETHER")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if s.bothClosedToday {
                    Label("You both closed today", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "link")
                    .foregroundStyle(s.jointStreak > 0 ? .orange : .secondary)
                    .accessibilityHidden(true)
                Text("\(s.jointStreak)")
                    .font(.title.weight(.bold))
                    .monospacedDigit()
                Text("day joint streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(s.jointStreak) day joint streak")

            HStack(spacing: 10) {
                streakPill(label: "You", days: s.ownStreak)
                streakPill(label: "Partner", days: s.partnerStreak ?? 0)
            }

            if let nudge = incomingNudge {
                HStack(spacing: 6) {
                    Image(systemName: "hand.wave.fill").foregroundStyle(.blue)
                    Text(nudge.message).font(.caption)
                }
            }

            Button {
                Task { await sendNudge() }
            } label: {
                Label(nudgeSent ? "Nudge sent" : "Nudge your partner", systemImage: "hand.wave.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(nudgeSent)
            .accessibilityHint("Sends a gentle prompt to your partner.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func streakPill(label: String, days: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(days)d")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sendNudge() async {
        // try? justified because: best-effort nudge over the zone seam; a failure
        // is non-critical and the button state still confirms the tap.
        try? await service().sendNudge()
        nudgeSent = true
    }
}

#if DEBUG
#Preview {
    // swiftlint:disable force_try
    let container = try! ModelContainer(
        for: AppSchema.schema(),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    let counter = StreakCounter(domain: .protocolAdherence)
    counter.currentStreak = 9
    counter.lastCompletedDate = Calendar.current.startOfDay(for: Date())
    container.mainContext.insert(counter)

    let zone = MemoryPartnerSharedZone()
    zone.preloadPartner(PartnerSharedRecord(
        userID: "partner",
        currentStreak: 12,
        masterMetric: 1.0,
        mascotState: "proud",
        lastUpdate: Date()
    ))

    return List {
        PartnerStatusCard(zoneOverride: zone)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    .modelContainer(container)
    // swiftlint:enable force_try
}
#endif
