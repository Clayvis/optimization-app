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

    private func start() {
        do {
            let templates = try LiftTemplatesLoader.load()
            let svc = LiftService(modelContext: modelContext, templatesFile: templates)
            session = try svc.startSession(templateName: templateName)
            service = svc
            startedAt = Date()
        } catch {
            // logged inside service
        }
    }

    private func end(service: LiftService, session: LiftSession) async {
        let mins = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        do {
            try await service.endSession(session, durationMinutes: mins)
            WKInterfaceDevice.current().play(.success)
            dismiss()
        } catch {
            // logged inside service
        }
    }
}
