import SwiftUI
import SwiftData
import WatchKit

struct BasketballWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var session: BasketballSession?
    @State private var service: BasketballService?
    @State private var startedAt = Date()
    @State private var hydration: Double = 0
    @State private var achilles: Int = 5
    @State private var live = LiveWorkoutSessionService.shared

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                ProgressView().task { start() }
            }
        }
        .navigationTitle("Basketball")
    }

    @ViewBuilder
    private func content(session: BasketballSession, service: BasketballService) -> some View {
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
                    Text(formatDuration(context.date.timeIntervalSince(startedAt)))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityLabel(String(localized: "Elapsed time"))
                        .accessibilityValue(formatDuration(context.date.timeIntervalSince(startedAt)))
                }

                Stepper("\(Int(hydration)) oz", value: $hydration, in: 0...300, step: 8)
                    .font(.caption)
                    .accessibilityLabel(String(localized: "Water intake during session"))
                    .accessibilityValue(String(localized: "\(Int(hydration)) ounces"))

                Picker("Achilles", selection: $achilles) {
                    ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
                }
                .font(.caption2)
                .accessibilityLabel(String(localized: "Achilles pain rating"))
                .accessibilityValue(String(localized: "\(achilles) out of 10"))

                Button(role: .destructive) {
                    Task { await end(service: service, session: session) }
                } label: {
                    Label("End", systemImage: "stop.circle")
                }
                .accessibilityLabel(String(localized: "End basketball session"))
                .accessibilityHint(String(localized: "Saves the session and returns home"))
            }
            .padding(.horizontal, 4)
        }
    }

    private func start() {
        let svc = BasketballService(modelContext: modelContext)
        do {
            session = try svc.startSession(at: Date())
            service = svc
            startedAt = Date()
            try? live.start(activityType: .basketball, locationType: .indoor)
            WatchConnectivityService.shared.send(
                WatchConnectivityEvent(kind: .workoutStarted, payload: ["type": "basketball"])
            )
        } catch {
            // logged inside service
        }
    }

    private func end(service: BasketballService, session: BasketballSession) async {
        let end = Date()
        let summary = await live.end()
        do {
            try service.endSession(session,
                                   endTime: end,
                                   achillesPostScore: achilles,
                                   hydrationOz: hydration,
                                   estimatedCalories: summary?.activeCaloriesKcal)
            WKInterfaceDevice.current().play(.success)
            WatchConnectivityService.shared.send(
                WatchConnectivityEvent(kind: .workoutEnded, payload: ["type": "basketball"])
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
