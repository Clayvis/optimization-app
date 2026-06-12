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
                        .animation(.easeOut(duration: 0.5), value: progress)
                    Image(mascotState.assetName(for: variant))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 78, height: 78)
                        .clipShape(Circle())
                }
                .frame(width: 104, height: 104)
                .scaleEffect(bounceScale)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.45),
                           value: pokeCount)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mascot \(mascotState.rawValue), \(tally.completed) of \(tally.scheduled) goals done. Tap for status.")

            if showingTallyCaption {
                Text("\(tally.completed) of \(tally.scheduled) goals today")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            } else if !isInternalReason(mascotReason) {
                Text(mascotReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(tally.completed >= tally.scheduled && tally.scheduled > 0
                     ? "day closed"
                     : "\(tally.scheduled - tally.completed) to go")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Subtle squash on even pokes, back to rest on odd, so each tap visibly
    /// lands without keeping any animation running between interactions.
    private var bounceScale: CGFloat {
        pokeCount % 2 == 0 ? 1.0 : 0.93
    }

    private func poke() {
        WKInterfaceDevice.current().play(.click)
        pokeCount += 1
        showingTallyCaption.toggle()
        recomputeMascot()
        // Bounce back to rest right after the squash lands.
        if !reduceMotion {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))  // MARK: try? justified - cancellation just skips the rebound frame.
                pokeCount += 1
            }
        } else {
            pokeCount += 1
        }
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
            .disabled(!fastIsActive)
        }
    }

    @ViewBuilder
    private var streakRow: some View {
        let workout = streakValue(.workout)
        let hydration = streakValue(.hydration)
        let learning = streakValue(.learning)
        HStack(spacing: 6) {
            streakChip(systemImage: "figure.strengthtraining.traditional", days: workout)
            streakChip(systemImage: "drop.fill", days: hydration)
            streakChip(systemImage: "book.fill", days: learning)
        }
        .padding(.top, 2)
    }

    private func streakChip(systemImage: String, days: Int) -> some View {
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

    /// Mascot recompute on appear only; we don't run a 30s ticker on the watch
    /// like CharacterStateService does on iOS — that would burn battery for no
    /// real-time benefit. The state on the wrist refreshes when the user
    /// opens the app or the iOS app pushes via WCSession (M3.8 Block 3).
    private func recomputeMascot() {
        let cal = deviceCalendar()
        let day = cal.startOfDay(for: Date())
        let log = logs.first { $0.supersededAt == nil && cal.isDate($0.date, inSameDayAs: day) }

        let workoutCounter = streaks.first { $0.domain == StreakDomain.workout.rawValue }
        let workoutMilestone = isMilestone(workoutCounter?.currentStreak)
            && (workoutCounter?.lastCompletedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false)
        let anyBroken = streaks.contains { c in
            guard let last = c.lastCompletedDate else { return false }
            let yesterday = cal.date(byAdding: .day, value: -1, to: day) ?? day
            return c.currentStreak == 0 && cal.isDate(last, inSameDayAs: yesterday)
        }

        // Fast window check (manual or scheduled).
        let inFast: Bool
        if let svc = fastingService, let p = profile {
            inFast = svc.state(at: Date(), profile: p) == .fasting
        } else {
            inFast = false
        }

        // Order matches CharacterState.precedenceOrder (urgent/achievement/
        // proud/disappointed/tired/thirsty/fasting/neutral) — but on the
        // wrist we skip urgent (no schedule lookup here) and stay on the
        // most likely visible states.
        if workoutMilestone {
            mascotState = .proud
            mascotReason = "milestone today"
        } else if anyBroken {
            mascotState = .disappointed
            mascotReason = "streak broke"
        } else if let log, let sleep = log.sleepHours, sleep < 6 {
            mascotState = .tired
            mascotReason = "low sleep"
        } else if inFast {
            mascotState = .fasting
            mascotReason = "in fast window"
        } else {
            mascotState = .neutral
            mascotReason = ""
        }
    }

    private func isMilestone(_ s: Int?) -> Bool {
        guard let s else { return false }
        return s == 7 || s == 30 || s == 100
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
