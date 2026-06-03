import Foundation

public enum ZoteroSQLiteReaderError: Error, Equatable, Sendable {
    case missingDatabase(String)
    case sqliteUnavailable
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case unsupportedSchema(ZoteroSchemaStatus)
}

#if canImport(SQLite3)
import SQLite3

private let requiredZoteroColumns: [String: [String]] = [
    "items": ["itemID", "itemTypeID", "key", "dateAdded", "dateModified"],
    "itemTypes": ["itemTypeID", "typeName"],
    "fields": ["fieldID", "fieldName"],
    "itemData": ["itemID", "fieldID", "valueID"],
    "itemDataValues": ["valueID", "value"],
    "collections": ["collectionID", "collectionName", "parentCollectionID", "key"],
    "collectionItems": ["collectionID", "itemID"],
    "tags": ["tagID", "name"],
    "itemTags": ["itemID", "tagID"],
    "creators": ["creatorID", "firstName", "lastName", "fieldMode"],
    "itemCreators": ["itemID", "creatorID", "creatorTypeID", "orderIndex"],
    "creatorTypes": ["creatorTypeID", "creatorType"],
    "itemAttachments": ["itemID", "parentItemID", "contentType", "path"]
]

public actor ZoteroSQLiteReader {
    private let configuration: ZoteroLibraryConfiguration

    public init(configuration: ZoteroLibraryConfiguration) throws {
        guard FileManager.default.fileExists(atPath: configuration.databaseURL.path) else {
            throw ZoteroSQLiteReaderError.missingDatabase(configuration.databaseURL.path)
        }
        self.configuration = configuration
    }

    public func schemaStatus() async throws -> ZoteroSchemaStatus {
        let existingTables = try await query("SELECT name FROM sqlite_master WHERE type = 'table'") { statement in
            var tables = Set<String>()
            while try statement.step() {
                tables.insert(statement.string("name"))
            }
            return tables
        }
        let missingTables = requiredZoteroColumns.keys.sorted().filter { !existingTables.contains($0) }
        var missingColumns: [String: [String]] = [:]
        for (table, requiredColumns) in requiredZoteroColumns where existingTables.contains(table) {
            let existingColumns = try await columns(in: table)
            let missing = requiredColumns.filter { !existingColumns.contains($0) }
            if !missing.isEmpty {
                missingColumns[table] = missing
            }
        }
        return ZoteroSchemaStatus(missingTables: missingTables, missingColumns: missingColumns)
    }

    public func collections() async throws -> [ZoteroCollection] {
        try await ensureReadableSchema()
        let sql = """
        SELECT collectionID, key, collectionName, parentCollectionID
        FROM collections
        ORDER BY collectionName COLLATE NOCASE
        """
        return try await query(sql) { statement in
            var rows: [ZoteroCollection] = []
            while try statement.step() {
                rows.append(statement.zoteroCollection())
            }
            return rows
        }
    }

    public func items(limit: Int = 250, collectionID: Int64? = nil) async throws -> [ZoteroItem] {
        try await ensureReadableSchema()
        let hasDeletedItems = try await tableExists("deletedItems")
        var bindings: [ZoteroSQLiteBinding] = []
        var collectionPredicate = ""
        if let collectionID {
            collectionPredicate = "AND EXISTS (SELECT 1 FROM collectionItems ci WHERE ci.itemID = i.itemID AND ci.collectionID = ?)"
            bindings.append(.int64(collectionID))
        }
        bindings.append(.int64(Int64(limit)))
        let deletedJoin = hasDeletedItems ? "LEFT JOIN deletedItems di ON di.itemID = i.itemID" : ""
        let deletedPredicate = hasDeletedItems ? "AND di.itemID IS NULL" : ""

        let sql = """
        SELECT i.itemID, i.key, it.typeName, i.dateAdded, i.dateModified
        FROM items i
        JOIN itemTypes it ON it.itemTypeID = i.itemTypeID
        \(deletedJoin)
        WHERE it.typeName NOT IN ('attachment', 'note', 'annotation')
          \(deletedPredicate)
          \(collectionPredicate)
        ORDER BY i.dateModified DESC, i.dateAdded DESC
        LIMIT ?
        """
        let baseRows = try await query(sql, bindings: bindings) { statement in
            var rows: [ZoteroBaseItemRow] = []
            while try statement.step() {
                rows.append(
                    ZoteroBaseItemRow(
                        id: statement.int64("itemID"),
                        key: statement.string("key"),
                        itemType: statement.string("typeName"),
                        dateAdded: statement.optionalString("dateAdded"),
                        dateModified: statement.optionalString("dateModified")
                    )
                )
            }
            return rows
        }

        let itemIDs = baseRows.map(\.id)
        let fields = try await fields(for: itemIDs)
        let collectionsByItem = try await collections(for: itemIDs)
        let tagsByItem = try await tags(for: itemIDs)
        let creatorsByItem = try await creators(for: itemIDs)
        let attachmentsByItem = try await attachments(for: itemIDs)

        return baseRows.map { row in
            let itemFields = fields[row.id] ?? [:]
            let arxiv = ZoteroArXivExtractor.extract(
                from: [
                    ("extra", itemFields["extra"]),
                    ("url", itemFields["url"]),
                    ("DOI", itemFields["DOI"]),
                    ("title", itemFields["title"])
                ]
            )
            return ZoteroItem(
                id: row.id,
                key: row.key,
                itemType: row.itemType,
                title: itemFields["title"],
                abstractNote: itemFields["abstractNote"],
                date: itemFields["date"],
                doi: itemFields["DOI"],
                url: itemFields["url"],
                extra: itemFields["extra"],
                libraryCatalog: itemFields["libraryCatalog"],
                collections: collectionsByItem[row.id] ?? [],
                tags: tagsByItem[row.id] ?? [],
                creators: creatorsByItem[row.id] ?? [],
                attachments: attachmentsByItem[row.id] ?? [],
                arxiv: arxiv,
                dateAdded: row.dateAdded,
                dateModified: row.dateModified
            )
        }
    }

    private func ensureReadableSchema() async throws {
        let status = try await schemaStatus()
        guard status.isReadable else {
            throw ZoteroSQLiteReaderError.unsupportedSchema(status)
        }
    }

    private func columns(in table: String) async throws -> Set<String> {
        try await query("PRAGMA table_info(\(table))") { statement in
            var columns = Set<String>()
            while try statement.step() {
                columns.insert(statement.string("name"))
            }
            return columns
        }
    }

    private func tableExists(_ tableName: String) async throws -> Bool {
        try await query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
            bindings: [.text(tableName)]
        ) { statement in
            try statement.step()
        }
    }

    private func fields(for itemIDs: [Int64]) async throws -> [Int64: [String: String]] {
        guard !itemIDs.isEmpty else { return [:] }
        let placeholders = Self.placeholders(count: itemIDs.count)
        let sql = """
        SELECT d.itemID, f.fieldName, v.value
        FROM itemData d
        JOIN fields f ON f.fieldID = d.fieldID
        JOIN itemDataValues v ON v.valueID = d.valueID
        WHERE d.itemID IN (\(placeholders))
        """
        return try await query(sql, bindings: itemIDs.map { .int64($0) }) { statement in
            var fieldsByItem: [Int64: [String: String]] = [:]
            while try statement.step() {
                fieldsByItem[statement.int64("itemID"), default: [:]][statement.string("fieldName")] = statement.string("value")
            }
            return fieldsByItem
        }
    }

    private func collections(for itemIDs: [Int64]) async throws -> [Int64: [ZoteroCollection]] {
        guard !itemIDs.isEmpty else { return [:] }
        let placeholders = Self.placeholders(count: itemIDs.count)
        let sql = """
        SELECT ci.itemID, c.collectionID, c.key, c.collectionName, c.parentCollectionID
        FROM collectionItems ci
        JOIN collections c ON c.collectionID = ci.collectionID
        WHERE ci.itemID IN (\(placeholders))
        ORDER BY c.collectionName COLLATE NOCASE
        """
        return try await query(sql, bindings: itemIDs.map { .int64($0) }) { statement in
            var rows: [Int64: [ZoteroCollection]] = [:]
            while try statement.step() {
                rows[statement.int64("itemID"), default: []].append(statement.zoteroCollection())
            }
            return rows
        }
    }

    private func tags(for itemIDs: [Int64]) async throws -> [Int64: [String]] {
        guard !itemIDs.isEmpty else { return [:] }
        let placeholders = Self.placeholders(count: itemIDs.count)
        let sql = """
        SELECT it.itemID, t.name
        FROM itemTags it
        JOIN tags t ON t.tagID = it.tagID
        WHERE it.itemID IN (\(placeholders))
        ORDER BY t.name COLLATE NOCASE
        """
        return try await query(sql, bindings: itemIDs.map { .int64($0) }) { statement in
            var rows: [Int64: [String]] = [:]
            while try statement.step() {
                rows[statement.int64("itemID"), default: []].append(statement.string("name"))
            }
            return rows
        }
    }

    private func creators(for itemIDs: [Int64]) async throws -> [Int64: [ZoteroCreator]] {
        guard !itemIDs.isEmpty else { return [:] }
        let placeholders = Self.placeholders(count: itemIDs.count)
        let sql = """
        SELECT ic.itemID, c.firstName, c.lastName, c.fieldMode, ct.creatorType
        FROM itemCreators ic
        JOIN creators c ON c.creatorID = ic.creatorID
        JOIN creatorTypes ct ON ct.creatorTypeID = ic.creatorTypeID
        WHERE ic.itemID IN (\(placeholders))
        ORDER BY ic.itemID, ic.orderIndex
        """
        return try await query(sql, bindings: itemIDs.map { .int64($0) }) { statement in
            var rows: [Int64: [ZoteroCreator]] = [:]
            while try statement.step() {
                rows[statement.int64("itemID"), default: []].append(statement.zoteroCreator())
            }
            return rows
        }
    }

    private func attachments(for itemIDs: [Int64]) async throws -> [Int64: [ZoteroAttachment]] {
        guard !itemIDs.isEmpty else { return [:] }
        let placeholders = Self.placeholders(count: itemIDs.count)
        let sql = """
        SELECT
          a.parentItemID,
          i.itemID,
          i.key,
          a.contentType,
          a.path
        FROM itemAttachments a
        JOIN items i ON i.itemID = a.itemID
        WHERE a.parentItemID IN (\(placeholders))
        ORDER BY i.dateModified DESC
        """
        return try await query(sql, bindings: itemIDs.map { .int64($0) }) { statement in
            var rows: [Int64: [ZoteroAttachment]] = [:]
            while try statement.step() {
                let attachment = statement.zoteroAttachment(dataDirectoryURL: configuration.dataDirectoryURL)
                if let parentID = attachment.parentItemID {
                    rows[parentID, default: []].append(attachment)
                }
            }
            return rows
        }
    }

    private func query<T>(
        _ sql: String,
        bindings: [ZoteroSQLiteBinding] = [],
        _ body: (ZoteroSQLiteStatement) throws -> T
    ) async throws -> T {
        let connection = try ZoteroSQLiteConnection(url: configuration.databaseURL)
        defer { connection.close() }
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        try statement.bind(bindings)
        return try body(statement)
    }

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }
}

