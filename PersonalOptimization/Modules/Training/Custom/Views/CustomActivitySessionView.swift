import SwiftUI
import SwiftData
import HealthKit

/// Live session view for a user-defined activity. Prep screen with an
/// explicit Start (mirrors Lift/Swim/Basketball), live timer plus Apple
/// Health metrics while running, end button that writes duration + optional
/// distance + intensity + measured-or-estimated calories.
@MainActor
struct CustomActivitySessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    let template: CustomActivityTemplate
    var suggestedDurationMinutes: Int? = nil
    var startsImmediately = false

    @State private var service: CustomActivityService?
    @State private var session: CustomActivitySession?
    @State private var startedAt = Date()
    @State private var durationMinutes: Int = 0
    @State private var distanceMeters: Double = 0
    @State private var intensity: String = "moderate"
    @State private var notes: String = ""
    @State private var completionCount: Int = 0
    @State private var liveMetrics: LiveWorkoutMetrics?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var detailsExpanded = false
    @State private var endedAt: Date?

    private let intensities = ["easy", "moderate", "hard"]

    private var hkActivityType: HKWorkoutActivityType {
        WorkoutMetrics.hkActivityType(forTemplateNamed: template.name)
    }

    var body: some View {
        Group {
            if let session, let service {
                liveContent(session: session, service: service)
            } else {
                readyContent
            }
        }
        .navigationTitle(template.name)
        .task {
            resumeIfActive()
            if startsImmediately && session == nil { start() }
        }
        .onDisappear { liveMetrics?.end() }
        .sensoryFeedback(.success, trigger: completionCount)
        .safeAreaInset(edge: .top) {
            if let errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Ready state

    @ViewBuilder
    private var readyContent: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: template.systemImageName)
                        .font(.title)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.headline)
                        Text(readySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if hkActivityType != .other {
                    LastWorkoutRecapRow(activityTypes: [hkActivityType])
                }
            }

            Section {
                Button {
                    start()
                } label: {
                    Label("Start session", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("customActivity.start")
            }
        }
    }

    private var readySubtitle: String {
        var parts = ["\(suggestedDurationMinutes ?? template.defaultDurationMinutes) min goal · save the time you actually do"]
        if template.trackDistance { parts.append("tracks distance") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Live state

    @ViewBuilder
    private func liveContent(session: CustomActivitySession, service: CustomActivityService) -> some View {
        Form {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Image(systemName: template.systemImageName)
                            .foregroundStyle(.tint)
                        Text(formatDuration((endedAt ?? context.date).timeIntervalSince(startedAt)))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Text(endedAt == nil ? "LIVE" : "FINISHED")
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

            Section {
                Text("Aim for \(suggestedDurationMinutes ?? template.defaultDurationMinutes) minutes. A shorter session counts too.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    // Set before the first await to close the double-tap window.
                    guard !isSaving else { return }
                    isSaving = true
                    if endedAt == nil { endedAt = Date() }
                    Task { await end(service: service, session: session) }
                } label: {
                    Label(isSaving ? "Saving…" : "Finish & save", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
                .accessibilityIdentifier("customActivity.finish")
                Text("Elapsed time saves automatically. Details are optional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup("Add or adjust details", isExpanded: $detailsExpanded) {
                    Stepper(durationMinutes == 0 ? "Duration: automatic" : "\(durationMinutes) min",
                            value: $durationMinutes, in: 0...360)
                    if durationMinutes > 0 {
                        Button("Use elapsed time") { durationMinutes = 0 }
                    }

                    if template.trackDistance {
                        VStack(alignment: .leading) {
                            HStack {
                                TextField("Meters", value: $distanceMeters, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.leading)
                                Text("m").foregroundStyle(.secondary)
                            }
                            Stepper("Step by 100 m", value: $distanceMeters, in: 0...100_000, step: 100)
                                .labelsHidden()
                            if let measured = liveMetrics?.distanceMeters, measured > 50 {
                                Button("Use Apple Health (\(WorkoutMetrics.milesText(meters: measured)))") {
                                    distanceMeters = measured.rounded()
                                }
                            }
                        }
                    }

                    Picker("Intensity", selection: $intensity) {
                        ForEach(intensities, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
        }
    }

    private var elapsedMinutes: Int {
        max(1, Int((endedAt ?? Date()).timeIntervalSince(startedAt) / 60))
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    // MARK: - Lifecycle

    /// Adopts an in-progress session; fresh ones wait for the Start button.
    private func resumeIfActive() {
        guard session == nil else { return }
        let svc = CustomActivityService(modelContext: modelContext, healthKit: LiveHealthKitService.shared)
        if let active = svc.currentSession(for: template) {
            service = svc
            session = active
            startedAt = active.date
            durationMinutes = 0
            beginLiveMetrics(from: active.date)
        } else {
            service = svc
        }
    }

    private func start() {
        let svc = service ?? CustomActivityService(modelContext: modelContext, healthKit: LiveHealthKitService.shared)
        do {
            let s = try svc.startSession(for: template)
            service = svc
            session = s
            startedAt = s.date
            durationMinutes = 0
            errorMessage = nil
            beginLiveMetrics(from: startedAt)
        } catch {
            errorMessage = "Couldn't start your workout. \(error.localizedDescription)"
        }
    }

    private func beginLiveMetrics(from start: Date) {
        let metrics = LiveWorkoutMetrics(
            healthKit: LiveHealthKitService.shared,
            sessionStart: start,
            activityType: hkActivityType
        )
        metrics.begin()
        liveMetrics = metrics
    }

    private func end(service: CustomActivityService, session: CustomActivitySession) async {
        defer { isSaving = false }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        // Save with the latest observed metrics. Waiting for another Health
        // query here can strand Finish & save when the Health daemon stalls.
        let minutes = durationMinutes == 0 ? elapsedMinutes : durationMinutes
        let kcal = liveMetrics?.closingKcal(
            met: WorkoutMetrics.met(forTemplateNamed: template.name),
            weightLbs: profiles.first?.weightLbs,
            elapsedMinutes: Double(minutes)
        )
        // Manual entry wins; otherwise take the HealthKit-measured distance.
        var meters: Double?
        if template.trackDistance {
            if distanceMeters > 0 {
                meters = distanceMeters
            } else if let measured = liveMetrics?.distanceMeters, measured > 50 {
                meters = measured.rounded()
            }
        }
        do {
            try service.endSession(
                session,
                durationMinutes: minutes,
                distanceMeters: meters,
                intensity: intensity,
                caloriesKcal: kcal,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            liveMetrics?.end()
            completionCount &+= 1
            LogFeedbackCenter.shared.confirm(IdentityCopy.workoutLogged)
            dismiss()
        } catch {
            errorMessage = "Your workout hasn't saved yet. Try Finish & save again. \(error.localizedDescription)"
        }
    }
}
