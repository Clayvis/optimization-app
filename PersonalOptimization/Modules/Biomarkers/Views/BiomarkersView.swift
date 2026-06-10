import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

/// Biomarker dashboard: PhenoAge crest, latest-draw summary, rule-based
/// patterns, and per-category marker list. Entry points for manual draws,
/// PDF parsing, and reference-format JSON import.
struct BiomarkersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\LabDraw.date, order: .reverse)]) private var draws: [LabDraw]
    @Query private var profiles: [UserProfile]

    @State private var showEditor = false
    @State private var editorPrefill: ParsedLabReport?
    @State private var showPDFImporter = false
    @State private var showJSONImporter = false
    @State private var importError: String?
    @State private var importBusy = false

    private var profile: UserProfile? { profiles.first }
    private var sex: String { profile?.sex ?? "male" }
    private var latest: LabDraw? { draws.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if let latest {
                        phenoAgeCard(for: latest)
                        summaryRow(for: latest)
                        patternsCard(for: latest)
                        categorySections(for: latest)
                        historyCard
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, Theme.Space.xxl)
            }
            .dojoBackground()
            .navigationTitle("Labs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            editorPrefill = nil
                            showEditor = true
                        } label: {
                            Label("Enter values", systemImage: "square.and.pencil")
                        }
                        Button {
                            showPDFImporter = true
                        } label: {
                            Label("Parse lab PDF", systemImage: "doc.viewfinder")
                        }
                        Button {
                            showJSONImporter = true
                        } label: {
                            Label("Import JSON export", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Theme.kurenai)
                    }
                    .accessibilityLabel("Add lab draw")
                }
            }
            .sheet(isPresented: $showEditor) {
                LabDrawEditorView(prefill: editorPrefill, sex: sex)
            }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
                handlePDF(result)
            }
            .fileImporter(isPresented: $showJSONImporter, allowedContentTypes: [.json]) { result in
                handleJSON(result)
            }
            .overlay {
                if importBusy {
                    ProgressView("Parsing…")
                        .padding(Theme.Space.xl)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.inkRaised))
                }
            }
            .alert("Import failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - PhenoAge

    @ViewBuilder
    private func phenoAgeCard(for draw: LabDraw) -> some View {
        let chrono = profile.flatMap { PhenoAgeCalculator.chronologicalAge(dob: $0.dob, asOf: draw.date) }
        let pheno = chrono.flatMap { PhenoAgeCalculator.phenoAge(values: draw.values, chronologicalAge: $0) }

        DojoCard(accent: Theme.kurenai) {
            HStack(spacing: Theme.Space.xl) {
                CrestRing(progress: ringProgress(pheno: pheno, chrono: chrono)) {
                    VStack(spacing: 0) {
                        if let pheno {
                            Text(String(format: "%.1f", pheno))
                                .font(Theme.numeral(24))
                                .foregroundStyle(Theme.textPrimary)
                            Text("bio age")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            Image(systemName: "questionmark")
                                .font(.title3)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionEyebrow(title: "PhenoAge")
                    if let pheno, let chrono {
                        let delta = pheno - chrono
                        Text(deltaLabel(delta))
                            .font(.headline)
                            .foregroundStyle(delta <= 0 ? Theme.matcha : Theme.kin)
                        Text("Chronological: \(String(format: "%.1f", chrono))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        let missing = PhenoAgeCalculator.missingMarkers(in: draw.values)
                        Text("Needs \(missing.count) more marker\(missing.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Text(missing.compactMap { BiomarkerCatalog.all[$0]?.name }.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .accessibilityLabel("Biological age card")
    }

    private func ringProgress(pheno: Double?, chrono: Double?) -> Double {
        guard let pheno, let chrono, chrono > 0 else { return 0 }
        // Full ring at 10 years younger; empty at 10 years older.
        return min(1, max(0, (chrono - pheno + 10) / 20))
    }

    private func deltaLabel(_ delta: Double) -> String {
        if abs(delta) < 0.05 { return "Matching your age" }
        let years = String(format: "%.1f", abs(delta))
        return delta < 0 ? "\(years) years younger" : "\(years) years older"
    }

    // MARK: - Summary

    @ViewBuilder
    private func summaryRow(for draw: LabDraw) -> some View {
        let summary = BiomarkerInsights.summarize(values: draw.values)
        HStack(spacing: Theme.Space.s) {
            StatChip(systemImage: "checkmark.seal.fill", text: "\(summary.optimal) optimal", tint: Theme.matcha)
            StatChip(systemImage: "minus.circle", text: "\(summary.suboptimal) sub", tint: Theme.kin)
            StatChip(systemImage: "exclamationmark.triangle.fill", text: "\(summary.outOfRange) flagged", tint: Theme.kurenai)
            Spacer()
            Text(draw.date, format: .dateTime.day().month().year())
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Patterns

    @ViewBuilder
    private func patternsCard(for draw: LabDraw) -> some View {
        let patterns = BiomarkerInsights.detectPatterns(values: draw.values, sex: sex)
        if !patterns.isEmpty {
            DojoCard(accent: Theme.kin) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionEyebrow(title: "Signals", tint: Theme.kin)
                    ForEach(patterns) { pattern in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pattern.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(pattern.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Categories

    @ViewBuilder
    private func categorySections(for draw: LabDraw) -> some View {
        ForEach(BiomarkerCatalog.categoryOrder, id: \.self) { category in
            let ids = BiomarkerCatalog.ids(inCategory: category, sex: sex)
                .filter { draw.values[$0] != nil }
            if !ids.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionEyebrow(title: category)
                    DojoCard(padding: Theme.Space.s) {
                        VStack(spacing: 0) {
                            ForEach(ids, id: \.self) { id in
                                markerRow(id: id, draw: draw)
                                if id != ids.last {
                                    Divider().overlay(Theme.hairline)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func markerRow(id: String, draw: LabDraw) -> some View {
        if let def = BiomarkerCatalog.all[id], let value = draw.values[id] {
            NavigationLink {
                MarkerDetailView(markerID: id)
            } label: {
                HStack {
                    flagDot(BiomarkerCatalog.evaluate(id, value: value))
                    Text(def.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let trend = BiomarkerInsights.trendPercent(markerID: id, draws: draws) {
                        Text(trend > 0 ? "↑" : (trend < 0 ? "↓" : "→"))
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Text(valueLabel(value))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text(def.unit)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, Theme.Space.s)
                .padding(.horizontal, Theme.Space.s)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(def.name): \(valueLabel(value)) \(def.unit)")
        }
    }

    private func flagDot(_ flag: BiomarkerFlag) -> some View {
        Circle()
            .fill(flagColor(flag))
            .frame(width: 8, height: 8)
            .accessibilityLabel(flag.displayLabel)
    }

    private func flagColor(_ flag: BiomarkerFlag) -> Color {
        switch flag {
        case .optimal: return Theme.matcha
        case .warning: return Theme.kin
        case .high: return Theme.kurenai
        case .low: return Theme.ai
        case .none: return Theme.textTertiary
        }
    }

    private func valueLabel(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: - History

    @ViewBuilder
    private var historyCard: some View {
        if draws.count > 1 {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(title: "Past draws")
                DojoCard(padding: Theme.Space.s) {
                    VStack(spacing: 0) {
                        ForEach(draws.dropFirst()) { draw in
                            HStack {
                                Text(draw.date, format: .dateTime.day().month().year())
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(draw.values.count) markers")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(Theme.Space.s)
                            if draw.persistentModelID != draws.last?.persistentModelID {
                                Divider().overlay(Theme.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        DojoCard {
            VStack(spacing: Theme.Space.m) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.kurenai)
                Text("No lab draws yet")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Add blood work by entering values, parsing a lab PDF, or importing a JSON export. PhenoAge unlocks once the nine required markers are present.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Enter first draw") {
                    editorPrefill = nil
                    showEditor = true
                }
                .buttonStyle(BladeButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.l)
        }
        .padding(.top, Theme.Space.xxl)
    }

    // MARK: - Import handling

    private func handlePDF(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let url):
            importBusy = true
            let sex = self.sex
            Task {
                defer { importBusy = false }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let report = try await BiomarkerPDFParser.shared.parse(pdfAt: url, sex: sex)
                    if report.values.isEmpty {
                        importError = "No biomarkers recognized in \(url.lastPathComponent)."
                    } else {
                        editorPrefill = report
                        showEditor = true
                    }
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func handleJSON(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let url):
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let count = try LabDrawStore.importReferenceJSON(data, modelContext: modelContext)
                Logger.parser.info("Imported \(count, privacy: .public) draws from JSON")
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

#Preview {
    BiomarkersView()
        .modelContainer(biomarkerPreviewContainer)
}

@MainActor
private let biomarkerPreviewContainer: ModelContainer = {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let ctx = container.mainContext
    let profile = UserProfile(name: "Clay", dob: Calendar.current.date(byAdding: .year, value: -31, to: Date()) ?? .distantPast)
    profile.onboardingCompleted = true
    ctx.insert(profile)
    _ = try? LabDrawStore.upsert(  // MARK: try? justified - preview seed only.
        date: Date(),
        values: [
            "glucose": 100, "hemoglobin": 14.6, "hematocrit": 43.3, "rbc": 4.93,
            "wbc": 5.10, "mcv": 88.0, "rdw": 13.9, "platelets": 228,
            "lymphocyte_pct": 37.2, "albumin": 4.6, "alt": 17, "ast": 22,
            "alk_phos": 56, "creatinine": 1.15, "tsh": 0.425, "magnesium": 1.7
        ],
        notes: "Preview draw",
        modelContext: ctx
    )
    return container
}()
