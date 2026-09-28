import XCTest
import SwiftData
@testable import PersonalOptimization

// MARK: - Barcode normalization

final class BarcodeTests: XCTestCase {
    func test_checkDigitsForEachRetailFormat() {
        XCTAssertTrue(Barcode.isValidGTIN("4901234567894"))      // EAN-13
        XCTAssertFalse(Barcode.isValidGTIN("4901234567895"))     // one digit off
        XCTAssertTrue(Barcode.isValidGTIN("042100005264"))       // UPC-A
        XCTAssertTrue(Barcode.isValidGTIN("96385074"))           // EAN-8
        XCTAssertFalse(Barcode.isValidGTIN("12345"))
    }

    func test_upcEExpandsToItsUPCA() {
        XCTAssertEqual(Barcode.expandUPCE("04252614"), "042100005264")
        XCTAssertNil(Barcode.expandUPCE("24252614"), "UPC-E uses number system 0 or 1")
    }

    func test_equivalentSpellingsAreTriedCanonicalFirst() {
        XCTAssertEqual(Barcode.lookupKeys(for: "042100005264"), ["0042100005264", "042100005264"])
        XCTAssertEqual(Barcode.lookupKeys(for: "0042100005264"), ["0042100005264", "042100005264"])
        XCTAssertEqual(Barcode.lookupKeys(for: "04252614", isUPCE: true).first, "0042100005264")
        XCTAssertEqual(Barcode.lookupKeys(for: " 4901234567894 "), ["4901234567894"])
        XCTAssertEqual(Barcode.lookupKeys(for: "96385074"), ["96385074"])
    }

    func test_nonProductCodesHaveNoKeys() {
        XCTAssertTrue(Barcode.lookupKeys(for: "4901234567895").isEmpty, "Bad check digit")
        XCTAssertTrue(Barcode.lookupKeys(for: "SHIP-12345").isEmpty, "Code 128 shipping label")
        XCTAssertTrue(Barcode.lookupKeys(for: "").isEmpty)
    }
}

// MARK: - Open Food Facts parsing

final class OpenFoodFactsParserTests: XCTestCase {
    private func parse(_ json: String) throws -> ExternalFood? {
        try OpenFoodFactsProvider.parse(Data(json.utf8), barcode: "4901234567894")
    }

    func test_perServingLabelValuesWin() throws {
        let food = try XCTUnwrap(parse("""
        {"status":1,"product":{"code":"4901234567894","product_name":"Granola","brands":"Acme, Other",
         "serving_quantity":45,"serving_quantity_unit":"g","product_quantity":450,"product_quantity_unit":"g",
         "nutriments":{"energy-kcal_serving":200,"proteins_serving":6,"carbohydrates_serving":30,"fat_serving":7,
                       "fiber_serving":3,"sugars_serving":9,"energy-kcal_100g":444}}}
        """))
        XCTAssertEqual(food.name, "Granola")
        XCTAssertEqual(food.brand, "Acme")
        XCTAssertEqual(food.servingSize, 45)
        XCTAssertEqual(food.servingUnit, "g")
        XCTAssertEqual(food.servingsPerContainer, 10)
        XCTAssertEqual(food.macros, MacroTotals(calories: 200, protein: 6, carbs: 30, fat: 7, fiber: 3, sugar: 9))
        XCTAssertEqual(food.externalID, "4901234567894")
        XCTAssertTrue(food.isComplete)
    }

    func test_per100gValuesScaleToTheServing() throws {
        let food = try XCTUnwrap(parse("""
        {"status":1,"product":{"product_name":"Rice crackers","serving_quantity":30,
         "nutriments":{"energy-kcal_100g":400,"proteins_100g":10,"carbohydrates_100g":80,"fat_100g":"2.5"}}}
        """))
        let macros = try XCTUnwrap(food.macros)
        XCTAssertEqual(macros.calories, 120, accuracy: 0.001)
        XCTAssertEqual(macros.protein, 3, accuracy: 0.001)
        XCTAssertEqual(macros.carbs, 24, accuracy: 0.001)
        XCTAssertEqual(macros.fat, 0.75, accuracy: 0.001, "Numeric strings are read")
        XCTAssertNil(macros.fiber, "An absent figure stays unknown, not zero")
    }

