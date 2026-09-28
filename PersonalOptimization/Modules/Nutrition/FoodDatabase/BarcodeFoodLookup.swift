import Foundation
import SwiftData

/// Barcode to food: the local catalog first (offline, and never re-fetched),
/// then each external provider in order. An external hit is saved as a
/// FoodItem with its source, external ID and canonical barcode, so the next
/// scan of the same product is local.
@MainActor
final class BarcodeFoodLookup {
    enum Outcome {
        /// `cached` is true when the food was already in the local catalog.
        case found(FoodItem, cached: Bool)
        /// The product exists but lacks a name or nutrition facts.
        case incomplete(ExternalFood, barcode: String)
        case notFound(barcode: String)
    }

    private let modelContext: ModelContext
    private let nutrition: NutritionService
    private let providers: [any FoodDatabaseProvider]

    init(modelContext: ModelContext, nutrition: NutritionService, providers: [any FoodDatabaseProvider]) {
        self.modelContext = modelContext
        self.nutrition = nutrition
        self.providers = providers
    }

    static func forUser(modelContext: ModelContext) -> BarcodeFoodLookup {
        BarcodeFoodLookup(modelContext: modelContext,
                          nutrition: NutritionService.forUser(modelContext: modelContext),
                          providers: FoodDatabaseProviders.current())
    }

    /// Throws `FoodLookupError.invalidBarcode` before any network call for a
    /// non-product code, provider errors for failed lookups, and store errors.
    func lookup(_ raw: String, isUPCE: Bool = false) async throws -> Outcome {
        let keys = Barcode.lookupKeys(for: raw, isUPCE: isUPCE)
        guard let canonical = keys.first else { throw FoodLookupError.invalidBarcode }
        if let local = try localFood(matching: keys) { return .found(local, cached: true) }
        for provider in providers {
            // The canonical EAN-13 and its UPC-A spelling cover nearly every product.
            for key in keys.prefix(2) {
                guard let product = try await provider.product(barcode: key) else { continue }
                // Another scan may have saved the same product while this one waited.
                if let local = try localFood(matching: keys) { return .found(local, cached: true) }
                guard product.isComplete, let macros = product.macros else {
                    return .incomplete(product, barcode: canonical)
                }
                let food = try nutrition.createFood(name: product.name, brand: product.brand,
                                                    servingSize: product.servingSize, servingUnit: product.servingUnit,
                                                    macros: macros, source: product.source, barcode: canonical,
                                                    externalID: product.externalID,
                                                    servingsPerContainer: product.servingsPerContainer)
                return .found(food, cached: false)
            }
        }
        return .notFound(barcode: canonical)
    }

    /// Foods carrying any equivalent spelling of the barcode, most used first.
    private func localFood(matching keys: [String]) throws -> FoodItem? {
        let foods = try modelContext.fetch(FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.barcode != nil },
            sortBy: [SortDescriptor(\.useCount, order: .reverse)]))
        return foods.first { food in food.barcode.map { keys.contains($0) } ?? false }
    }
}
