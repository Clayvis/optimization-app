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

    /// Seeds the template schedule from the bundled JSON if no seeded (non-custom)
    /// template blocks exist yet. Idempotent across multiple launches. User-marked
    /// `isCustom` blocks do not block re-seeding so the schedule template chooser
    /// can apply a fresh template while preserving the user's custom rows.
    static func seedIfNeeded(modelContext: ModelContext, bundle: Bundle = .main) throws {
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.isOverride == false && $0.isCustom == false }
        )
        let existing = try modelContext.fetchCount(descriptor)
        guard existing == 0 else {
            Logger.schedule.info("Skipping seed: \(existing, privacy: .public) seeded blocks present")
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

    /// Wipes all non-custom ScheduleBlocks and seeds from the JSON resource named
    /// `resourceName` (no extension). `isCustom == true` blocks are preserved.
    /// Used by `ScheduleTemplateApplier` to load generic per-template seeds
    /// without going through Clay's personal `default_schedule.json`.
    static func resetToTemplate(resourceName: String,
                                modelContext: ModelContext,
                                bundle: Bundle = .main) throws {
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.isCustom == false && $0.isOverride == false }
        )
        let toDelete = try modelContext.fetch(descriptor)
        for block in toDelete {
            modelContext.delete(block)
        }
        try modelContext.save()

        let file = try loadScheduleFile(resourceName: resourceName, bundle: bundle)
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
        Logger.schedule.info(
            "Reset to template \(resourceName, privacy: .public): deleted \(toDelete.count, privacy: .public), seeded \(file.blocks.count, privacy: .public)"
        )
    }

    static func loadDefaultScheduleFile(bundle: Bundle = .main) throws -> DefaultScheduleFile {
        try loadScheduleFile(resourceName: "default_schedule", bundle: bundle)
    }

    /// M4.1 apply path. Wipes all non-custom non-override ScheduleBlocks then
    /// inserts the drafts. Preserves `isCustom == true` rows verbatim. Stamps
    /// `userProfile.lastGeneratedAt` and persists the user's chosen anchor
    /// events for future generations. Caller is responsible for marking the
    /// associated ScheduleGenerationRun row as accepted.
    static func applyDrafts(_ drafts: [ScheduleBlockDraft],
                            anchorEvents: [String],
                            modelContext: ModelContext,
                            now: Date = Date()) throws {
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.isCustom == false && $0.isOverride == false }
        )
        let toDelete = try modelContext.fetch(descriptor)
        for block in toDelete {
            modelContext.delete(block)
        }
        for draft in drafts {
            modelContext.insert(draft.toScheduleBlock())
        }

        if let profile = modelContext.fetchFirstOrNil(FetchDescriptor<UserProfile>()) {
            profile.lastGeneratedAt = now
            let csv = anchorEvents
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
            profile.anchorEventsCSV = csv
        }

        try modelContext.save()
        Logger.schedule.info(
            "Applied AI-generated drafts: removed \(toDelete.count, privacy: .public), inserted \(drafts.count, privacy: .public)"
        )
    }

    /// Generic loader for any bundled schedule JSON sharing the `DefaultScheduleFile`
    /// shape. Throws `resourceMissing` if the resource isn't in the bundle.
    static func loadScheduleFile(resourceName: String,
                                 bundle: Bundle = .main) throws -> DefaultScheduleFile {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw ScheduleSeedError.resourceMissing
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DefaultScheduleFile.self, from: data)
        } catch let decodingError {
            throw ScheduleSeedError.decodingFailed(decodingError)
        }
    }

    /// V11 loader for v2 parametric template JSONs (the four shipped
    /// templates: balanced, gym_focused, language_focused, fasting_focused).
    /// Used by tests and any caller that wants to inspect the template's
    /// shape without applying it.
    static func loadParametricScheduleFile(resourceName: String,
                                           bundle: Bundle = .main) throws -> ParametricScheduleFile {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw ScheduleSeedError.resourceMissing
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ParametricScheduleFile.self, from: data)
        } catch let decodingError {
            throw ScheduleSeedError.decodingFailed(decodingError)
        }
    }

    /// M5 parametric template application. Wipes non-custom non-override
    /// ScheduleBlocks then resolves the v2 template's anchor-based blocks
    /// against the user's chosen anchors before inserting. User-marked
    /// `isCustom` blocks are preserved verbatim so a re-apply respects the
    /// user's manual edits.
    ///
    /// Throws `decodingFailed` when the JSON isn't a v2 file (version != 2);
    /// the legacy `resetToTemplate` path stays available for v1 callers.
    static func resetToParametricTemplate(resourceName: String,
                                          anchors: SchedulePlanner.AnchorSet,
                                          modelContext: ModelContext,
                                          bundle: Bundle = .main) throws {
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.isCustom == false && $0.isOverride == false }
        )
        let toDelete = try modelContext.fetch(descriptor)
        for block in toDelete {
            modelContext.delete(block)
        }
        try modelContext.save()

        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw ScheduleSeedError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let file: ParametricScheduleFile
        do {
            file = try JSONDecoder().decode(ParametricScheduleFile.self, from: data)
        } catch {
            throw ScheduleSeedError.decodingFailed(error)
        }
        guard file.version == 2 else {
            throw ScheduleSeedError.decodingFailed(
                NSError(domain: "ScheduleSeed", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "expected parametric template version 2, got \(file.version)"
                ])
            )
        }

        let resolved = try SchedulePlanner.resolveAll(templateBlocks: file.blocks, anchors: anchors)
        for r in resolved {
            let blockType = BlockType(rawValue: r.type) ?? .other
            let block = ScheduleBlock(
                dayOfWeek: r.dayOfWeek,
                startTime: r.startHHMM,
                endTime: r.endHHMM,
                activity: r.activity,
                type: blockType,
                module: r.module
            )
            modelContext.insert(block)
        }
        try modelContext.save()
        Logger.schedule.info(
            "Applied parametric template \(resourceName, privacy: .public): wrote \(resolved.count, privacy: .public) blocks against training anchor \(anchors.trainingStartHHMM, privacy: .public)"
        )
    }
}