    func test_kilojoulesOnlyConvertAndNoServingMeansPer100() throws {
        let food = try XCTUnwrap(parse("""
        {"status":1,"product":{"product_name":"Oat drink","product_quantity_unit":"ml",
         "nutriments":{"energy_100g":1674,"proteins_100g":1}}}
        """))
        XCTAssertEqual(food.servingSize, 100)
        XCTAssertEqual(food.servingUnit, "ml")
        XCTAssertEqual(try XCTUnwrap(food.macros).calories, 400.1, accuracy: 0.1)
    }

    func test_japaneseNameIsUsedWhenThatIsAllThereIs() throws {
        let food = try XCTUnwrap(parse("""
        {"status":1,"product":{"product_name":"","product_name_ja":"おにぎり","nutriments":{"energy-kcal_100g":180}}}
        """))
        XCTAssertEqual(food.name, "おにぎり")
    }

    func test_missingNutritionOrNameIsIncompleteNotGuessed() throws {
        let noFacts = try XCTUnwrap(parse(#"{"status":1,"product":{"product_name":"Mystery bar","nutriments":{}}}"#))
        XCTAssertNil(noFacts.macros)
        XCTAssertFalse(noFacts.isComplete)
        let noName = try XCTUnwrap(parse(#"{"status":1,"product":{"nutriments":{"energy-kcal_100g":100}}}"#))
        XCTAssertFalse(noName.isComplete)
    }

    func test_unknownProductIsNil() throws {
        XCTAssertNil(try parse(#"{"status":0,"status_verbose":"product not found"}"#))
    }

    func test_garbageIsMalformed() {
        XCTAssertThrowsError(try parse("<html>")) { XCTAssertEqual($0 as? FoodLookupError, .malformed) }
    }
}

// MARK: - Open Food Facts transport

/// Serves canned responses; nonisolated(unsafe) because URLProtocol is created
/// by the URL loading system, and tests set the handler before each request.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class OpenFoodFactsProviderTests: XCTestCase {
    private func provider() -> OpenFoodFactsProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OpenFoodFactsProvider(session: URLSession(configuration: configuration))
    }

    private func respond(status: Int, body: String) {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func test_requestSendsOnlyTheBarcodeAndIdentifiesTheApp() async throws {
        respond(status: 200, body: #"{"status":1,"product":{"product_name":"Granola","nutriments":{"energy-kcal_100g":444}}}"#)
        let food = try await provider().product(barcode: "4901234567894")
        XCTAssertEqual(food?.name, "Granola")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.host, "world.openfoodfacts.org")
        XCTAssertEqual(request.url?.path, "/api/v2/product/4901234567894.json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), OpenFoodFactsProvider.userAgent)
        XCTAssertNil(request.httpBody)
    }

    func test_notFoundServerErrorAndOfflineAreDistinct() async throws {
        respond(status: 404, body: #"{"status":0}"#)
        let missing = try await provider().product(barcode: "4901234567894")
        XCTAssertNil(missing, "404 means the product is not in the database")

        respond(status: 503, body: "")
        do { _ = try await provider().product(barcode: "4901234567894"); XCTFail("503 must throw") }
        catch { XCTAssertEqual(error as? FoodLookupError, .service(503)) }

        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await provider().product(barcode: "4901234567894"); XCTFail("Offline must throw") }
        catch { XCTAssertEqual(error as? FoodLookupError, .unreachable) }
    }
}

// MARK: - Lookup order and caching

/// Records every request; answers from a fixed table.
private final class FakeFoodProvider: FoodDatabaseProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [String] = []
    private let products: [String: ExternalFood]
    private let failure: FoodLookupError?
    let source: FoodSource = .openFoodFacts

    init(products: [String: ExternalFood] = [:], failure: FoodLookupError? = nil) {
        self.products = products
        self.failure = failure
    }

    var requests: [String] { lock.withLock { _requests } }

    func product(barcode: String) async throws -> ExternalFood? {
        lock.withLock { _requests.append(barcode) }
        if let failure { throw failure }
        return products[barcode]
    }
}

@MainActor
final class BarcodeFoodLookupTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var nutrition: NutritionService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        nutrition = NutritionService(modelContext: context, calendar: .current)
    }

    override func tearDown() async throws {
        nutrition = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    private let granola = ExternalFood(source: .openFoodFacts, externalID: "4901234567894", name: "Granola", brand: "Acme",
                                       servingSize: 45, servingUnit: "g", servingsPerContainer: 10,
                                       macros: MacroTotals(calories: 200, protein: 6, carbs: 30, fat: 7))

    private func lookup(_ provider: FakeFoodProvider) -> BarcodeFoodLookup {
        BarcodeFoodLookup(modelContext: context, nutrition: nutrition, providers: [provider])
    }

    func test_localFoodWinsWithoutTouchingTheNetwork() async throws {
        let mine = try nutrition.createFood(name: "My crackers", servingSize: 30, servingUnit: "g",
                                            macros: MacroTotals(calories: 120, protein: 3, carbs: 24, fat: 1),
                                            barcode: "0042100005264")
        let provider = FakeFoodProvider()
        guard case .found(let food, let cached) = try await lookup(provider).lookup("042100005264") else {
            return XCTFail("A UPC-A scan must find the EAN-13 spelling saved locally")
        }
        XCTAssertTrue(food === mine)
        XCTAssertTrue(cached)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func test_externalHitIsCachedAndNeverRefetched() async throws {
        let provider = FakeFoodProvider(products: ["4901234567894": granola])
        let service = lookup(provider)
        guard case .found(let food, let cached) = try await service.lookup("4901234567894") else {
            return XCTFail("Expected a database hit")
        }
        XCTAssertFalse(cached)
        XCTAssertEqual(food.sourceValue, .openFoodFacts)
        XCTAssertEqual(food.externalID, "4901234567894")
        XCTAssertEqual(food.barcode, "4901234567894")
        XCTAssertEqual(food.servingsPerContainer, 10)
        XCTAssertEqual(food.calories, 200)
        guard case .found(let again, let cachedAgain) = try await service.lookup("4901234567894") else {
            return XCTFail("Expected the cached food")
        }
        XCTAssertTrue(again === food)
        XCTAssertTrue(cachedAgain)
        XCTAssertEqual(provider.requests, ["4901234567894"], "One network request in total")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodItem>()), 1)
    }

    func test_unknownProductReportsTheCanonicalBarcode() async throws {
        let provider = FakeFoodProvider()
        guard case .notFound(let barcode) = try await lookup(provider).lookup("042100005264") else {
            return XCTFail("Expected not found")
        }
        XCTAssertEqual(barcode, "0042100005264")
        XCTAssertEqual(provider.requests, ["0042100005264", "042100005264"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodItem>()), 0)
    }

    func test_incompleteProductIsNotSaved() async throws {
        let bare = ExternalFood(source: .openFoodFacts, externalID: "4901234567894", name: "Mystery bar", brand: nil,
                                servingSize: 100, servingUnit: "g", servingsPerContainer: nil, macros: nil)
        guard case .incomplete(let product, let barcode) = try await lookup(FakeFoodProvider(products: ["4901234567894": bare]))
            .lookup("4901234567894") else { return XCTFail("Expected incomplete") }
        XCTAssertEqual(product.name, "Mystery bar")
        XCTAssertEqual(barcode, "4901234567894")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodItem>()), 0)
    }

    func test_invalidCodeAndOfflineFailWithoutSaving() async throws {
        let offline = FakeFoodProvider(failure: .unreachable)
        do { _ = try await lookup(offline).lookup("4901234567895"); XCTFail("Bad check digit must throw") }
        catch { XCTAssertEqual(error as? FoodLookupError, .invalidBarcode) }
        XCTAssertTrue(offline.requests.isEmpty, "No request for a code that is not a product barcode")
        do { _ = try await lookup(offline).lookup("4901234567894"); XCTFail("Offline must throw") }
        catch { XCTAssertEqual(error as? FoodLookupError, .unreachable) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodItem>()), 0)
    }

    func test_customFoodCreatedForAMissingBarcodeIsFoundNextTime() async throws {
        let provider = FakeFoodProvider()
        guard case .notFound(let barcode) = try await lookup(provider).lookup("4901234567894") else {
            return XCTFail("Expected not found")
        }
        _ = try nutrition.createFood(name: "Local bakery bread", servingSize: 1, servingUnit: "slice",
                                     macros: MacroTotals(calories: 90, protein: 3, carbs: 17, fat: 1), barcode: barcode)
        guard case .found(let food, true) = try await lookup(provider).lookup("4901234567894") else {
            return XCTFail("The user's own food must be found locally")
        }
        XCTAssertEqual(food.name, "Local bakery bread")
        XCTAssertEqual(provider.requests.count, 1)
    }
}
