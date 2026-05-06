import SwiftUI
import SwiftData

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

    private var achillesCheckInEnabled: Bool {
        profiles.first?.achillesCheckInEnabled ?? true
    }

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Basketball")
        .task { await start() }
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

    private func start() async {
        let svc = BasketballService(modelContext: modelContext, healthKit: LiveHealthKitService.shared)
        do {
            let s = try svc.startSession(at: Date())
            startedAt = Date()
            session = s
            service = svc
            _ = await WorkoutLiveActivityController.start(workoutType: "Basketball", startDate: startedAt)
        } catch {
            // Logged inside service.
        }
    }

    private func endWorkout(session: BasketballSession, service: BasketballService) async {
        let end = Date()
        do {
            try service.endSession(session,
                                          endTime: end,
                                          achillesPostScore: achillesCheckInEnabled ? achillesScore : nil,
                                          hydrationOz: hydrationOz)
            await WorkoutLiveActivityController.endAll()
            ended = true
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
