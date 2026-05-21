import SwiftUI
import SwiftData
import WatchKit

struct HydrationWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var service: HydrationService?
    @State private var refreshTrigger = 0
    @State private var loadError: String?

    private let bottleSizes: [Double] = [8, 16, 24, 32]

    var body: some View {
        ScrollView {
            content
        }
        .task { await loadService() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            Text(error).font(.footnote).foregroundStyle(.secondary).padding()
        } else if let service {
            mainContent(service: service)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func mainContent(service: HydrationService) -> some View {
        let now = Date()
        let intake = service.intakeForDay(of: now)
        let target = service.targetRange(for: now)
        let dayType = service.dayType(for: now)

        VStack(spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Text("\(Int(intake))").font(.title2.weight(.bold)).monospacedDigit()
                Text("oz").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(target.lowerBound))-\(Int(target.upperBound))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(intake / target.upperBound, 1.0))
                .tint(progressTint(intake: intake, target: target))
            Text(dayType.rawValue.capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(bottleSizes, id: \.self) { oz in
                Button {
                    log(oz: oz, service: service)
                } label: {
                    HStack {
                        Image(systemName: "drop.fill").foregroundStyle(.tint)
                        Text("\(Int(oz)) oz").font(.body.weight(.semibold))
                        Spacer()
                    }
                    .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Log \(Int(oz)) ounces of water")
            }

            Button {
                logElectrolyte(service: service)
            } label: {
                HStack {
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                    Text("Electrolyte").font(.body.weight(.semibold))
                    Spacer()
                }
                .frame(height: 38)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Log an electrolyte session")
        }
        .padding(.horizontal, 4)
        .id(refreshTrigger)
    }

    private func log(oz: Double, service: HydrationService) {
        // MARK: - try? justified because SwiftData write to in-process
        // container, failure path is unrecoverable corruption rather than a
        // recoverable user error; the haptic still fires to confirm tap.
        _ = try? service.logBottle(oz: oz)
        WKInterfaceDevice.current().play(.success)
        // Real-time signal to the phone so the iOS UI updates within seconds
        // instead of waiting on CloudKit propagation. Persisted SwiftData
        // row + CloudKit sync remain the source of truth.
        WatchConnectivityService.shared.send(
            WatchConnectivityEvent(
                kind: .waterLogged,
                payload: ["oz": "\(Int(oz))"]
            )
        )
        refreshTrigger += 1
    }

    private func logElectrolyte(service: HydrationService) {
        // MARK: - try? justified because the failure path mirrors logBottle.
        _ = try? service.logElectrolyte()
        WKInterfaceDevice.current().play(.success)
        WatchConnectivityService.shared.send(
            WatchConnectivityEvent(
                kind: .waterLogged,
                payload: ["type": "electrolyte"]
            )
        )
        refreshTrigger += 1
    }

    private func progressTint(intake: Double, target: ClosedRange<Double>) -> Color {
        if intake >= target.lowerBound { return .green }
        if intake >= target.lowerBound * 0.5 { return .yellow }
        return .orange
    }

    private func loadService() async {
        do {
            let config = try ScheduleConfigLoader.load()
            service = HydrationService(modelContext: modelContext, targets: config.hydrationTargetsOz)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
