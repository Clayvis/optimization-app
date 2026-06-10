import Foundation
import SwiftData
import os

enum LabDrawStoreError: LocalizedError {
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .invalidDate(let raw): return "Unrecognized lab date \(raw)"
        }
    }
}

/// Insert/merge path for `LabDraw` rows. Lab results are calendar-dated, so
/// the day key is UTC midnight of the draw's date; uniqueness per day is
/// enforced here (fetch-or-merge) rather than with a store constraint, which
/// the CloudKit mirror does not allow.
///
/// Retention: merging only ever ADDS or UPDATES marker values on the existing
/// row. Removing a row is an explicit user action in the editor UI only.
@MainActor
enum LabDrawStore {

    /// UTC midnight for a calendar date.
    static func dayKey(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal.startOfDay(for: date)
    }

    /// All draws, newest first.
    static func allDraws(modelContext: ModelContext) -> [LabDraw] {
        let descriptor = FetchDescriptor<LabDraw>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return modelContext.fetchOrEmpty(descriptor)
    }

    /// The most recent draw, if any.
    static func latest(modelContext: ModelContext) -> LabDraw? {
        var descriptor = FetchDescriptor<LabDraw>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return modelContext.fetchOrEmpty(descriptor).first
    }

    /// Upsert a draw for a calendar date. When a row for that day exists, new
    /// values overwrite matching keys and add the rest; notes/source are
    /// updated when non-empty. Computed markers (HOMA-IR) are auto-filled,
    /// mirroring the reference save path.
    /// - Throws: rethrows the context save failure.
    @discardableResult
    static func upsert(
        date: Date,
        values: [String: Double],
        notes: String? = nil,
        sourcePdfFilename: String? = nil,
        modelContext: ModelContext
    ) throws -> LabDraw {
        let day = dayKey(date)
        let merged = BiomarkerInsights.withComputedValues(values)

        let existing = modelContext.fetchOrEmpty(
            FetchDescriptor<LabDraw>(predicate: #Predicate<LabDraw> { $0.date == day })
        ).first

        if let existing {
            for (k, v) in merged { existing.values[k] = v }
            // Recompute HOMA-IR over the merged row (a new insulin value may
            // pair with a previously stored glucose).
            existing.values = BiomarkerInsights.withComputedValues(existing.values)
            if let notes, !notes.isEmpty { existing.notes = notes }
            if let sourcePdfFilename { existing.sourcePdfFilename = sourcePdfFilename }
            try modelContext.save()
            Logger.parser.info("LabDraw merged for \(day, privacy: .public): now \(existing.values.count, privacy: .public) markers")
            return existing
        }

        let draw = LabDraw(date: day, values: merged)
        if let notes, !notes.isEmpty { draw.notes = notes }
        draw.sourcePdfFilename = sourcePdfFilename
        modelContext.insert(draw)
        try modelContext.save()
        Logger.parser.info("LabDraw created for \(day, privacy: .public) with \(merged.count, privacy: .public) markers")
        return draw
    }

    // MARK: - Reference-format JSON import

    /// One draw row in the reference export format
    /// (`{"id", "date": "YYYY-MM-DD", "notes", "values": {marker: number}}`).
    struct ReferenceLab: Codable {
        let date: String
        let notes: String?
        let values: [String: Double]
    }

    /// Top-level reference export (`sample_lab_dod.json` shape).
    struct ReferenceExport: Codable {
        let labs: [ReferenceLab]
    }

    /// Import draws from a reference-format JSON export. Upserts by day, so
    /// re-importing the same file is idempotent.
    /// - Returns: the number of draws imported.
    /// - Throws: decode failures, `LabDrawStoreError.invalidDate`, save errors.
    @discardableResult
    static func importReferenceJSON(_ data: Data, modelContext: ModelContext) throws -> Int {
        let export = try JSONDecoder().decode(ReferenceExport.self, from: data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"

        for lab in export.labs {
            guard let date = formatter.date(from: lab.date) else {
                throw LabDrawStoreError.invalidDate(lab.date)
            }
            try upsert(date: date, values: lab.values, notes: lab.notes, modelContext: modelContext)
        }
        return export.labs.count
    }
}
