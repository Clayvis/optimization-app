import SwiftUI
import SwiftData
import WatchKit

/// Watch idle "home" — mascot front and center, master metric below, plus a
/// one-tap row for the highest-frequency logs (water, end fast). Designed to
/// feel like a glance: open, see your day, log one thing, drop the wrist.
///
/// Battery posture: no Timer.scheduledTimer. The clock-driven elements
/// (fasting elapsed, "now" header) live inside a TimelineView with a 60s
/// cadence — Apple's WidgetKit/Watch policy honors this without burning the
/// chip. Heavy queries (hydration target lookup) run once on appear, not on
/// the ticker.
@MainActor
struct IdleHomeWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var logs: [DailyLog]
    @Query(sort: [SortDescriptor(\StreakCounter.domain, order: .forward)])
    private var streaks: [StreakCounter]

    @State private var mascotState: CharacterState = .neutral
    @State private var mascotReason: String = ""
    @State private var hydrationService: HydrationService?
    @State private var fastingService: FastingService?
    @State private var refreshTrigger = 0
    @State private var pokeCount = 0
    @State private var showingTallyCaption = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var profile: UserProfile? { profiles.first }
    private var variant: String { profile?.mascotVariant ?? "ninja_male" }
    private var motionDisabled: Bool { reduceMotion || profile?.reducedMotion == true }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                mascotBlock
                fastingBlock
                quickLogRow
                streakRow
            }
            .padding(.horizontal, 4)
            .id(refreshTrigger)
        }
        .task { await loadServices() }
        .onAppear { recomputeMascot() }
    }

    // MARK: - Blocks

    /// The tamagotchi: mascot inside a live goal ring (today's protocol
    /// adherence). Tap to poke it — haptic, a little bounce, and the caption
    /// flips between the mascot's reason and the day tally. The ring IS the
    /// master metric, so the goals live on the same glance as the character.
    @ViewBuilder
    private var mascotBlock: some View {
        let tally = todayTally()
        let progress = tally.scheduled > 0 ? Double(tally.completed) / Double(tally.scheduled) : 0

        VStack(spacing: 4) {
            Button {
                poke()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: max(0.0001, min(1, progress)))
                        .stroke(
                            progress >= 1 ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(motionDisabled ? nil : .easeOut(duration: 0.5), value: progress)
                    Image(mascotState.assetName(for: variant))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 78, height: 78)
                        .clipShape(Circle())
                }
                .frame(width: 104, height: 104)
                .phaseAnimator([false, true], trigger: pokeCount) { content, pressed in
                    content.scaleEffect(motionDisabled ? 1 : (pressed ? 0.93 : 1))
                } animation: { _ in
                    motionDisabled ? nil : .spring(response: 0.3, dampingFraction: 0.6)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mascot \(mascotState.rawValue), \(tally.completed) of \(tally.scheduled) goals done. Tap for status.")
            .accessibilityHint("Double tap to hear the alternate daily status")

            if showingTallyCaption {
                Text("\(tally.completed) of \(tally.scheduled) goals today")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            } else if !isInternalReason(mascotReason) {
                Text(mascotState.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(mascotReason)
            } else {
                Text(tally.completed >= tally.scheduled && tally.scheduled > 0
                     ? "day closed"
                     : "\(tally.scheduled - tally.completed) to go")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func poke() {
        WKInterfaceDevice.current().play(.click)
        pokeCount += 1
        showingTallyCaption.toggle()
        recomputeMascot()
    }

    @ViewBuilder
    private var fastingBlock: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            if let svc = fastingService, let p = profile {
                let state = svc.state(at: now, profile: p)
                let elapsed = svc.elapsedFasting(at: now, profile: p)
                let remaining = svc.remainingInFast(at: now, profile: p)
                HStack {
                    Image(systemName: state == .fasting ? "timer" : "fork.knife")
                        .foregroundStyle(state == .fasting ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state == .fasting ? "Fasting" : "Eating")
                            .font(.caption.weight(.semibold))
                        Text(state == .fasting
                             ? (remaining.map { "\(formatHM($0)) left" } ?? "open")
                             : "open")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state == .fasting {
                        Text(formatHM(elapsed))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state == .fasting
                    ? "Fasting, \(remaining.map { "\(formatHM($0)) remaining" } ?? "end time unavailable"), \(formatHM(elapsed)) elapsed"
                    : "Eating window open")
            }
        }
    }

    @ViewBuilder
    private var quickLogRow: some View {
        HStack(spacing: 8) {
            Button {
                quickLogWater(oz: 16)
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").foregroundStyle(.blue)
                    Text("+16 oz").font(.caption2.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .accessibilityLabel("Log 16 ounces of water")
            .accessibilityHint("Adds water to today's hydration total")

            Button {
                endFastIfActive()
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
                    Text("End fast").font(.caption2.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("End current fast")
            .accessibilityHint(fastIsActive ? "Ends and records the current fast" : "No fast is currently active")
            .disabled(!fastIsActive)
        }
    }

    @ViewBuilder
    private var streakRow: some View {
        let workout = streakValue(.workout)
        let hydration = streakValue(.hydration)
        let learning = streakValue(.learning)
        HStack(spacing: 6) {
            streakChip(systemImage: "figure.strengthtraining.traditional", label: "Workout", days: workout)
            streakChip(systemImage: "drop.fill", label: "Hydration", days: hydration)
            streakChip(systemImage: "book.fill", label: "Learning", days: learning)
        }
        .padding(.top, 2)
    }

    private func streakChip(systemImage: String, label: String, days: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2)
            if days > 0 {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2)
            }
            Text("\(days)d")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.18))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) streak")
        .accessibilityValue("\(days) days")
    }

    // MARK: - Actions

    private func quickLogWater(oz: Double) {
        guard let svc = hydrationService else { return }
        _ = try? svc.logBottle(oz: oz)  // MARK: try? justified - haptic still confirms; a failed write surfaces on next refresh rather than blocking the glance.
        WKInterfaceDevice.current().play(.success)
        refreshTrigger += 1
    }

    private func endFastIfActive() {
        guard let svc = fastingService else { return }
        _ = try? svc.endManualFast()  // MARK: try? justified - same glance posture as logBottle above.
        WKInterfaceDevice.current().play(.success)
        refreshTrigger += 1
    }

    private var fastIsActive: Bool {
        guard let svc = fastingService, let p = profile else { return false }
        return svc.state(at: Date(), profile: p) == .fasting
    }

    // MARK: - Computation

    /// Today's tally via the shared `ProtocolGoalSnapshot` — the SAME rules the
    /// phone, the master metric, and the watch-face complication use (scheduled-
    /// aware workout domain, day-type hydration floor, the real learning rule,
    /// travel/sick grace). Replaces a hand-rolled tally that diverged on every
    /// rule (32 oz bottle = hydration done, hardcoded 4 domains, no grace).
    private func todayTally() -> (completed: Int, scheduled: Int) {
        let snap = ProtocolGoalSnapshot.make(modelContext: modelContext)
        return (snap.completedDomains, snap.totalDomains)
    }

    private func streakValue(_ domain: StreakDomain) -> Int {
        streaks.first { $0.domain == domain.rawValue }?.currentStreak ?? 0
    }

    /// Reuse the phone's resolver so recovery and comeback have the same
    /// meaning on the wrist. Refreshes follow user interaction, not polling.
    private func recomputeMascot() {
        let now = Date()
        var inputs = CharacterStateService.gatherInputs(
            modelContext: modelContext, timezone: UserCalendar.timezone(modelContext: modelContext), now: now
        )
        if let service = fastingService, let profile {
            inputs.inFastWindow = service.state(at: now, profile: profile) == .fasting
        }
        let resolved = CharacterStateService.resolve(inputs: inputs)
        mascotState = resolved.state
        mascotReason = resolved.reason
    }

    private func isInternalReason(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty || trimmed == "default"
    }

    /// Device-timezone calendar. Renamed from `jstCalendar`: the body has
    /// followed the device since the M3 timezone centralization; only the
    /// name still claimed a JST pin.
    private func deviceCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    private func formatHM(_ s: TimeInterval) -> String {
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    private func loadServices() async {
        do {
            let config = try ScheduleConfigLoader.load()
            hydrationService = HydrationService(modelContext: modelContext, targets: config.hydrationTargetsOz)
            fastingService = FastingService(modelContext: modelContext, defaults: config.fastingDefaults)
        } catch {
            // Stay quiet on the watch — surface bad config in iOS Diagnostics, not on the wrist.
        }
        recomputeMascot()
    }
}