private struct ZoteroBaseItemRow {
    var id: Int64
    var key: String
    var itemType: String
    var dateAdded: String?
    var dateModified: String?
}

private final class ZoteroSQLiteConnection {
    private var db: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let db {
                sqlite3_close(db)
            }
            throw ZoteroSQLiteReaderError.openFailed(message)
        }
        sqlite3_busy_timeout(db, 3_000)
        _ = sqlite3_exec(db, "PRAGMA query_only = ON", nil, nil, nil)
    }

    func prepare(_ sql: String) throws -> ZoteroSQLiteStatement {
        var raw: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &raw, nil) == SQLITE_OK, let raw else {
            throw ZoteroSQLiteReaderError.prepareFailed(errorMessage)
        }
        return ZoteroSQLiteStatement(raw: raw, connection: self)
    }

    func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    var errorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
    }
}

private final class ZoteroSQLiteStatement {
    let raw: OpaquePointer
    private unowned let connection: ZoteroSQLiteConnection
    private lazy var columnIndexes = Self.makeColumnIndexes(raw)
    private var finalized = false

    init(raw: OpaquePointer, connection: ZoteroSQLiteConnection) {
        self.raw = raw
        self.connection = connection
    }

    deinit {
        finalize()
    }

    func finalize() {
        guard !finalized else { return }
        sqlite3_finalize(raw)
        finalized = true
    }

