import SwiftUI
import SwiftData
import Charts

struct HydrationView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var service: HydrationService?
    @State private var loadError: String?
    @State private var refreshTrigger = 0

    private let bottleSizes: [Double] = [8, 16, 24, 32]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Hydration")
        }
        .task { await loadService() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ContentUnavailableView("Hydration unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let service {
            mainContent(service: service)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func mainContent(service: HydrationService) -> some View {
        let now = Date()
        let dayType = service.dayType(for: now)
        let target = service.targetRange(for: now)
        let intake = service.intakeForDay(of: now)
        let electrolytes = service.electrolyteCount(for: now)

        ScrollView {
            VStack(spacing: 20) {
                progressCard(intake: intake, target: target, dayType: dayType)

                paceCard(intake: intake, target: target, now: now)

                logCard(service: service)

                electrolyteCard(count: electrolytes, service: service)
            }
            .padding()
            .id(refreshTrigger)
        }
    }

    @ViewBuilder
    private func progressCard(intake: Double, target: ClosedRange<Double>, dayType: DayType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayType.rawValue.uppercased() + " DAY")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(alignment: .lastTextBaseline) {
                Text("\(Int(intake))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("oz")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Target")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(target.lowerBound))–\(Int(target.upperBound)) oz")
                        .font(.subheadline.weight(.medium))
                }
            }

            ProgressView(value: min(intake / target.upperBound, 1.0))
                .tint(progressTint(intake: intake, target: target))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func paceCard(intake: Double, target: ClosedRange<Double>, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pace")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            let hourFraction = currentDayFraction(now: now)
            let idealAtNow = target.lowerBound * hourFraction
            let delta = intake - idealAtNow

            HStack {
                Text(delta >= 0 ? "Ahead by \(Int(abs(delta))) oz" : "Behind by \(Int(abs(delta))) oz")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(delta >= 0 ? .green : .orange)
                Spacer()
                Text("By now: \(Int(idealAtNow)) oz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                LineMark(x: .value("Hour", 6), y: .value("Pace", 0))
                LineMark(x: .value("Hour", 22), y: .value("Pace", target.lowerBound))
                    .foregroundStyle(.secondary)
                PointMark(
                    x: .value("Now", currentJSTHour(now)),
                    y: .value("Intake", intake)
                )
                .foregroundStyle(delta >= 0 ? .green : .orange)
                .symbolSize(120)
            }
            .frame(height: 120)
            .chartYAxis(.hidden)
            .chartXScale(domain: 6...22)
            .chartYScale(domain: 0...(target.upperBound * 1.1))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func logCard(service: HydrationService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log a bottle")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(bottleSizes, id: \.self) { oz in
                    Button {
                        _ = try? service.logBottle(oz: oz)
                        refreshTrigger += 1
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(Int(oz))")
                                .font(.title3.weight(.bold))
                            Text("oz")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log \(Int(oz)) ounces of water")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func electrolyteCard(count: Int, service: HydrationService) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Electrolytes")
                    .font(.subheadline.weight(.semibold))
                Text("\(count) session\(count == 1 ? "" : "s") today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                _ = try? service.logElectrolyte()
                refreshTrigger += 1
            } label: {
                Label("Log", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Log an electrolyte session")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func progressTint(intake: Double, target: ClosedRange<Double>) -> Color {
        if intake >= target.lowerBound { return .green }
        if intake >= target.lowerBound * 0.5 { return .yellow }
        return .orange
    }

    private func currentDayFraction(now: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        // Active waking window 06:00 - 22:00 = 16h = 960 min.
        let windowStart = 6 * 60
        let windowEnd = 22 * 60
        let denom = windowEnd - windowStart
        let progress = max(0, min(denom, minutes - windowStart))
        return Double(progress) / Double(denom)
    }

    private func currentJSTHour(_ date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
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

#Preview {
    let schema = Schema(versionedSchema: SchemaV2.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return HydrationView().modelContainer(container)
}
