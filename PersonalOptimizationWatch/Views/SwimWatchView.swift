import SwiftUI
import SwiftData
import WatchKit

struct SwimWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLuminanceReduced) private var dimmed

    @State private var session: SwimSession?
    @State private var service: SwimService?
    @State private var startedAt = Date()
    @State private var live = LiveWorkoutSessionService.shared

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                ProgressView().task { start() }
            }
        }
        .navigationTitle("Swim")
        .foregroundStyle(dimmed ? .secondary : .primary)
        .animation(.easeInOut(duration: 0.5), value: dimmed)
    }

    @ViewBuilder
    private func content(session: SwimSession, service: SwimService) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                if live.isActive {
                    HStack(spacing: 6) {
                        Label("\(Int(live.heartRate))", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                            .font(.caption2.monospacedDigit())
                            .accessibilityHidden(true)
                        Spacer()
                        Label("\(Int(live.activeCaloriesKcal))", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2.monospacedDigit())
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized:
                        "Heart rate \(Int(live.heartRate)), \(Int(live.activeCaloriesKcal)) calories burned"
                    ))
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 2) {
                        Text(formatDuration(context.date.timeIntervalSince(startedAt)))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("\(session.laps) laps · \(Int(session.totalMeters)) m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized:
                        "Elapsed \(formatDuration(context.date.timeIntervalSince(startedAt))), \(session.laps) laps, \(Int(session.totalMeters)) meters"
                    ))
                }

                Button {
                    // MARK: - try? justified because SwiftData local write;
                    // failure path is unrecoverable corruption rather than a
                    // user error. Haptic still confirms the tap.
                    _ = try? service.logLap(in: session, count: 1)
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Label("+1 lap", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(String(localized: "Add one lap"))
                .accessibilityHint(String(localized: "Increments lap count by one"))

                Button(role: .destructive) {
                    Task { await end(service: service, session: session) }
                } label: {
                    Label("End", systemImage: "stop.circle")
                }
                .accessibilityLabel(String(localized: "End swim session"))
                .accessibilityHint(String(localized: "Saves the session and returns home"))
            }
            .padding(.horizontal, 4)
        }
    }

    private func start() {
        let svc = SwimService(modelContext: modelContext)
        do {
            session = try svc.startSession(at: Date(), poolLengthMeters: 25, location: "McTureous")
            service = svc
            startedAt = Date()
            try? live.start(activityType: .swimming, locationType: .indoor)
            WatchConnectivityService.shared.send(
                WatchConnectivityEvent(kind: .workoutStarted, payload: ["type": "swim"])
            )
        } catch {
            // logged inside service
        }
    }

    private func end(service: SwimService, session: SwimSession) async {
        let summary = await live.end()
        let mins = max(1, summary?.durationMinutes ?? Int(Date().timeIntervalSince(startedAt) / 60))
        do {
            try service.endSession(session,
                                   durationMinutes: mins,
                                   avgHR: summary?.avgHeartRate,
                                   estimatedCalories: summary?.activeCaloriesKcal)
            WKInterfaceDevice.current().play(.success)
            WatchConnectivityService.shared.send(
                WatchConnectivityEvent(kind: .workoutEnded, payload: ["type": "swim"])
            )
            dismiss()
        } catch {
            // logged inside service
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
