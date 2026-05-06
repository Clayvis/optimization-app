import Foundation

struct LiftTemplate: Decodable, Sendable {
    let name: String
    let focus: String
    let exercises: [LiftTemplateExercise]
}

struct LiftTemplateExercise: Decodable, Sendable {
    let name: String
    let orderIndex: Int
    let targetSets: Int
    let targetReps: Int
}

struct LiftTemplatesFile: Decodable, Sendable {
    let version: Int
    let templates: [LiftTemplate]
}

enum LiftTemplatesError: LocalizedError {
    case resourceMissing
    case decodingFailed(Error)
    case templateNotFound(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing: return "lift_templates.json missing from app bundle"
        case .decodingFailed(let e): return "Failed to decode lift_templates.json: \(e.localizedDescription)"
        case .templateNotFound(let name): return "Lift template not found: \(name)"
        }
    }
}

enum LiftTemplatesLoader {
    static func load(bundle: Bundle = .main) throws -> LiftTemplatesFile {
        guard let url = bundle.url(forResource: "lift_templates", withExtension: "json") else {
            throw LiftTemplatesError.resourceMissing
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(LiftTemplatesFile.self, from: data)
        } catch {
            throw LiftTemplatesError.decodingFailed(error)
        }
    }

    static func template(named name: String, file: LiftTemplatesFile) throws -> LiftTemplate {
        guard let template = file.templates.first(where: { $0.name == name }) else {
            throw LiftTemplatesError.templateNotFound(name)
        }
        return template
    }
}
