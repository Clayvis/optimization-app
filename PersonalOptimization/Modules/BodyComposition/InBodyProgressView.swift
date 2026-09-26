import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct InBodyProgressView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \InBodyScan.date, order: .reverse) private var scans: [InBodyScan]
    @Query private var profiles: [UserProfile]
    @State private var adding = false
    @State private var editing: InBodyScan?
    @State private var importing = false
    @State private var error: String?
    @State private var focus = HypertrophyFocus()
    @State private var selectedPrevious: UUID?
    private var previous: InBodyScan? {
        scans.dropFirst().first { $0.id == selectedPrevious } ?? scans.dropFirst().first
    }
    private var comparison: BodyCompositionComparison? {
        guard let current = scans.first, let previous else { return nil }
        // MARK: try? justified: the view shows an explicit unavailable state for invalid imported chronology.
        return try? BodyCompositionComparison(previous: previous.values, current: current.values,
                                              calendar: UserCalendar.current(modelContext: context))
    }

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { self.error = nil } }
            if let latest = scans.first {
                Section("Body composition") {
                    Text("\(latest.weightLb, specifier: "%.1f") lb").font(.largeTitle.bold())
                    Text(latest.date, style: .date).foregroundStyle(.secondary)
                    LabeledContent("Estimated skeletal muscle", value: "\(latest.skeletalMuscleMassLb.formatted()) lb")
                    LabeledContent("Body fat", value: "\(latest.bodyFatPercent.formatted())%")
                    Button("Edit latest scan") { editing = latest }
                }
                if let delta = comparison {
                    analysisSection(BodyCompositionAssessment(comparison: delta, focus: focus))
                    Section("Scan comparison") {
                        Picker("Compare with", selection: $selectedPrevious) {
                            ForEach(Array(scans.dropFirst())) { scan in
                                Text(scan.date, style: .date).tag(Optional(scan.id))
                            }
                        }
                        metric("Estimated skeletal muscle", delta.skeletalMuscle, "lb")
                        metric("Total lean mass", delta.leanMass, "lb")
                        metric("Body weight", delta.weight, "lb")
                        metric("Body-fat mass", delta.fatMass, "lb")
                        metric("Body-fat percentage", delta.fatPercentagePoints, "percentage points")
                        if let value = delta.visceralFat { metric("Visceral fat area", value, "cm²") }
                        metric("Weekly weight change", delta.weeklyWeight, "lb/week")
                        Text("\(delta.days) days · \(delta.weeks, specifier: "%.2f") weeks between scans")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Hydration comparability: \(delta.comparability.rawValue)") {
                        if let water = delta.water { metric("Total body water", water, "lb") }
                        if let ecw = delta.ecw { LabeledContent("ECW/TBW change", value: String(format: "%+.3f", ecw)) }
                        Text("Lean mass includes water and other fat-free tissue. It is not the amount of muscle gained. Skeletal-muscle mass is also a BIA estimate.")
                        Text("Comparison heuristic: high ≤0.003, moderate ≤0.007, lower >0.007 absolute ECW/TBW change. Missing ratios mean unknown. This is not a clinically validated confidence score. Compare scans under consistent preparation conditions.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Segmental lean-mass change") {
                        ForEach(["Right arm", "Left arm", "Trunk", "Right leg", "Left leg"]
                            .filter { delta.segments[$0] != nil }, id: \.self) { key in
                            metric(key, delta.segments[key] ?? 0, "lb")
                        }
                        Text("Whole-arm and whole-leg measurements cannot isolate forearms, quads, hamstrings, adductors or calves. Use workout records to assess those muscles.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Scan history") {
                        Chart(scans) { scan in
                            LineMark(x: .value("Date", scan.date), y: .value("Skeletal muscle (lb)", scan.skeletalMuscleMassLb))
                            PointMark(x: .value("Date", scan.date), y: .value("Skeletal muscle (lb)", scan.skeletalMuscleMassLb))
                        }.frame(height: 170)
                        Text("Estimated skeletal-muscle mass, lb").font(.caption)
                    }
                } else {
                    Text("Add a second scan from a different day to compare trends.")
                }
            } else {
                ContentUnavailableView("InBody Progress Coach", systemImage: "figure.strengthtraining.traditional",
                    description: Text("Add a scan or import a JSON scan file. Your scans stay in your private iCloud data."))
            }
            focusSection
            if focus.enabled {
                Section("Training emphasis · last 7 days") {
                    ForEach(InBodyService.guidance(context: context, profile: profiles.first, asOf: Date())) { advice in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(advice.muscle).font(.headline)
                            Text("\(advice.directSets) direct sets · \(advice.effectiveSets, specifier: "%.1f") effective sets")
                            Text(advice.averageRIR.map { "Average recorded RIR: \($0.formatted(.number.precision(.fractionLength(1))))" } ?? "RIR: not recorded")
                            Text(advice.recommendation).font(.subheadline.weight(.medium))
                            Text(advice.prescription).font(.caption)
                            Text(advice.exercises).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                    Text("These are starting ranges, not mandatory quotas. Keep chest, back, shoulders and upper arms at maintenance volume when reallocating sets. Recovery and pain restrictions take precedence.").font(.caption)
                    Text("Uses completed lift sessions, logged RIR and matched-exercise performance. Nutrition and sleep/recovery context also feed the existing Coach. Unclassified exercises and missing RIR are not assumed to be hard sets.").font(.caption)
                }
            }
            Section("All scans") {
                ForEach(scans) { scan in
                    Button { editing = scan } label: {
                        HStack { Text(scan.date, style: .date); Spacer(); Text("\(scan.weightLb, specifier: "%.1f") lb") }
                    }
                }
            }
        }
        .navigationTitle("InBody Coach")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add scan", systemImage: "plus") { adding = true }
                    Button("Import scans", systemImage: "square.and.arrow.down") { importing = true }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Add or import InBody scans")
            }
        }
        .onAppear { focus = InBodyService.focus(profile: profiles.first) }
        .sheet(isPresented: $adding) { InBodyScanEditor(scan: nil) }
        .sheet(item: $editing) { InBodyScanEditor(scan: $0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let values = try decoder.decode([InBodyValues].self, from: Data(contentsOf: url))
                try InBodyService.save(values, context: context)
            } catch { self.error = error.localizedDescription }
        }
    }

    private func metric(_ name: String, _ value: Double, _ unit: String) -> some View {
        LabeledContent(name, value: String(format: "%+.2f %@", value, unit))
    }

    private var focusSection: some View {
        Section("Controlled hypertrophy") {
            Toggle("Use this focus in the Coach", isOn: $focus.enabled)
                .onChange(of: focus.enabled) { _, _ in saveFocus() }
            Text("Priority order: thighs, calves, forearms. Maintain chest, back, shoulders and upper arms.").font(.caption)
            HStack {
                Text("Weekly gain minimum (lb)")
                TextField("0.25", value: $focus.weeklyGainMin, format: .number).keyboardType(.decimalPad)
            }
            HStack {
                Text("Weekly gain maximum (lb)")
                TextField("0.5", value: $focus.weeklyGainMax, format: .number).keyboardType(.decimalPad)
            }
            Button("Save training focus") { saveFocus() }
        }
    }

    /// Deterministic coach analysis. Stable bands and rate targets are shown
    /// so the verdict is checkable, and calories never change automatically.
    private func analysisSection(_ assessment: BodyCompositionAssessment) -> some View {
        Section("Coach analysis") {
            Text(assessment.headline)
                .font(.headline)
                .accessibilityIdentifier("inbody.analysis.headline")
            LabeledContent("Estimated skeletal muscle", value: assessment.muscle.rawValue)
            LabeledContent("Body-fat mass", value: assessment.fatMass.rawValue)
            LabeledContent("Body-fat percentage", value: assessment.bodyFatPercent.rawValue)
            LabeledContent("Weight-gain rate", value: assessment.gainRate.rawValue)
            LabeledContent("Scan comparability", value: assessment.comparability.rawValue.capitalized)
            ForEach(assessment.recommendations, id: \.self) { line in
                Label(line, systemImage: "arrow.right.circle")
                    .font(.subheadline)
            }
            Text("Stable means within ±\(BodyCompositionAssessment.muscleBandLb.formatted()) lb of muscle or fat mass, or ±\(BodyCompositionAssessment.bodyFatBandPoints.formatted()) body-fat points; smaller scan-to-scan changes are within normal measurement noise. Calorie targets are not changed automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func saveFocus() {
        guard let profile = profiles.first else { error = "Complete your profile first."; return }
        guard focus.weeklyGainMin.isFinite, focus.weeklyGainMax.isFinite,
              focus.weeklyGainMin >= 0, focus.weeklyGainMax >= focus.weeklyGainMin else {
            error = "Enter a valid weekly gain range."; return
        }
        // Loading the stored focus on appear also fires the toggle's onChange.
        guard InBodyService.focus(profile: profile) != focus else { return }
        let previous = profile.metadataBlob
        profile.setMetadata("inbody.focus", value: focus)
        do { try context.save() }
        catch { profile.metadataBlob = previous; self.error = error.localizedDescription }
    }
}

private struct InBodyScanEditor: View {
    let scan: InBodyScan?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = InBodyValues()
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let error { ErrorBanner(message: error) { self.error = nil } }
                DatePicker("Scan date", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                Section("Whole body") {
                    number("Height (in)", $draft.heightInches)
                    number("Weight (lb)", $draft.weightLb)
                    number("Skeletal muscle (lb)", $draft.skeletalMuscleMassLb)
                    number("Lean body mass (lb)", $draft.leanBodyMassLb)
                    number("Body-fat mass (lb)", $draft.bodyFatMassLb)
                    number("Body fat (%)", $draft.bodyFatPercent)
                }
                Section("Optional scan measurements") {
                    optional("Visceral fat area (cm²)", $draft.visceralFatAreaCm2)
                    optional("Total body water (lb)", $draft.totalBodyWaterLb)
                    optional("ECW/TBW ratio", $draft.ecwTbwRatio)
                    optional("BMR (kcal)", $draft.basalMetabolicRateKcal)
                    optional("Right arm lean (lb)", $draft.rightArmLb)
                    optional("Left arm lean (lb)", $draft.leftArmLb)
                    optional("Trunk lean (lb)", $draft.trunkLb)
                    optional("Right leg lean (lb)", $draft.rightLegLb)
                    optional("Left leg lean (lb)", $draft.leftLegLb)
                }
            }
            .navigationTitle(scan == nil ? "Add scan" : "Edit scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try InBodyService.save([draft], context: context, editing: scan); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("inbody.save")
                }
            }
            .onAppear { if let scan { draft = scan.values } }
        }
    }
    private func number(_ label: String, _ value: Binding<Double>) -> some View {
        let display = Binding<Double?>(get: { value.wrappedValue == 0 ? nil : value.wrappedValue },
                                      set: { value.wrappedValue = $0 ?? 0 })
        return HStack {
            Text(label)
            TextField("Required", value: display, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier(label)
        }
    }
    private func optional(_ label: String, _ value: Binding<Double?>) -> some View {
        HStack { Text(label); TextField("Not measured", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
    }
}

#Preview {
    NavigationStack { InBodyProgressView() }
        .modelContainer(for: [InBodyScan.self, UserProfile.self], inMemory: true)
}
