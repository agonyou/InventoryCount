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
    @Published private(set) var catalogue: [CatalogueItem] = []
    @Published private(set) var errorMessage: String?

    private(set) var database: Database?
    private(set) var counts: Collection?
    private(set) var catalogueColl: Collection?
    private(set) var locationsColl: Collection?
    private var tokens: [ListenerToken] = []

    var allCollections: [Collection] { [counts, catalogueColl, locationsColl].compactMap { $0 } }

    private init() {}

    // MARK: - Open / close

    func open() throws {
        if database != nil { return }
        let db = try Database(name: AppConfig.databaseName)
        let c = try db.createCollection(name: AppConfig.countsCollection, scope: AppConfig.scopeName)
        let k = try db.createCollection(name: AppConfig.cataloguesCollection, scope: AppConfig.scopeName)
        let l = try db.createCollection(name: AppConfig.locationsCollection, scope: AppConfig.scopeName)

        try c.createIndex(withName: "countsTypeCaptured", config: ValueIndexConfiguration(["type", "captured_at"]))
        try c.createIndex(withName: "countsFTS",
                          config: FullTextIndexConfiguration(["item_name", "annotation", "attributes"]))
        try k.createIndex(withName: "catalogueType", config: ValueIndexConfiguration(["type", "code.value"]))
        try l.createIndex(withName: "locationsType", config: ValueIndexConfiguration(["type", "name"]))

        database = db; counts = c; catalogueColl = k; locationsColl = l
        try startLiveQueries()
    }

    func close() {
        tokens = []
        entries = []; locations = []; catalogue = []
        try? database?.close()
        database = nil; counts = nil; catalogueColl = nil; locationsColl = nil
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
        try q.execute()
    }

    private func startLiveQueries() throws {
        let s = AppConfig.scopeName
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.countsCollection) WHERE type = 'count' ORDER BY captured_at DESC",
                      collection: AppConfig.countsCollection, map: CountEntry.init(id:dictionary:)) { [weak self] in self?.entries = $0 }
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.locationsCollection) WHERE type = 'location' ORDER BY name ASC",
                      collection: AppConfig.locationsCollection, map: LocationRef.init(id:dictionary:)) { [weak self] in self?.locations = $0 }
        try liveQuery("SELECT META().id AS id, * FROM \(s).\(AppConfig.cataloguesCollection) WHERE type = 'catalogue_item' ORDER BY name ASC",
                      collection: AppConfig.cataloguesCollection, map: CatalogueItem.init(id:dictionary:)) { [weak self] in self?.catalogue = $0 }
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

    // MARK: - Catalogue

    func catalogueItem(for code: ScannedCode) -> CatalogueItem? {
        catalogue.first { $0.code == code }
    }

    func save(_ item: CatalogueItem) throws {
        guard let k = catalogueColl else { throw DBError.notOpen }
        let doc = (try k.document(id: item.id))?.toMutable() ?? MutableDocument(id: item.id)
        for (kk, v) in item.toDictionary() { doc.setValue(v, forKey: kk) }
        try k.save(document: doc)
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

    var localEntryCount: Int { Int(counts?.count ?? 0) }
}
