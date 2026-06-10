import SwiftUI
import SwiftData
import Charts

struct HydrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var service: HydrationService?
    @State private var loadError: String?
    @State private var refreshTrigger = 0

    @State private var customAmount: Double = 0
    @State private var customUnit: HydrationUnit = .oz
    @State private var customBeverage: BeverageType = .water
    @State private var editingEntry: HydrationEntry?
    @State private var celebrationTrigger = 0

    enum HydrationUnit: String, CaseIterable, Identifiable {
        case oz, mL
        var id: String { rawValue }
    }

    private var quickPicks: [Double] {
        let csv = profiles.first?.hydrationQuickPicksOzCSV ?? "4,8,12,16,20,24,32"
        return HydrationService.parseQuickPicksCSV(csv)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Hydration")
                .scrollContentBackground(.hidden)
                .background(DojoBackground())
        }
        .task { await loadService() }
        .sensoryFeedback(.increase, trigger: celebrationTrigger)
        .sheet(item: $editingEntry) { entry in
            if let service {
                HydrationEntryEditSheet(entry: entry, service: service) {
                    refreshTrigger += 1
                }
            }
        }
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
            VStack(spacing: 16) {
                progressCard(intake: intake, target: target, dayType: dayType)

                paceCard(intake: intake, target: target, now: now)

                quickLogCard(service: service)

                customLogCard(service: service)

                electrolyteCard(count: electrolytes, service: service)

                recentEntriesCard(service: service, now: now)
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
        .dojoCardSurface()
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
        .dojoCardSurface()
    }

    @ViewBuilder
    private func quickLogCard(service: HydrationService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick log")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Beverage", selection: $customBeverage) {
                    ForEach(BeverageType.allCases, id: \.rawValue) { b in
                        Text(b.displayName).tag(b)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Beverage type")
            }

            let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(quickPicks, id: \.self) { oz in
                    Button {
                        _ = try? service.logBeverage(amountOz: oz, beverageType: customBeverage)  // MARK: try? justified - best-effort; failure logged inside the called function.
                        refreshTrigger += 1
                        celebrationTrigger += 1
                        LogFeedbackCenter.shared.confirm(IdentityCopy.hydrationLogged)
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(Int(oz))")
                                .font(.title3.weight(.bold))
                            Text("oz")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .dojoCardSurface()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log \(Int(oz)) ounces of \(customBeverage.displayName)")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
    }

    @ViewBuilder
    private func customLogCard(service: HydrationService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom amount")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Amount", value: $customAmount, format: .number)
                    .keyboardType(.decimalPad)
                    .padding(8)
                    .dojoCardSurface()
                Picker("Unit", selection: $customUnit) {
                    Text("oz").tag(HydrationUnit.oz)
                    Text("mL").tag(HydrationUnit.mL)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                Button {
                    logCustom(service: service)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .disabled(customAmount <= 0)
                .accessibilityLabel("Log custom amount")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
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
                _ = try? service.logElectrolyte()  // MARK: try? justified - best-effort; failure logged inside the called function.
                refreshTrigger += 1
                celebrationTrigger += 1
                LogFeedbackCenter.shared.confirm(IdentityCopy.hydrationLogged)
            } label: {
                Label("Log", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Log an electrolyte session")
        }
        .padding()
        .dojoCardSurface()
    }

    @ViewBuilder
    private func recentEntriesCard(service: HydrationService, now: Date) -> some View {
        let entries = service.entriesForDay(of: now)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Today's log")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Tap to edit · swipe to delete")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                ForEach(entries.prefix(8), id: \.persistentModelID) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        HStack {
                            Image(systemName: iconFor(beverage: entry.beverageType))
                                .foregroundStyle(colorFor(beverage: entry.beverageType))
                            Text("\(Int(entry.amountOz)) oz · \(entry.beverageType.displayName)")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(timeFormatter.string(from: entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            _ = try? service.deleteEntry(entry)  // MARK: try? justified - best-effort; failure logged inside the called function.
                            refreshTrigger += 1
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .dojoCardSurface()
        }
    }

    private func logCustom(service: HydrationService) {
        switch customUnit {
        case .oz:
            _ = try? service.logBeverage(amountOz: customAmount, beverageType: customBeverage)  // MARK: try? justified - best-effort; failure logged inside the called function.
        case .mL:
            _ = try? service.logBeverage(amountML: customAmount, beverageType: customBeverage)  // MARK: try? justified - best-effort; failure logged inside the called function.
        }
        customAmount = 0
        refreshTrigger += 1
        celebrationTrigger += 1
        LogFeedbackCenter.shared.confirm(IdentityCopy.hydrationLogged)
    }

    private func iconFor(beverage: BeverageType) -> String {
        switch beverage {
        case .water: return "drop.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .tea: return "leaf.fill"
        case .electrolyte: return "bolt.fill"
        case .other: return "drop.halffull"
        }
    }

    private func colorFor(beverage: BeverageType) -> Color {
        switch beverage {
        case .water: return .blue
        case .coffee: return .brown
        case .tea: return .green
        case .electrolyte: return .yellow
        case .other: return .gray
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeZone = TimeZone.current
        f.dateFormat = "HH:mm"
        return f
    }

    private func progressTint(intake: Double, target: ClosedRange<Double>) -> Color {
        if intake >= target.lowerBound { return .green }
        if intake >= target.lowerBound * 0.5 { return .yellow }
        return .orange
    }

    private func currentDayFraction(now: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
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
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
    }

    private func loadService() async {
        do {
            let config = try ScheduleConfigLoader.loadCached()
            service = HydrationService(modelContext: modelContext, targets: config.hydrationTargetsOz)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Editor for a single HydrationEntry. Lets the user fix mis-entered amounts
/// or change the beverage type retroactively. Delete is also exposed here for
/// users who prefer modal flows over swipe gestures.
private struct HydrationEntryEditSheet: View {
    @Bindable var entry: HydrationEntry
    let service: HydrationService
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftAmount: Double
    @State private var draftBeverage: BeverageType
    @State private var error: String?

    init(entry: HydrationEntry, service: HydrationService, onChange: @escaping () -> Void) {
        self.entry = entry
        self.service = service
        self.onChange = onChange
        _draftAmount = State(initialValue: entry.amountOz)
        _draftBeverage = State(initialValue: entry.beverageType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        TextField("Amount", value: $draftAmount, format: .number)
                            .keyboardType(.decimalPad)
                        Text("oz").foregroundStyle(.secondary)
                    }
                    Stepper("Adjust by 1 oz", value: $draftAmount, in: 0...200, step: 1)
                        .labelsHidden()
                }
                Section("Beverage") {
                    Picker("Type", selection: $draftBeverage) {
                        ForEach(BeverageType.allCases, id: \.rawValue) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        do {
                            try service.deleteEntry(entry)
                            onChange()
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    } label: {
                        Label("Delete this entry", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit hydration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try service.updateEntry(entry,
                                                    newAmountOz: draftAmount,
                                                    newBeverageType: draftBeverage)
                            onChange()
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(draftAmount <= 0)
                }
            }
        }
    }
}

#Preview {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return HydrationView().modelContainer(container)
}
