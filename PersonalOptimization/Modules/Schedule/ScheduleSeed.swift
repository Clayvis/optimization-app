import Foundation
import SwiftData
import os

struct DefaultScheduleFile: Decodable {
    let version: Int
    let timezone: String
    let blocks: [DefaultBlock]

    struct DefaultBlock: Decodable {
        let dayOfWeek: Int
        let startTime: String
        let endTime: String
        let activity: String
        let type: String
        let module: String?
    }
}

enum ScheduleSeedError: LocalizedError {
    case resourceMissing
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .resourceMissing:
            return "default_schedule.json missing from app bundle"
        case .decodingFailed(let underlying):
            return "Failed to decode default_schedule.json: \(underlying.localizedDescription)"
        }
    }
}

@MainActor
enum ScheduleSeed {

    /// Seeds the template schedule from the bundled JSON if no template blocks exist yet.
    /// Idempotent across multiple launches and across iOS + watchOS targets.
    static func seedIfNeeded(modelContext: ModelContext, bundle: Bundle = .main) throws {
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate { $0.isOverride == false }
        )
        let existing = try modelContext.fetchCount(descriptor)
        guard existing == 0 else {
            Logger.schedule.info("Skipping seed: \(existing, privacy: .public) template blocks present")
            return
        }

        let file = try loadDefaultScheduleFile(bundle: bundle)
        for entry in file.blocks {
            let blockType = BlockType(rawValue: entry.type) ?? .other
            let block = ScheduleBlock(
                dayOfWeek: entry.dayOfWeek,
                startTime: entry.startTime,
                endTime: entry.endTime,
                activity: entry.activity,
                type: blockType,
                module: entry.module
            )
            modelContext.insert(block)
        }
        try modelContext.save()
        Logger.schedule.info("Seeded \(file.blocks.count, privacy: .public) template blocks")
    }

    /// Wipes all non-custom (`isCustom == false`) ScheduleBlocks and re-seeds from the
    /// default file. User-created blocks (`isCustom == true`) are preserved verbatim.
    static func resetToDefault(modelContext: ModelContext, bundle: Bundle = .main) throws {
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.isCustom == false && $0.isOverride == false }
        )
        let toDelete = try modelContext.fetch(descriptor)
        for block in toDelete {
            modelContext.delete(block)
        }
        try modelContext.save()
        try seedIfNeeded(modelContext: modelContext, bundle: bundle)
        Logger.schedule.info("Reset to default schedule, deleted \(toDelete.count, privacy: .public), re-seeded")
    }

    static func loadDefaultScheduleFile(bundle: Bundle = .main) throws -> DefaultScheduleFile {
        guard let url = bundle.url(forResource: "default_schedule", withExtension: "json") else {
            throw ScheduleSeedError.resourceMissing
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DefaultScheduleFile.self, from: data)
        } catch let decodingError {
            throw ScheduleSeedError.decodingFailed(decodingError)
        }
    }
}
