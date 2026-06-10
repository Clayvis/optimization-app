import SwiftUI
import SwiftData
import Charts

/// Time series for one biomarker across all draws, drawn over its optimal
/// (jade) and normal (ink) reference bands, with the reference
/// implementation's first-to-latest percent change.
struct MarkerDetailView: View {
    @Query(sort: [SortDescriptor(\LabDraw.date, order: .forward)]) private var draws: [LabDraw]
    @Query(sort: [SortDescriptor(\WearableEntry.date, order: .forward)]) private var wearables: [WearableEntry]

    let markerID: String

    @State private var overlayMetric: String?

    private var definition: BiomarkerDefinition? { BiomarkerCatalog.all[markerID] }

    /// Wearable metric keys present in the data, with display labels. Lets the
    /// user overlay a recovery signal (HRV, resting HR, sleep) on the marker
    /// trend to eyeball correlations.
    private static let overlayChoices: [(key: String, label: String)] = [
        ("hrv_rmssd", "HRV"),
        ("resting_hr", "Resting HR"),
        ("sleep_score", "Sleep score"),
        ("weight", "Weight")
    ]

    private var availableOverlays: [(key: String, label: String)] {
        Self.overlayChoices.filter { choice in
            wearables.contains { $0.metrics[choice.key] != nil }
        }
    }

    private func overlaySeries(_ key: String) -> [(date: Date, value: Double)] {
        wearables
            .compactMap { entry in entry.metrics[key].map { (entry.date, $0) } }
            .sorted { $0.date < $1.date }
    }

    private var series: [(date: Date, value: Double)] {
        draws.compactMap { draw in
            draw.values[markerID].map { (draw.date, $0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let def = definition {
                    headerCard(def)
                    chartCard(def)
                    drawList(def)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, Theme.Space.xxl)
        }
        .dojoBackground()
        .navigationTitle(definition?.name ?? markerID)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func headerCard(_ def: BiomarkerDefinition) -> some View {
        let latest = series.last
        let flag = BiomarkerCatalog.evaluate(markerID, value: latest?.value)

        DojoCard(accent: accentColor(flag)) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionEyebrow(title: def.category)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(latest.map { format($0.value) } ?? "—")
                            .font(Theme.numeral(34))
                            .foregroundStyle(Theme.textPrimary)
                        Text(def.unit)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(flag.displayLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor(flag))
                }
                Spacer()
                if let trend = BiomarkerInsights.trendPercent(markerID: markerID, draws: draws) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(trend > 0 ? "+" : "")\(format(trend))%")
                            .font(Theme.numeral(20))
                            .foregroundStyle(trend > 0 ? Theme.kin : Theme.matcha)
                        Text("since first draw")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chartCard(_ def: BiomarkerDefinition) -> some View {
        if series.count >= 2 {
            DojoCard {
                Chart {
                    if def.normal.count == 2 {
                        RectangleMark(
                            yStart: .value("Normal low", def.normal[0]),
                            yEnd: .value("Normal high", def.normal[1])
                        )
                        .foregroundStyle(Theme.inkSunken.opacity(0.6))
                    }
                    if def.optimal.count == 2 {
                        RectangleMark(
                            yStart: .value("Optimal low", def.optimal[0]),
                            yEnd: .value("Optimal high", def.optimal[1])
                        )
                        .foregroundStyle(Theme.matcha.opacity(0.18))
                    }
                    ForEach(series, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(def.name, point.value)
                        )
                        .foregroundStyle(Theme.kurenai)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(def.name, point.value)
                        )
                        .foregroundStyle(Theme.kurenai)
                    }
                    // Wearable overlay on a secondary axis, normalized into the
                    // marker's value band so the shapes are visually comparable.
                    if let overlayMetric, let mapped = normalizedOverlay(overlayMetric) {
                        ForEach(mapped, id: \.date) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("overlay", point.value),
                                series: .value("series", "overlay")
                            )
                            .foregroundStyle(Theme.ai)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                }
                .frame(height: 220)
                .chartYAxisLabel(def.unit)

                if !availableOverlays.isEmpty {
                    overlayPicker
                }
            }
            .accessibilityLabel("\(def.name) trend chart, \(series.count) draws")
        } else {
            DojoCard {
                Text("One draw so far. Trends unlock with the second draw.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func drawList(_ def: BiomarkerDefinition) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(title: "Readings")
            DojoCard(padding: Theme.Space.s) {
                VStack(spacing: 0) {
                    ForEach(series.reversed(), id: \.date) { point in
                        HStack {
                            Text(point.date, format: .dateTime.day().month().year())
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(format(point.value))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(accentColor(BiomarkerCatalog.evaluate(markerID, value: point.value)))
                            Text(def.unit)
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(Theme.Space.s)
                        if point.date != series.first?.date {
                            Divider().overlay(Theme.hairline)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var overlayPicker: some View {
        HStack(spacing: Theme.Space.s) {
            Text("Overlay")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            Button("Off") { overlayMetric = nil }
                .font(.caption2.weight(overlayMetric == nil ? .bold : .regular))
                .foregroundStyle(overlayMetric == nil ? Theme.kurenai : Theme.textSecondary)
                .buttonStyle(.plain)
            ForEach(availableOverlays, id: \.key) { choice in
                Button(choice.label) { overlayMetric = choice.key }
                    .font(.caption2.weight(overlayMetric == choice.key ? .bold : .regular))
                    .foregroundStyle(overlayMetric == choice.key ? Theme.ai : Theme.textSecondary)
                    .buttonStyle(.plain)
            }
        }
    }

    /// Min-max normalize the wearable series into the marker's own value band
    /// so both lines share the chart's y-domain.
    private func normalizedOverlay(_ key: String) -> [(date: Date, value: Double)]? {
        let overlay = overlaySeries(key).filter { point in
            guard let first = series.first?.date, let last = series.last?.date else { return false }
            return point.date >= first && point.date <= last
        }
        guard overlay.count >= 2, series.count >= 2 else { return nil }
        let oVals = overlay.map(\.value)
        let mVals = series.map(\.value)
        guard let oMin = oVals.min(), let oMax = oVals.max(), oMax > oMin,
              let mMin = mVals.min(), let mMax = mVals.max() else { return nil }
        return overlay.map { point in
            let t = (point.value - oMin) / (oMax - oMin)
            return (point.date, mMin + t * (mMax - mMin))
        }
    }

    private func accentColor(_ flag: BiomarkerFlag) -> Color {
        switch flag {
        case .optimal: return Theme.matcha
        case .warning: return Theme.kin
        case .high: return Theme.kurenai
        case .low: return Theme.ai
        case .none: return Theme.textTertiary
        }
    }

    private func format(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

#Preview {
    NavigationStack {
        MarkerDetailView(markerID: "glucose")
    }
    .modelContainer(markerPreviewContainer)
}

@MainActor
private let markerPreviewContainer: ModelContainer = {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let ctx = container.mainContext
    let cal = Calendar.current
    for (offset, value) in [(0, 100.0), (-90, 96.0), (-180, 92.0)] {
        // MARK: - try? justified because preview seed only.
        _ = try? LabDrawStore.upsert(
            date: cal.date(byAdding: .day, value: offset, to: Date()) ?? Date(),
            values: ["glucose": value],
            modelContext: ctx
        )
    }
    return container
}()
