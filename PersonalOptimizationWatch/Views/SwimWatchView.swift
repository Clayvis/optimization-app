import SwiftUI
import SwiftData
import WatchKit

struct SwimWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var session: SwimSession?
    @State private var service: SwimService?
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                ProgressView().task { start() }
            }
        }
        .navigationTitle("Swim")
    }

    @ViewBuilder
    private func content(session: SwimSession, service: SwimService) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 2) {
                        Text(formatDuration(context.date.timeIntervalSince(startedAt)))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("\(session.laps) laps · \(Int(session.totalMeters)) m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    // try? justified: SwiftData local write.
                    _ = try? service.logLap(in: session, count: 1)
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Label("+1 lap", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)

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
        let svc = SwimService(modelContext: modelContext)
        do {
            session = try svc.startSession(at: Date(), poolLengthMeters: 25, location: "McTureous")
            service = svc
            startedAt = Date()
        } catch {
            // logged inside service
        }
    }

    private func end(service: SwimService, session: SwimSession) async {
        let mins = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        do {
            try service.endSession(session, durationMinutes: mins)
            WKInterfaceDevice.current().play(.success)
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
