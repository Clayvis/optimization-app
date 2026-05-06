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
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(formatDuration(context.date.timeIntervalSince(startedAt)))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }

                Stepper("\(Int(hydration)) oz", value: $hydration, in: 0...300, step: 8)
                    .font(.caption)

                Picker("Achilles", selection: $achilles) {
                    ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
                }
                .font(.caption2)

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
        let svc = BasketballService(modelContext: modelContext)
        do {
            session = try svc.startSession(at: Date())
            service = svc
            startedAt = Date()
        } catch {
            // logged inside service
        }
    }

    private func end(service: BasketballService, session: BasketballSession) async {
        let end = Date()
        do {
            try service.endSession(session, endTime: end, achillesPostScore: achilles, hydrationOz: hydration)
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
