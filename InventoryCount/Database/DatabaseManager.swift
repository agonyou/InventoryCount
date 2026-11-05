//  DatabaseManager.swift
//  Local-first data layer: three collections in the `inventory` scope, live queries,
//  CRUD with blobs, FTS, and a duplicate-row check for the Summary's Flagged list.

import Foundation
import CouchbaseLiteSwift

enum DBError: LocalizedError {
    case notOpen, notFound
    var errorDescription: String? {
        switch self { case .notOpen: return "Database is not open"; case .notFound: return "Document not found" }
    }
}

@MainActor
final class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()

    @Published private(set) var entries: [CountEntry] = []
    @Published private(set) var locations: [LocationRef] = []
    @Published private(set) var catalog: [CatalogItem] = []
    @Published private(set) var reviews: [ReviewDoc] = []
    @Published private(set) var proposals: [ProposalDoc] = []
    @Published private(set) var stockRecords: [StockRecord] = [] {
        didSet {
            // Each store's records with their names split into words once, for closest-name matching.
            stockWords = Dictionary(grouping: stockRecords.map { ($0, ProductMatcher.tokens($0.itemName)) }, by: { $0.0.storeID })
                .mapValues { $0.map { (item: $0.0, words: $0.1) } }
        }
    }
    private var stockWords: [String: [(item: StockRecord, words: Set<String>)]] = [:]
    @Published private(set) var shipments: [Shipment] = []
    @Published private(set) var trucks: [Truck] = []
    @Published private(set) var products: [StoreProduct] = [] {
        didSet { productIndex = ProductIndex(products) }
    }
    private var productIndex = ProductIndex([])
    @Published private(set) var errorMessage: String?

    private(set) var database: Database?
    private(set) var counts: Collection?
    private(set) var catalogColl: Collection?
    private(set) var locationsColl: Collection?
    private(set) var reviewsColl: Collection?
    private(set) var proposalsColl: Collection?
    private(set) var trucksColl: Collection?
    private(set) var shipmentsColl: Collection?
    private var tokens: [ListenerToken] = []

    var allCollections: [Collection] { [counts, catalogColl, locationsColl, reviewsColl, proposalsColl, trucksColl, shipmentsColl].compactMap { $0 } }

    private init() {}

    // MARK: - Open / close

    func open() throws {
        if database != nil { return }
        SyncLogs.start()   // on already from launch; here too in case open() runs first (tests)
        let db = try Database(name: AppConfig.databaseName)
        let c = try db.createCollection(name: AppConfig.countsCollection, scope: AppConfig.scopeName)
        let k = try db.createCollection(name: AppConfig.catalogCollection, scope: AppConfig.scopeName)
        let l = try db.createCollection(name: AppConfig.locationsCollection, scope: AppConfig.scopeName)
        let r = try db.createCollection(name: AppConfig.reviewsCollection, scope: AppConfig.scopeName)
        let p = try db.createCollection(name: AppConfig.proposalsCollection, scope: AppConfig.scopeName)
        let t = try db.createCollection(name: AppConfig.trucksCollection, scope: AppConfig.scopeName)
        let sh = try db.createCollection(name: AppConfig.shipmentsCollection, scope: AppConfig.scopeName)

        try c.createIndex(withName: "countsTypeCaptured", config: ValueIndexConfiguration(["type", "captured_at"]))
        try c.createIndex(withName: "countsStoreSku", config: ValueIndexConfiguration(["store_id", "sku"]))
        try c.createIndex(withName: "countsFTS",
                          config: FullTextIndexConfiguration(["item_name", "annotation", "attributes"]))
        try k.createIndex(withName: "catalogType", config: ValueIndexConfiguration(["type", "code.value"]))
        try l.createIndex(withName: "locationsType", config: ValueIndexConfiguration(["type", "name"]))
        try r.createIndex(withName: "reviewsTypeTeamDay", config: ValueIndexConfiguration(["type", "team", "day"]))
        try p.createIndex(withName: "proposalsTypeDay", config: ValueIndexConfiguration(["type", "day"]))

        database = db; counts = c; catalogColl = k; locationsColl = l; reviewsColl = r
        proposalsColl = p; trucksColl = t; shipmentsColl = sh
        try startLiveQueries()
    }

    func close() {
        tokens = []
        entries = []; locations = []; catalog = []; reviews = []; products = []; proposals = []; stockRecords = []; shipments = []; trucks = []
        try? database?.close()
        database = nil; counts = nil; catalogColl = nil; locationsColl = nil; reviewsColl = nil
        proposalsColl = nil; trucksColl = nil; shipmentsColl = nil
    }

    // MARK: - Live queries

    private func liveQuery<T>(_ sql: String, collection: String, map: @escaping (String, [String: Any]) -> T?,
                              assign: @escaping ([T]) -> Void) throws {
        guard let db = database else { throw DBError.notOpen }
        let q = try db.createQuery(sql)
        let token = q.addChangeListener { [weak self] change in
            guard let self else { return }
            if let error = change.error {
                Task { @MainActor in self.errorMessage = error.localizedDescription }
                return
            }
            var items: [T] = []
            if let results = change.results {
                for row in results {
                    let id = row.string(forKey: "id") ?? ""
                    if let dict = row.dictionary(forKey: collection)?.toDictionary(), let item = map(id, dict) {
                        items.append(item)
                    }
                }
            }
            Task { @MainActor in assign(items) }
        }
        tokens.append(token)
        _ = try q.execute()   // the listener delivers the rows; this only starts the query
    }

    private func startLiveQueries() throws {
        let s = AppConfig.scopeName
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.countsCollection) WHERE type = 'count' AND captured_by IS VALUED ORDER BY captured_at DESC",
                      collection: AppConfig.countsCollection, map: CountEntry.init(id:dictionary:)) { [weak self] in self?.entries = $0 }
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.locationsCollection) WHERE type = 'location' ORDER BY name ASC",
                      collection: AppConfig.locationsCollection, map: LocationRef.init(id:dictionary:)) { [weak self] in self?.locations = $0 }
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.catalogCollection) WHERE type = 'catalog_item' ORDER BY name ASC",
                      collection: AppConfig.catalogCollection, map: CatalogItem.init(id:dictionary:)) { [weak self] in self?.catalog = $0 }
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.catalogCollection) WHERE sku IS VALUED AND team IS MISSING",
                      collection: AppConfig.catalogCollection, map: StoreProduct.init(id:dictionary:)) { [weak self] in self?.products = $0 }
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.reviewsCollection) WHERE type = 'review' ORDER BY day DESC",
                      collection: AppConfig.reviewsCollection, map: ReviewDoc.init(id:dictionary:)) { [weak self] in self?.reviews = $0 }
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.proposalsCollection) WHERE type = 'proposal' ORDER BY day DESC",
                      collection: AppConfig.proposalsCollection, map: ProposalDoc.init(id:dictionary:)) { [weak self] in self?.proposals = $0 }
        // The store system's stock records share counts with phone counts; a stock record has a
        // numeric stock_quantity and never captured_by (as in the counts access rule).
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.countsCollection) WHERE stock_quantity IS VALUED AND store_id IS VALUED AND captured_by IS NOT VALUED",
                      collection: AppConfig.countsCollection, map: StockRecord.init(id:dictionary:)) { [weak self] in self?.stockRecords = $0 }
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.shipmentsCollection) WHERE type = 'shipment'",
                      collection: AppConfig.shipmentsCollection, map: Shipment.init(id:dictionary:)) { [weak self] in self?.shipments = $0 }
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.trucksCollection) WHERE type = 'truck' ORDER BY truck_id",
                      collection: AppConfig.trucksCollection, map: Truck.init(id:dictionary:)) { [weak self] in self?.trucks = $0 }
    }

    // MARK: - Count entries

    func save(_ entry: CountEntry, photo: Data? = nil) throws {
        guard let c = counts else { throw DBError.notOpen }
        let doc = (try c.document(id: entry.id))?.toMutable() ?? MutableDocument(id: entry.id)
        for (k, v) in entry.toDictionary() { doc.setValue(v, forKey: k) }
        if let photo { doc.setBlob(Blob(contentType: "image/jpeg", data: photo), forKey: "photo") }
        try c.save(document: doc)
    }

    func saveAll(_ newEntries: [CountEntry], photo: Data? = nil) throws {
        guard let db = database else { throw DBError.notOpen }
        try db.inBatch { for e in newEntries { try save(e, photo: photo) } }
    }

    func delete(_ entry: CountEntry) throws {
        guard let c = counts, let doc = try c.document(id: entry.id) else { throw DBError.notFound }
        try c.delete(document: doc)
    }

    func photo(for entry: CountEntry) -> Data? {
        guard let c = counts, let doc = try? c.document(id: entry.id) else { return nil }
        return doc.blob(forKey: "photo")?.content
    }

    // MARK: - Catalog

    /// The team's name for a code: the same code, else the same GTIN (a UPC-A read as EAN-13).
    func catalogItem(for code: ScannedCode) -> CatalogItem? {
        if let exact = catalog.first(where: { $0.code == code }) { return exact }
        guard let gtin = GTIN.normalize(code) else { return nil }
        return catalog.first { GTIN.normalize($0.code) == gtin }
    }

    /// The store system's product for a scanned code, matched as GTIN-13.
    func product(for code: ScannedCode) -> StoreProduct? {
        GTIN.normalize(code).flatMap { productIndex.byGTIN[$0] }
    }

    /// The store system's product with exactly this name (any case), when only one has it.
    func product(named name: String) -> StoreProduct? {
        productIndex.byName[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// Look up a product by name, on the phone (works offline). Every word typed must start a word
    /// of the name, brand or category; 6 or more digits search the SKU and barcode instead. Whole-word
    /// matches first, then items this store stocks, by the store's 30-day sales.
    func searchProducts(_ query: String, store: String?, limit: Int = 25) -> (results: [StoreProduct], total: Int) {
        let q = query.trimmingCharacters(in: .whitespaces)
        let digits = q.filter(\.isNumber)
        let stock = store.map { s in Dictionary(stockRecords.filter { $0.storeID == s }.map { ($0.sku, $0) }, uniquingKeysWith: { a, _ in a }) } ?? [:]
        var hits: [(p: StoreProduct, exact: Int, sales: Int)] = []
        if digits.count >= 6, digits.count == q.filter({ !$0.isWhitespace }).count {
            let gtin = GTIN.normalize(digits)
            for p in products where p.sku.contains(digits) || p.code?.value.contains(digits) == true
                || (gtin != nil && p.code.flatMap(GTIN.normalize) == gtin) {
                hits.append((p, 1, stock[p.sku]?.sales30d ?? -1))
            }
        } else {
            let words = ProductMatcher.tokens(q)
            guard !words.isEmpty else { return ([], 0) }
            for (p, productWords) in productIndex.searchable {
                var exact = 0
                let all = words.allSatisfy { w in
                    if productWords.contains(w) { exact += 1; return true }
                    return productWords.contains { $0.hasPrefix(w) }
                }
                if all { hits.append((p, exact, stock[p.sku]?.sales30d ?? -1)) }
            }
        }
        hits.sort { a, b in
            if a.exact != b.exact { return a.exact > b.exact }
            if a.sales != b.sales { return a.sales > b.sales }
            return a.p.name < b.p.name
        }
        return (hits.prefix(limit).map(\.p), hits.count)
    }

    /// A name for a scanned code without asking the counter: team catalog, then store products.
    func productName(for code: ScannedCode) -> (name: String, attributes: String)? {
        if let c = catalogItem(for: code) { return (c.name, c.attributes) }
        if let p = product(for: code) { return (p.name, [p.brand, p.department].filter { !$0.isEmpty }.joined(separator: " · ")) }
        return nil
    }

    func save(_ item: CatalogItem) throws {
        guard let k = catalogColl else { throw DBError.notOpen }
        let doc = (try k.document(id: item.id))?.toMutable() ?? MutableDocument(id: item.id)
        for (kk, v) in item.toDictionary() { doc.setValue(v, forKey: kk) }
        try k.save(document: doc)
    }

    // MARK: - Store stock

    /// The store system's stock records for one store.
    func stock(store: String) -> [StockRecord] { stockRecords.filter { $0.storeID == store } }

    /// The store system's record for what a count is of: same store, by sku, else by exact name.
    func systemStock(store: String?, sku: String?, itemName: String) -> StockRecord? {
        guard let store else { return nil }
        let name = itemName.trimmingCharacters(in: .whitespaces)
        if let sku, let bySku = stockRecords.first(where: { $0.storeID == store && $0.sku == sku }) { return bySku }
        guard !name.isEmpty else { return nil }
        let sku = product(named: name)?.sku
        return stockRecords.first { $0.storeID == store && ($0.sku == sku || $0.itemName.caseInsensitiveCompare(name) == .orderedSame) }
    }

    func systemStock(for e: CountEntry) -> StockRecord? {
        systemStock(store: e.storeID ?? AppConfig.currentStoreID, sku: e.sku, itemName: e.itemName)
    }

    /// What a count is of, for comparing on the spot: by sku or exact name, else the closest name
    /// among the store's own items. A closest match is only shown, never written to the count.
    func stockMatch(store: String?, sku: String?, itemName: String) -> StockMatch {
        guard let store else { return .none }
        if let exact = systemStock(store: store, sku: sku, itemName: itemName) { return .exact(exact) }
        switch ProductMatcher.match(itemName, in: stockWords[store] ?? []) {
        case .one(let r): return .closest(r)
        case .several(let n): return .several(n)
        case .none: return .none
        }
    }

    func stockMatch(for e: CountEntry) -> StockMatch {
        stockMatch(store: e.storeID ?? AppConfig.currentStoreID, sku: e.sku, itemName: e.itemName)
    }

    // MARK: - Nomad's decisions

    /// The newest approved proposal of each kind this store's crew should see: the purchase order,
    /// transfers, count check, then cold-chain alerts.
    func nomadDecisions(store: String?) -> [ProposalDoc] {
        var newest: [ProposalDoc.Kind: ProposalDoc] = [:]
        for p in proposals where p.isFor(store: store) {
            if let seen = newest[p.kind], seen.day >= p.day { continue }
            newest[p.kind] = p
        }
        let order: [ProposalDoc.Kind] = [.purchaseOrder, .replenishment, .countCheck, .coldChainAlert, .shiftSummary]
        return order.compactMap { newest[$0] }
    }

    // MARK: - Locations

    func location(forQR qr: String) -> LocationRef? { locations.first { $0.qr == qr && !qr.isEmpty } }

    func save(_ location: LocationRef) throws {
        guard let l = locationsColl else { throw DBError.notOpen }
        let doc = (try l.document(id: location.id))?.toMutable() ?? MutableDocument(id: location.id)
        for (k, v) in location.toDictionary() { doc.setValue(v, forKey: k) }
        try l.save(document: doc)
    }

    func delete(_ location: LocationRef) throws {
        guard let l = locationsColl, let doc = try l.document(id: location.id) else { throw DBError.notFound }
        try l.delete(document: doc)
    }

    // MARK: - Review / duplicates ("same bin counted twice" → both rows kept, flagged)

    /// Rows with the same item + location captured by different devices.
    func duplicateGroups() -> [[CountEntry]] {
        let rows = entries.filter { $0.kind == .entry }
        let grouped = Dictionary(grouping: rows) { "\($0.itemName.lowercased())|\($0.location.display.lowercased())" }
        return grouped.values
            .filter { Set($0.map(\.capturedBy)).count > 1 }
            .map { $0.sorted { $0.capturedAt < $1.capturedAt } }
            .sorted { ($0.first?.capturedAt ?? .distantPast) > ($1.first?.capturedAt ?? .distantPast) }
    }

    var flagged: [CountEntry] {
        let dupIDs = Set(duplicateGroups().flatMap { $0 }.map(\.id))
        return entries.filter { $0.kind == .entry && ($0.needsReview || $0.countIsEstimate || dupIDs.contains($0.id)) }
    }

    /// Phone counts on this device; not the store system's stock records, which share the collection.
    var localEntryCount: Int {
        guard let db = database,
              let q = try? db.createQuery("SELECT COUNT(*) AS n FROM \(AppConfig.scopeName).\(AppConfig.countsCollection) WHERE captured_by IS VALUED"),
              let row = try? q.execute().next() else { return 0 }
        return row.int(forKey: "n")
    }
}

/// Store products by GTIN-13 and by lowercased name (names shared by two SKUs are left out,
/// so a spoken name never picks one of them at random).
private struct ProductIndex {
    var byGTIN: [String: StoreProduct] = [:]
    var byName: [String: StoreProduct] = [:]
    /// Each product with the words of its name, brand and category, for Look up a product.
    var searchable: [(product: StoreProduct, words: Set<String>)] = []

    init(_ products: [StoreProduct]) {
        var ambiguous: Set<String> = []
        searchable = products.map { ($0, ProductMatcher.tokens("\($0.name) \($0.brand) \($0.category)")) }
        for p in products {
            if let code = p.code, let gtin = GTIN.normalize(code) { byGTIN[gtin] = p }
            let key = p.name.lowercased()
            if let seen = byName[key], seen.sku != p.sku { ambiguous.insert(key) }
            byName[key] = p
        }
        for key in ambiguous { byName[key] = nil }
    }
}
