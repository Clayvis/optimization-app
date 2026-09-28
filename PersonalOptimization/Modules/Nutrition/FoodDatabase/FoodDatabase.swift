import Foundation
import os

/// A packaged food from an external database, normalized to one serving.
/// `macros` is nil when the database has no usable nutrition facts; the user
/// then enters them from the label (never guessed).
struct ExternalFood: Equatable, Sendable {
    let source: FoodSource
    let externalID: String
    let name: String
    let brand: String?
    let servingSize: Double
    let servingUnit: String
    let servingsPerContainer: Double?
    let macros: MacroTotals?

    var isComplete: Bool {
        macros != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One external food database. Only the barcode leaves the device.
protocol FoodDatabaseProvider: Sendable {
    var source: FoodSource { get }
    /// Nil when the database has no product for the barcode. Throws
    /// `FoodLookupError` for transport, server or format failures.
    func product(barcode: String) async throws -> ExternalFood?
}

enum FoodLookupError: LocalizedError, Equatable {
    case invalidBarcode
    case unreachable
    case service(Int)
    case malformed

    var errorDescription: String? {
        switch self {
        case .invalidBarcode:
            return "That isn't a product barcode. Check the digits, or scan the barcode near the nutrition label."
        case .unreachable:
            return "Couldn't reach the food database. Check your connection, or add the food manually."
        case .service(let status):
            return "The food database didn't answer (error \(status)). Try again, or add the food manually."
        case .malformed:
            return "The food database sent data this app couldn't read. Add the food manually."
        }
    }
}

/// Providers in lookup order after the local catalog. FatSecret joins here once
/// the user supplies developer keys through Xcode Cloud environment variables
/// (never committed); see docs/planning/NUTRITION_PHASE3_BARCODE_HANDOFF_2026-09-28.md.
enum FoodDatabaseProviders {
    static func current() -> [any FoodDatabaseProvider] {
        // UI tests never touch the network; they seed local foods instead.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return [] }
        return [OpenFoodFactsProvider()]
    }
}

/// Open Food Facts product lookup (API v2, no key). Only the barcode is sent.
/// Data is under the Open Database License: show `attribution` wherever these
/// facts appear.
struct OpenFoodFactsProvider: FoodDatabaseProvider {
    static let attribution = "Nutrition facts from Open Food Facts, available under the Open Database License (ODbL)."
    /// Open Food Facts asks every client to identify itself.
    static let userAgent = "Optimization/1.0 (iOS; https://github.com/Clayvis/optimization-app)"
    static let fields = ["code", "product_name", "product_name_en", "product_name_ja", "generic_name",
                         "brands", "serving_size", "serving_quantity", "serving_quantity_unit",
                         "product_quantity", "product_quantity_unit", "nutriments"].joined(separator: ",")

    let session: URLSession
    var source: FoodSource { .openFoodFacts }

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func productURL(barcode: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "world.openfoodfacts.org"
        components.path = "/api/v2/product/\(barcode).json"
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        return components.url
    }

    func product(barcode: String) async throws -> ExternalFood? {
        guard Barcode.digits(barcode) != nil, let url = Self.productURL(barcode: barcode) else {
            throw FoodLookupError.invalidBarcode
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Logger.api.warning("Open Food Facts request failed: \(error.localizedDescription, privacy: .public)")
            throw FoodLookupError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw FoodLookupError.unreachable }
        // API v2 answers a missing product with 404 and status 0.
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw FoodLookupError.service(http.statusCode) }
        return try Self.parse(data, barcode: barcode)
    }

    /// Parses a v2 product response. Nil when the product is not in the
    /// database. Per-serving label values win; otherwise per-100 g values are
    /// scaled to the serving quantity, or kept per 100 g when there is none.
    /// Energy falls back from kcal to kJ / 4.184. Missing energy or name means
    /// incomplete (`macros == nil` or an empty name), never a guess.
    static func parse(_ data: Data, barcode: String) throws -> ExternalFood? {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch { throw FoodLookupError.malformed }
        guard let root = object as? [String: Any] else { throw FoodLookupError.malformed }
        if let status = number(root["status"]), status == 0 { return nil }
        guard let product = root["product"] as? [String: Any] else { return nil }

        let name = ["product_name", "product_name_en", "product_name_ja", "generic_name"]
            .compactMap { (product[$0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]

        let servingQuantity = number(product["serving_quantity"]).flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        let quantityUnit = (product["product_quantity_unit"] as? String).map(unit(from:)) ?? "g"
        let servingUnit = (product["serving_quantity_unit"] as? String).map(unit(from:))
            ?? (product["serving_size"] as? String).map(unit(from:)) ?? quantityUnit
        let factor = (servingQuantity ?? 100) / 100

        func value(_ key: String) -> Double? {
            if servingQuantity != nil, let perServing = number(nutriments["\(key)_serving"]) { return perServing }
            return number(nutriments["\(key)_100g"]).map { $0 * factor }
        }
        func energy() -> Double? {
            if servingQuantity != nil {
                if let kcal = number(nutriments["energy-kcal_serving"]) { return kcal }
                if let kj = number(nutriments["energy-kj_serving"]) ?? number(nutriments["energy_serving"]) { return kj / 4.184 }
            }
            if let kcal = number(nutriments["energy-kcal_100g"]) { return kcal * factor }
            if let kj = number(nutriments["energy-kj_100g"]) ?? number(nutriments["energy_100g"]) { return kj / 4.184 * factor }
            return nil
        }

        var macros: MacroTotals?
        if let calories = energy() {
            let candidate = MacroTotals(calories: calories,
                                        protein: value("proteins") ?? 0,
                                        carbs: value("carbohydrates") ?? 0,
                                        fat: value("fat") ?? 0,
                                        fiber: value("fiber"),
                                        sugar: value("sugars"))
            let all = [candidate.calories, candidate.protein, candidate.carbs, candidate.fat]
                + [candidate.fiber, candidate.sugar].compactMap { $0 }
            macros = all.allSatisfy { $0.isFinite && $0 >= 0 } ? candidate : nil
        }

        var perContainer: Double?
        if let servingQuantity, let total = number(product["product_quantity"]), total > 0, servingUnit == quantityUnit {
            perContainer = (total / servingQuantity * 10).rounded() / 10
        }
        let code = (product["code"] as? String) ?? (root["code"] as? String) ?? barcode
        return ExternalFood(source: .openFoodFacts, externalID: code, name: name, brand: brand,
                            servingSize: servingQuantity ?? 100, servingUnit: servingUnit,
                            servingsPerContainer: perContainer, macros: macros)
    }

    /// Open Food Facts mixes numbers and numeric strings.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let text as String:
            return Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }

    private static func unit(from text: String) -> String {
        let lowered = text.lowercased()
        if lowered.contains("ml") || lowered.contains("cl") || lowered == "l" { return "ml" }
        return "g"
    }
}
