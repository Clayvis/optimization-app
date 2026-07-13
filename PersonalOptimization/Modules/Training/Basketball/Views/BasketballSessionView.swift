import SwiftUI
import SwiftData
import HealthKit

struct BasketballSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var session: BasketballSession?
    @State private var service: BasketballService?
    @State private var startedAt = Date()
    @State private var hydrationOz: Double = 0
    @State private var achillesScore: Int = 5
    @State private var ended = false
    @State private var liveMetrics: LiveWorkoutMetrics?

    private var achillesCheckInEnabled: Bool {
        profiles.first?.achillesCheckInEnabled ?? true
    }

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                readyContent
            }
        }
        .navigationTitle("Basketball")
        .task { resumeIfActive() }
        .onDisappear { liveMetrics?.end() }
        .sensoryFeedback(.success, trigger: ended)
    }

    // MARK: - Ready state (nothing inserted until the user starts)

    @ViewBuilder
    private var readyContent: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "basketball.fill")
                        .font(.title)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Court session")
                            .font(.headline)
                        Text("Timer, hydration, and Achilles check-in. Apple Health fills in calories and distance as you play.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LastWorkoutRecapRow { $0 == .basketball }
            }

            if achillesCheckInEnabled {
                Section {
                    Label("You'll log an Achilles check-in when you finish.", systemImage: "figure.walk.motion")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await start() }
                } label: {
                    Label("Start session", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("basketball.start")
            }
        }
    }

    @ViewBuilder
    private func content(session: BasketballSession, service: BasketballService) -> some View {
        Form {
            Section("Session") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Image(systemName: "basketball.fill").foregroundStyle(.orange)
                        Text(formatDuration(context.date.timeIntervalSince(startedAt)))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Text("Live")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }

            if let liveMetrics {
                LiveWorkoutStatsSection(metrics: liveMetrics)
            }

            Section("Hydration during session") {
                Stepper("\(Int(hydrationOz)) oz", value: $hydrationOz, in: 0...300, step: 8)
            }

            if achillesCheckInEnabled {
                Section("Achilles check-in (1-10)") {
                    HStack {
                        Text("Score").foregroundStyle(.secondary).font(.subheadline)
                        Spacer()
                        Picker("", selection: $achillesScore) {
                            ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await endWorkout(session: session, service: service) }
                } label: {
                    Label("End session", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Lifecycle

    /// Adopts an in-progress session (user navigated away mid-game) without
    /// starting a new one. Fresh sessions wait for the Start button.
    private func resumeIfActive() {
        guard session == nil else { return }
        let svc = BasketballService(modelContext: modelContext, healthKit: LiveHealthKitService.shared)
        if let active = svc.currentSession(at: Date()) {
            session = active
            service = svc
            startedAt = active.startTime
            beginLiveMetrics(from: active.startTime)
        } else {
            service = svc
        }
    }

    private func start() async {
        let svc = service ?? BasketballService(modelContext: modelContext, healthKit: LiveHealthKitService.shared)
        do {
            let s = try svc.startSession(at: Date())
            startedAt = Date()
            session = s
            service = svc
            beginLiveMetrics(from: startedAt)
            _ = await WorkoutLiveActivityController.start(workoutType: "Basketball", startDate: startedAt)
        } catch {
            // Logged inside service.
        }
    }

    private func beginLiveMetrics(from start: Date) {
        let metrics = LiveWorkoutMetrics(
            healthKit: LiveHealthKitService.shared,
            sessionStart: start,
            activityType: .basketball
        )
        metrics.begin()
        liveMetrics = metrics
    }

    private func endWorkout(session: BasketballSession, service: BasketballService) async {
        let end = Date()
        // Prefer HealthKit-measured energy for the Health workout row; fall
        // back to a MET estimate from body weight for phone-only sessions.
        await liveMetrics?.refreshOnce()
        let elapsedMinutes = end.timeIntervalSince(startedAt) / 60
        let kcal = liveMetrics?.closingKcal(
            met: WorkoutMetrics.met(for: .basketball),
            weightLbs: profiles.first?.weightLbs,
            elapsedMinutes: elapsedMinutes
        )
        do {
            try service.endSession(session,
                                          endTime: end,
                                          achillesPostScore: achillesCheckInEnabled ? achillesScore : nil,
                                          hydrationOz: hydrationOz,
                                          estimatedCalories: kcal)
            liveMetrics?.end()
            await WorkoutLiveActivityController.endAll()
            ended = true
            LogFeedbackCenter.shared.confirm(IdentityCopy.workoutLogged)
            dismiss()
        } catch {
            // Logged inside service.
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
