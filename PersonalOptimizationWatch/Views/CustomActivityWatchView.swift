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
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var finishedSummary: LiveSessionSummary?
    @State private var finishedMinutes: Int?

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else if let errorMessage {
                VStack {
                    Text(errorMessage).font(.caption)
                    Button("Retry start") { start() }
                }
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
                if let errorMessage {
                    Text(errorMessage).font(.caption2).foregroundStyle(.orange)
                }
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

                // V11 always-on polish: 60s tick when dimmed, 1Hz otherwise.
                TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { context in
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
                .accessibilityHint(String(localized: "Choose easy, moderate, or hard effort"))

                Button {
                    guard !isSaving else { return }
                    isSaving = true
                    Task { await end(service: service, session: session) }
                } label: {
                    Label(isSaving ? "Saving" : "Finish & save", systemImage: "checkmark.circle")
                }
                .disabled(isSaving)
                .accessibilityLabel(String(localized: "End \(template.name) session"))
                .accessibilityHint(String(localized: "Saves the session and returns home"))
            }
            .padding(.horizontal, 4)
        }
    }

    private func start() {
        let svc = CustomActivityService(modelContext: modelContext)
        do {
            let active = try svc.startSession(for: template)
            session = active
            service = svc
            startedAt = active.date
            errorMessage = nil
            if !live.isActive {
                do { try live.start(activityType: hkActivityType, locationType: locationType) }
                catch { errorMessage = "Live metrics unavailable. Your session timer is running." }
            }
            // V11 Handoff parity: phone Lock Screen banner names the template.
            _ = HandoffService.startActivity(type: .customActivity, template: template.name)
            WatchConnectivityService.shared.send(
                WatchConnectivityEvent(kind: .workoutStarted,
                                       payload: ["type": "custom", "template": template.name])
            )
        } catch {
            errorMessage = "Couldn't start. Please try again."
        }
    }

    private func end(service: CustomActivityService, session: CustomActivitySession) async {
        defer { isSaving = false }
        if finishedMinutes == nil {
            finishedSummary = await live.end()
            finishedMinutes = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        }
        let summary = finishedSummary
        let mins = finishedMinutes ?? 1
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
            errorMessage = "Not saved yet. Tap Finish & save to retry."
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
