import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers
import PhotosUI
import AVFoundation

struct InBodyProgressView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \InBodyScan.date, order: .reverse) private var scans: [InBodyScan]
    @Query private var profiles: [UserProfile]
    @State private var adding = false
    @State private var editing: InBodyScan?
    @State private var importing = false
    @State private var error: String?
    @State private var choosingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var readingPhoto = false
    /// Values read from a photo, shown in the editor for review before saving.
    @State private var photoReading: InBodyPhotoReading?
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
                    description: Text("Take or choose a photo of your InBody result sheet, type the values, or import a JSON file. Your scans stay in your private iCloud data."))
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
                    if InBodyCameraPicker.isAvailable {
                        Button("Take photo of results", systemImage: "camera") { Task { await takePhoto() } }
                    }
                    Button("Choose photo", systemImage: "photo.on.rectangle") { choosePhoto() }
                    Button("Type values", systemImage: "square.and.pencil") { adding = true }
                    Button("Import JSON file", systemImage: "square.and.arrow.down") { importing = true }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Add or import InBody scans")
            }
        }
        .onAppear { focus = InBodyService.focus(profile: profiles.first) }
        .sheet(isPresented: $adding) { InBodyScanEditor(scan: nil) }
        .sheet(item: $editing) { InBodyScanEditor(scan: $0) }
        .sheet(item: $photoReading) { InBodyScanEditor(scan: nil, reading: $0) }
        .photosPicker(isPresented: $choosingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await readPhoto(item) }
        }
        .fullScreenCover(isPresented: $takingPhoto) {
            InBodyCameraPicker { image in
                takingPhoto = false
                guard let data = image.uprightJPEGData() else { error = InBodyPhotoError.unreadableImage.localizedDescription; return }
                read([data])
            } onCancel: {
                takingPhoto = false
            }
            .ignoresSafeArea()
        }
        .overlay {
            if readingPhoto {
                ProgressView("Reading your scan…")
                    .padding(Theme.Space.l)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .accessibilityIdentifier("inbody.photo.reading")
            }
        }
        .disabled(readingPhoto)
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

    // MARK: - Photo of a result sheet

    private func choosePhoto() {
        #if DEBUG
        // UI tests cannot drive the system photo picker; read the sample sheet.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-inbody-photo") {
            read([InBodySampleSheet.pngData()])
            return
        }
        #endif
        choosingPhoto = true
    }

    /// The camera asks for access on first use; a refusal points to Settings
    /// and to choosing a photo instead.
    private func takePhoto() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            takingPhoto = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) { takingPhoto = true }
        default:
            error = "Camera access is off for this app. Allow it in Settings, or choose a photo of your results instead."
        }
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        readingPhoto = true
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw InBodyPhotoError.unreadableImage }
            read([data])
        } catch {
            readingPhoto = false
            self.error = error.localizedDescription
        }
    }

    /// Reads on a background thread; the editor opens with the values for review.
    private func read(_ pages: [Data]) {
        readingPhoto = true
        let calendar = UserCalendar.current(modelContext: context)
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try InBodySheetRecognizer.read(imageData: pages, now: Date(), calendar: calendar) }
            }.value
            readingPhoto = false
            switch outcome {
            case .success(let reading): photoReading = reading
            case .failure(let failure): error = failure.localizedDescription
            }
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
    /// Values read from a photo. Every one is shown for review; nothing is
    /// saved until the user taps Save.
    var reading: InBodyPhotoReading? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = InBodyValues()
    @State private var error: String?
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                if let error { ErrorBanner(message: error) { self.error = nil } }
                if let reading { photoSummary(reading) }
                HStack {
                    DatePicker("Scan date", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                    photoMark(.date)
                }
                Section("Whole body") {
                    number("Height (in)", $draft.heightInches, .height)
                    number("Weight (lb)", $draft.weightLb, .weight)
                    number("Skeletal muscle (lb)", $draft.skeletalMuscleMassLb, .skeletalMuscle)
                    number("Lean body mass (lb)", $draft.leanBodyMassLb, .leanBodyMass)
                    number("Body-fat mass (lb)", $draft.bodyFatMassLb, .bodyFatMass)
                    number("Body fat (%)", $draft.bodyFatPercent, .bodyFatPercent)
                }
                Section("Optional scan measurements") {
                    optional("Visceral fat area (cm²)", $draft.visceralFatAreaCm2, .visceralFatArea)
                    optional("Total body water (lb)", $draft.totalBodyWaterLb, .totalBodyWater)
                    optional("ECW/TBW ratio", $draft.ecwTbwRatio, .ecwTbwRatio)
                    optional("BMR (kcal)", $draft.basalMetabolicRateKcal, .basalMetabolicRate)
                    optional("Right arm lean (lb)", $draft.rightArmLb, .rightArm)
                    optional("Left arm lean (lb)", $draft.leftArmLb, .leftArm)
                    optional("Trunk lean (lb)", $draft.trunkLb, .trunk)
                    optional("Right leg lean (lb)", $draft.rightLegLb, .rightLeg)
                    optional("Left leg lean (lb)", $draft.leftLegLb, .leftLeg)
                }
            }
            .navigationTitle(scan != nil ? "Edit scan" : reading != nil ? "Check scan" : "Add scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try InBodyService.save([draft], context: context, editing: scan); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("inbody.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let scan { draft = scan.values } else if let reading { draft = reading.values }
            }
        }
    }

    private func photoSummary(_ reading: InBodyPhotoReading) -> some View {
        let missing = InBodyField.allCases.filter { !reading.read.contains($0) }
        return Section {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Label("Read \(reading.read.count) of \(InBodyField.allCases.count) values from your photo",
                      systemImage: "text.viewfinder")
                    .font(.headline)
                Text("Check each value against your sheet before saving. The photo was read on this iPhone and wasn't saved.")
                    .font(.caption)
                if !reading.uncertain.isEmpty {
                    Label("Values marked with a warning were hard to read or don't add up. Compare them closely.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !reading.read.contains(.date) {
                    Text("The test date wasn't found. Set it below.").font(.caption)
                }
                if reading.convertedFromKilograms {
                    Text("The sheet was in kilograms; masses were converted to pounds.").font(.caption)
                }
                if !missing.isEmpty {
                    Text("Not found: \(missing.map(\.label).joined(separator: ", ")).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("inbody.photo.summary")
        }
    }

    /// Marks a value the photo supplied, in orange when it needs a closer look.
    @ViewBuilder
    private func photoMark(_ field: InBodyField) -> some View {
        if let reading, reading.read.contains(field) {
            if reading.uncertain[field] != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Check against the sheet")
            } else {
                Image(systemName: "text.viewfinder")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Read from photo")
            }
        }
    }

    /// The readings behind a doubtful value, each one tap to use.
    @ViewBuilder
    private func alternatives(_ field: InBodyField) -> some View {
        if let options = reading?.uncertain[field] {
            HStack(spacing: Theme.Space.s) {
                Text(options.count > 1 ? "Read as" : "Doesn't add up. Check")
                    .font(.caption)
                    .foregroundStyle(.orange)
                ForEach(options, id: \.self) { option in
                    Button(option.formatted()) { InBodySheetParser.set(field, option, on: &draft) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("Use \(option.formatted())")
                        .accessibilityIdentifier("inbody.photo.option")
                }
            }
        }
    }

    private func number(_ label: String, _ value: Binding<Double>, _ field: InBodyField) -> some View {
        let display = Binding<Double?>(get: { value.wrappedValue == 0 ? nil : value.wrappedValue },
                                      set: { value.wrappedValue = $0 ?? 0 })
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(label)
                photoMark(field)
                TextField("Required", value: display, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier(label)
            }
            alternatives(field)
        }
    }

    private func optional(_ label: String, _ value: Binding<Double?>, _ field: InBodyField) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(label)
                photoMark(field)
                TextField("Not measured", value: value, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier(label)
            }
            alternatives(field)
        }
    }
}

private extension InBodyField {
    /// Name in the editor's "not found" list.
    var label: String {
        switch self {
        case .date: return "test date"
        case .height: return "height"
        case .weight: return "weight"
        case .skeletalMuscle: return "skeletal muscle"
        case .leanBodyMass: return "lean body mass"
        case .bodyFatMass: return "body-fat mass"
        case .bodyFatPercent: return "body fat %"
        case .totalBodyWater: return "total body water"
        case .ecwTbwRatio: return "ECW/TBW"
        case .visceralFatArea: return "visceral fat area"
        case .basalMetabolicRate: return "BMR"
        case .rightArm: return "right arm"
        case .leftArm: return "left arm"
        case .trunk: return "trunk"
        case .rightLeg: return "right leg"
        case .leftLeg: return "left leg"
        }
    }
}

#Preview {
    NavigationStack { InBodyProgressView() }
        .modelContainer(for: [InBodyScan.self, UserProfile.self], inMemory: true)
}
