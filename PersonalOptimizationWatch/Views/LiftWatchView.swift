import SwiftUI
import SwiftData
import WatchKit

struct LiftWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let templateName: String

    @State private var session: LiftSession?
    @State private var service: LiftService?
    @State private var startedAt = Date()
    @State private var currentExerciseIndex = 0
    /// Live workout driver. Provides HR + kcal + elapsed when HK is granted;
    /// session view keeps working when it isn't (HR/kcal just stay 0).
    @State private var live = LiveWorkoutSessionService.shared

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                ProgressView().task { start() }
            }
        }
        .navigationTitle(templateName)
    }

    @ViewBuilder
    private func content(session: LiftSession, service: LiftService) -> some View {
        let exercises = (session.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        let active = exercises.indices.contains(currentExerciseIndex) ? exercises[currentExerciseIndex] : nil

        ScrollView {
            VStack(spacing: 8) {
                liveStatsRow
                if let active {
                    Text(active.name).font(.headline)
                    let sets = (active.sets ?? []).sorted { $0.orderIndex < $1.orderIndex }
                    Text("\(sets.count) sets logged").font(.caption2).foregroundStyle(.secondary)

                    Button {
                        // try? justified: SwiftData local write.
                        _ = try? service.logSet(in: session, exerciseName: active.name, weightLbs: 135, reps: 5, restSeconds: 90)
                        WKInterfaceDevice.current().play(.success)
                    } label: {
                        Label("+ Set 135x5", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack {
                    Button {
                        if currentExerciseIndex > 0 { currentExerciseIndex -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text("\(currentExerciseIndex + 1) / \(exercises.count)").font(.caption2)
                    Spacer()
                    Button {
                        if currentExerciseIndex < exercises.count - 1 { currentExerciseIndex += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }

                Button(role: .destructive) {
                    Task { await end(service: service, session: session) }
                } label: {
                    Label("End", systemImage: "stop.circle")
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// Live HR + kcal + elapsed from the active HK session. When HK isn't
    /// authorized or a session never started (e.g. M3.7 hardware-less unit
    /// tests), the values stay at 0 and the row reads as a clean placeholder
    /// instead of crashing.
    @ViewBuilder
    private var liveStatsRow: some View {
        if live.isActive {
            HStack(spacing: 6) {
                Label("\(Int(live.heartRate))", systemImage: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption2.monospacedDigit())
                Spacer()
                Label("\(Int(live.activeCaloriesKcal))", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2.monospacedDigit())
                Spacer()
                Text(formatDuration(live.elapsedSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func start() {
        do {
            let templates = try LiftTemplatesLoader.load()
            let svc = LiftService(modelContext: modelContext, templatesFile: templates)
            session = try svc.startSession(templateName: templateName)
            service = svc
            startedAt = Date()
            // Best-effort: start the live HK session for HR + kcal. Failure
            // here doesn't block the lift session — SwiftData remains the
            // truth (M3.6 architecture) and HK is secondary.
            try? live.start(activityType: .functionalStrengthTraining)
            WatchConnectivityService.shared.send(
                WatchConnectivityEvent(kind: .workoutStarted,
                                       payload: ["type": "lift", "template": templateName])
            )
        } catch {
            // logged inside service
        }
    }

    private func end(service: LiftService, session: LiftSession) async {
        let summary = await live.end()
        let mins = max(1, summary?.durationMinutes ?? Int(Date().timeIntervalSince(startedAt) / 60))
        do {
            try service.endSession(session,
                                   durationMinutes: mins,
                                   avgHR: summary?.avgHeartRate,
                                   estimatedCalories: summary?.activeCaloriesKcal)
            WKInterfaceDevice.current().play(.success)
            WatchConnectivityService.shared.send(
                WatchConnectivityEvent(kind: .workoutEnded,
                                       payload: ["type": "lift", "minutes": "\(mins)"])
            )
            dismiss()
        } catch {
            // logged inside service
        }
    }
}
