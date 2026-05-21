import SwiftUI
import SwiftData
import WatchKit
import HealthKit

/// Watch live session for a user-defined activity template (Running, HIIT,
/// Yoga, etc). Mirrors the LiftWatchView pattern: live HR/kcal/elapsed at
/// the top, in-session controls, end button persists into
/// `CustomActivitySession` + writes the workout-event ledger.
@MainActor
struct CustomActivityWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLuminanceReduced) private var dimmed
    let template: CustomActivityTemplate

    @State private var session: CustomActivitySession?
    @State private var service: CustomActivityService?
    @State private var startedAt = Date()
    @State private var live = LiveWorkoutSessionService.shared
    @State private var distanceMeters: Double = 0
    @State private var intensity: String = "moderate"

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                ProgressView().task { start() }
            }
        }
        .navigationTitle(template.name)
        .foregroundStyle(dimmed ? .secondary : .primary)
        .animation(.easeInOut(duration: 0.5), value: dimmed)
    }

    @ViewBuilder
    private func content(session: CustomActivitySession, service: CustomActivityService) -> some View {
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

                if template.trackDistance {
                    HStack {
                        Text("\(Int(live.distanceMeters)) m")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "Distance"))
                            .accessibilityValue(String(localized: "\(Int(live.distanceMeters)) meters"))
                        Spacer()
                    }
                }

                Picker("Intensity", selection: $intensity) {
                    Text("Easy").tag("easy")
                    Text("Moderate").tag("moderate")
                    Text("Hard").tag("hard")
                }
                .pickerStyle(.navigationLink)
                .font(.caption2)
                .accessibilityLabel(String(localized: "Workout intensity"))
                .accessibilityValue(intensity)

                Button(role: .destructive) {
                    Task { await end(service: service, session: session) }
                } label: {
                    Label("End", systemImage: "stop.circle")
                }
                .accessibilityLabel(String(localized: "End \(template.name) session"))
                .accessibilityHint(String(localized: "Saves the session and returns home"))
            }
            .padding(.horizontal, 4)
        }
    }

    private func start() {
        let svc = CustomActivityService(modelContext: modelContext)
        do {
            session = try svc.startSession(for: template)
            service = svc
            startedAt = Date()
            try? live.start(activityType: hkActivityType, locationType: locationType)
            WatchConnectivityService.shared.send(
                WatchConnectivityEvent(kind: .workoutStarted,
                                       payload: ["type": "custom", "template": template.name])
            )
        } catch {
            // logged inside service
        }
    }

    private func end(service: CustomActivityService, session: CustomActivitySession) async {
        let summary = await live.end()
        let mins = max(1, summary?.durationMinutes ?? Int(Date().timeIntervalSince(startedAt) / 60))
        do {
            try service.endSession(
                session,
                durationMinutes: mins,
                distanceMeters: template.trackDistance ? (summary?.distanceMeters ?? live.distanceMeters) : nil,
                intensity: intensity,
                avgHR: summary?.avgHeartRate,
                caloriesKcal: summary?.activeCaloriesKcal,
                notes: nil
            )
            WKInterfaceDevice.current().play(.success)
            WatchConnectivityService.shared.send(
                WatchConnectivityEvent(kind: .workoutEnded,
                                       payload: ["type": "custom", "template": template.name])
            )
            dismiss()
        } catch {
            // logged inside service
        }
    }

    /// Map a custom template name to the closest HK activity type. Defaults to
    /// `.other` which is HK's catch-all and avoids a wrong-icon situation in
    /// the workout summary screen.
    private var hkActivityType: HKWorkoutActivityType {
        let name = template.name.lowercased()
        if name.contains("run") { return .running }
        if name.contains("walk") { return .walking }
        if name.contains("hik") { return .hiking }
        if name.contains("cycle") || name.contains("bike") { return .cycling }
        if name.contains("yoga") { return .yoga }
        if name.contains("hiit") { return .highIntensityIntervalTraining }
        if name.contains("dance") { return .socialDance }
        if name.contains("box") { return .boxing }
        if name.contains("martial") { return .martialArts }
        return .other
    }

    private var locationType: HKWorkoutSessionLocationType {
        let name = template.name.lowercased()
        if name.contains("run") || name.contains("walk") || name.contains("hik") || name.contains("cycle") {
            return .outdoor
        }
        return .indoor
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
