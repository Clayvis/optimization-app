import SwiftUI
import SwiftData

/// Live session view for a user-defined activity. Mirrors the Lift/Swim/
/// Basketball pattern — start on appear (or resume), live timer, end button
/// that writes duration + optional distance + intensity.
@MainActor
struct CustomActivitySessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let template: CustomActivityTemplate

    @State private var service: CustomActivityService?
    @State private var session: CustomActivitySession?
    @State private var startedAt = Date()
    @State private var durationMinutes: Int = 0
    @State private var distanceMeters: Double = 0
    @State private var intensity: String = "moderate"
    @State private var notes: String = ""
    @State private var completionCount: Int = 0

    private let intensities = ["easy", "moderate", "hard"]

    var body: some View {
        Group {
            if let session, let service {
                liveContent(session: session, service: service)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(template.name)
        .task { await startOrResume() }
        .sensoryFeedback(.success, trigger: completionCount)
    }

    @ViewBuilder
    private func liveContent(session: CustomActivitySession, service: CustomActivityService) -> some View {
        Form {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Image(systemName: template.systemImageName)
                            .foregroundStyle(.tint)
                        Text(formatDuration(context.date.timeIntervalSince(startedAt)))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Text("LIVE")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }

            Section("Duration") {
                Stepper("\(durationMinutes) min", value: $durationMinutes, in: 0...360, step: 5)
                Button("Use elapsed (\(elapsedMinutes) min)") {
                    durationMinutes = elapsedMinutes
                }
            }

            if template.trackDistance {
                Section("Distance") {
                    HStack {
                        TextField("Meters", value: $distanceMeters, format: .number)
                            .keyboardType(.decimalPad)
                        Text("m").foregroundStyle(.secondary)
                    }
                    Stepper("Step by 100 m", value: $distanceMeters, in: 0...100_000, step: 100)
                        .labelsHidden()
                }
            }

            Section("Intensity") {
                Picker("Intensity", selection: $intensity) {
                    ForEach(intensities, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section {
                Button(role: .destructive) {
                    end(service: service, session: session)
                } label: {
                    Label("End session", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var elapsedMinutes: Int {
        max(1, Int(Date().timeIntervalSince(startedAt) / 60))
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func startOrResume() async {
        let svc = CustomActivityService(modelContext: modelContext)
        if let active = svc.currentSession(for: template) {
            service = svc
            session = active
            startedAt = active.date
            return
        }
        do {
            let s = try svc.startSession(for: template)
            service = svc
            session = s
            startedAt = Date()
            durationMinutes = template.defaultDurationMinutes
        } catch {
            // Logged in service.
        }
    }

    private func end(service: CustomActivityService, session: CustomActivitySession) {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        do {
            try service.endSession(
                session,
                durationMinutes: durationMinutes == 0 ? elapsedMinutes : durationMinutes,
                distanceMeters: template.trackDistance && distanceMeters > 0 ? distanceMeters : nil,
                intensity: intensity,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            completionCount &+= 1
            LogFeedbackCenter.shared.confirm(IdentityCopy.workoutLogged)
            dismiss()
        } catch {
            // Logged in service.
        }
    }
}
