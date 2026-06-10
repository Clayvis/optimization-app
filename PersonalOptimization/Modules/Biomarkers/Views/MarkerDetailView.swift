import SwiftUI
import SwiftData
import Charts

/// Time series for one biomarker across all draws, drawn over its optimal
/// (jade) and normal (ink) reference bands, with the reference
/// implementation's first-to-latest percent change.
struct MarkerDetailView: View {
    @Query(sort: [SortDescriptor(\LabDraw.date, order: .forward)]) private var draws: [LabDraw]

    let markerID: String

    private var definition: BiomarkerDefinition? { BiomarkerCatalog.all[markerID] }

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
                }
                .frame(height: 220)
                .chartYAxisLabel(def.unit)
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
