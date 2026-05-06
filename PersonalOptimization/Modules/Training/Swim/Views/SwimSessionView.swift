import SwiftUI
import SwiftData

struct SwimSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var session: SwimSession?
    @State private var service: SwimService?
    @State private var startedAt = Date()
    @State private var poolLengthMeters: Double = 25
    @State private var location: String = "McTureous"

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                setupContent
            }
        }
        .navigationTitle("Swim")
    }

    @ViewBuilder
    private var setupContent: some View {
        Form {
            Section("Pool") {
                Picker("Pool length", selection: $poolLengthMeters) {
                    Text("25 m").tag(25.0)
                    Text("50 m").tag(50.0)
                }
                .pickerStyle(.segmented)
                Picker("Location", selection: $location) {
                    Text("McTureous").tag("McTureous")
                    Text("Hansen").tag("Hansen")
                }
            }
            Section {
                Button {
                    start()
                } label: {
                    Label("Start session", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func content(session: SwimSession, service: SwimService) -> some View {
        Form {
            Section("Session") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Image(systemName: "figure.pool.swim").foregroundStyle(.cyan)
                        Text(formatDuration(context.date.timeIntervalSince(startedAt)))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Text("\(session.laps) laps · \(Int(session.totalMeters)) m")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }

            Section {
                Button {
                    // try? justified: SwiftData local write, see overall pattern.
                    _ = try? service.logLap(in: session, count: 1)
                } label: {
                    Label("+1 lap", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Section {
                Button(role: .destructive) {
                    Task { await end(service: service, session: session) }
                } label: {
                    Label("End session", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func start() {
        let svc = SwimService(modelContext: modelContext, healthKit: LiveHealthKitService.shared)
        do {
            let s = try svc.startSession(at: Date(), poolLengthMeters: poolLengthMeters, location: location)
            startedAt = Date()
            session = s
            service = svc
        } catch {
            // logged inside service
        }
    }

    private func end(service: SwimService, session: SwimSession) async {
        let mins = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        do {
            try await service.endSession(session, durationMinutes: mins)
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