    func bind(_ bindings: [ZoteroSQLiteBinding]) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .int64(let value):
                result = sqlite3_bind_int64(raw, index, value)
            case .text(let value):
                result = sqlite3_bind_text(raw, index, value, -1, zoteroSQLiteTransient)
            }
            guard result == SQLITE_OK else {
                throw ZoteroSQLiteReaderError.bindFailed(errorMessage)
            }
        }
    }

    func step() throws -> Bool {
        let result = sqlite3_step(raw)
        if result == SQLITE_ROW {
            return true
        }
        if result == SQLITE_DONE {
            return false
        }
        throw ZoteroSQLiteReaderError.stepFailed(errorMessage)
    }

    func zoteroCollection() -> ZoteroCollection {
        ZoteroCollection(
            id: int64("collectionID"),
            key: optionalString("key"),
            name: string("collectionName"),
            parentCollectionID: optionalInt64("parentCollectionID")
        )
    }

    func zoteroCreator() -> ZoteroCreator {
        let firstName = optionalString("firstName")
        let lastName = optionalString("lastName")
        let displayName: String
        if int("fieldMode") == 1 {
            displayName = lastName ?? firstName ?? ""
        } else {
            displayName = [firstName, lastName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return ZoteroCreator(
            firstName: firstName,
            lastName: lastName,
            displayName: displayName,
            creatorType: string("creatorType")
        )
    }

    func zoteroAttachment(dataDirectoryURL: URL) -> ZoteroAttachment {
        let key = string("key")
        let path = optionalString("path")
        return ZoteroAttachment(
            id: int64("itemID"),
            key: key,
            parentItemID: optionalInt64("parentItemID"),
            contentType: optionalString("contentType"),
            path: path,
            resolvedFileURL: Self.resolveAttachmentURL(
                path: path,
                attachmentKey: key,
                dataDirectoryURL: dataDirectoryURL
            )
        )
    }

    func string(_ column: String) -> String {
        guard let text = sqlite3_column_text(raw, index(column)) else {
            return ""
        }
        return String(cString: text)
    }

    func optionalString(_ column: String) -> String? {
        sqlite3_column_type(raw, index(column)) == SQLITE_NULL ? nil : string(column)
    }

    func int(_ column: String) -> Int {
        Int(sqlite3_column_int(raw, index(column)))
    }

    func int64(_ column: String) -> Int64 {
        sqlite3_column_int64(raw, index(column))
    }

    func optionalInt64(_ column: String) -> Int64? {
        sqlite3_column_type(raw, index(column)) == SQLITE_NULL ? nil : int64(column)
    }

    var errorMessage: String {
        connection.errorMessage
    }

    private func index(_ column: String) -> Int32 {
        columnIndexes[column] ?? 0
    }

    private static func makeColumnIndexes(_ raw: OpaquePointer) -> [String: Int32] {
        var indexes: [String: Int32] = [:]
        for index in 0..<sqlite3_column_count(raw) {
            if let name = sqlite3_column_name(raw, index) {
                indexes[String(cString: name)] = index
            }
        }
        return indexes
    }

    private static func resolveAttachmentURL(
        path: String?,
        attachmentKey: String,
        dataDirectoryURL: URL
    ) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("storage:") {
            let filename = String(path.dropFirst("storage:".count))
            return dataDirectoryURL
                .appendingPathComponent("storage")
                .appendingPathComponent(attachmentKey)
                .appendingPathComponent(filename)
        }
        if path.hasPrefix("/") || path.contains(":\\") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

private enum ZoteroSQLiteBinding {
    case int64(Int64)
    case text(String)
}

private let zoteroSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

#else

public actor ZoteroSQLiteReader {
    public init(configuration: ZoteroLibraryConfiguration) throws {
        throw ZoteroSQLiteReaderError.sqliteUnavailable
    }

    public func schemaStatus() async throws -> ZoteroSchemaStatus {
        throw ZoteroSQLiteReaderError.sqliteUnavailable
    }

    public func collections() async throws -> [ZoteroCollection] {
        throw ZoteroSQLiteReaderError.sqliteUnavailable
    }

    public func items(limit: Int = 250, collectionID: Int64? = nil) async throws -> [ZoteroItem] {
        throw ZoteroSQLiteReaderError.sqliteUnavailable
    }
}

#endif
