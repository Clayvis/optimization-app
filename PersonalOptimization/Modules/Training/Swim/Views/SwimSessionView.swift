import SwiftUI
import SwiftData

struct SwimSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var session: SwimSession?
    @State private var service: SwimService?
    @State private var startedAt = Date()

    @State private var poolLengthMeters: Double = 25
    @State private var locationText: String = ""
    @State private var waterType: SwimWaterType = .pool

    @State private var lapsExact: Int = 0
    @State private var metersExact: Double = 0
    @State private var completionCount: Int = 0

    var body: some View {
        Group {
            if let session, let service {
                content(session: session, service: service)
            } else {
                setupContent
            }
        }
        .navigationTitle("Swim")
        .task { resumeIfNeeded() }
        .sensoryFeedback(.success, trigger: completionCount)
    }

    /// Resume an in-progress swim session that the user navigated away from.
    private func resumeIfNeeded() {
        guard session == nil else { return }
        let svc = SwimService(modelContext: modelContext, healthKit: LiveHealthKitService.shared)
        if let active = svc.currentSession(at: Date()) {
            session = active
            service = svc
            startedAt = active.date
            poolLengthMeters = active.poolLengthMeters
            locationText = active.location ?? ""
            waterType = active.waterType
            lapsExact = active.laps
            metersExact = active.totalMeters
        }
    }

    @ViewBuilder
    private var setupContent: some View {
        Form {
            Section("Where") {
                Picker("Water type", selection: $waterType) {
                    ForEach(SwimWaterType.allCases, id: \.rawValue) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Location", text: $locationText)
                    .autocapitalization(.words)
                    .accessibilityLabel("Location")

                let recents = recentLocations()
                if !recents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recents, id: \.self) { name in
                                Button {
                                    locationText = name
                                } label: {
                                    Text(name)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(.tertiarySystemBackground))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .accessibilityLabel("Recent locations")
                }
            }

            if waterType == .pool {
                Section("Pool length") {
                    Stepper(value: $poolLengthMeters, in: 10...100, step: 5) {
                        Text("\(Int(poolLengthMeters)) m")
                    }
                    .accessibilityValue("\(Int(poolLengthMeters)) meters")
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
                        Text("\(session.laps) lap\(session.laps == 1 ? "" : "s") · \(Int(session.totalMeters)) m")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }

            if session.waterType == .pool {
                poolEntrySection(session: session, service: service)
            } else {
                openWaterEntrySection(session: session, service: service)
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

    @ViewBuilder
    private func poolEntrySection(session: SwimSession, service: SwimService) -> some View {
        Section("Add laps") {
            HStack(spacing: 8) {
                ForEach([1, 2, 5, 10], id: \.self) { count in
                    Button {
                        _ = try? service.logLap(in: session, count: count)
                    } label: {
                        Text("+\(count)")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(count) lap\(count == 1 ? "" : "s")")
                }
            }
        }

        Section("Set exact laps") {
            HStack {
                Stepper("Laps: \(lapsExact)", value: $lapsExact, in: 0...500)
                Button("Set") {
                    _ = try? service.setExactLaps(in: session, laps: lapsExact)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func openWaterEntrySection(session: SwimSession, service: SwimService) -> some View {
        Section("Add meters") {
            HStack(spacing: 8) {
                ForEach([100.0, 250.0, 500.0, 1000.0], id: \.self) { m in
                    Button {
                        _ = try? service.logMeters(in: session, meters: m)
                    } label: {
                        Text("+\(Int(m))")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(Int(m)) meters")
                }
            }
        }

        Section("Set exact distance") {
            HStack {
                TextField("Meters", value: $metersExact, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.leading)
                Button("Set") {
                    _ = try? service.setExactDistance(in: session, meters: metersExact)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func recentLocations() -> [String] {
        let svc = SwimService(modelContext: modelContext, healthKit: nil)
        return svc.recentLocations(limit: 5)
    }

    private func start() {
        let svc = SwimService(modelContext: modelContext, healthKit: LiveHealthKitService.shared)
        do {
            let trimmed = locationText.trimmingCharacters(in: .whitespaces)
            let s = try svc.startSession(
                at: Date(),
                poolLengthMeters: poolLengthMeters,
                location: trimmed.isEmpty ? nil : trimmed,
                waterType: waterType
            )
            startedAt = Date()
            session = s
            service = svc
            lapsExact = s.laps
            metersExact = s.totalMeters
            Task { _ = await WorkoutLiveActivityController.start(workoutType: "Swim", startDate: startedAt) }
        } catch {
            // logged inside service
        }
    }

    private func end(service: SwimService, session: SwimSession) async {
        let mins = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        do {
            try service.endSession(session, durationMinutes: mins)
            await WorkoutLiveActivityController.endAll()
            completionCount &+= 1
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
