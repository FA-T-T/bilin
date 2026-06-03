import Foundation
import BilinReaderKit

public enum SQLiteLibraryStoreError: Error, Equatable, Sendable {
    case missingDatabase(String)
    case sqliteUnavailable
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case invalidDate(String)
    case invalidLibrary(String)
    case unsupportedSchema(missingRequiredVersions: [String], unknownVersions: [String])
}

#if canImport(SQLite3)
import SQLite3

private let requiredLibraryMigrationVersions = [
    "001_initial",
    "002_assets",
    "003_block_search",
    "004_block_embeddings",
    "005_reader_cards",
    "006_reading_progress"
]

public actor SQLiteLibraryStore: LibraryStore {
    private let databaseURL: URL
    private let library: Library

    public init(libraryDirectoryURL: URL, libraryName: String? = nil) throws {
        try self.init(
            databaseURL: libraryDirectoryURL.appendingPathComponent("library.sqlite"),
            libraryName: libraryName
        )
    }

    public init(databaseURL: URL, libraryName: String? = nil) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw SQLiteLibraryStoreError.missingDatabase(databaseURL.path)
        }
        self.databaseURL = databaseURL.standardizedFileURL

        let directoryURL = databaseURL.deletingLastPathComponent()
        let attributes = try? FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let createdAt = attributes?[.creationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        let updatedAt = attributes?[.modificationDate] as? Date ?? createdAt
        self.library = Library(
            id: self.databaseURL.path,
            name: libraryName ?? directoryURL.lastPathComponent,
            path: directoryURL.path,
            status: .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func schemaStatus() async throws -> LibrarySchemaStatus {
        guard try await tableExists("schema_migrations") else {
            throw SQLiteLibraryStoreError.invalidLibrary(databaseURL.path)
        }
        let appliedVersions = try await query("SELECT version FROM schema_migrations ORDER BY version") { statement in
            var versions: [String] = []
            while try statement.step() {
                versions.append(statement.string("version"))
            }
            return versions
        }
        let applied = Set(appliedVersions)
        let required = Set(requiredLibraryMigrationVersions)
        return LibrarySchemaStatus(
            appliedVersions: appliedVersions,
            missingRequiredVersions: requiredLibraryMigrationVersions.filter { !applied.contains($0) },
            unknownVersions: appliedVersions.filter { !required.contains($0) }
        )
    }

    public func listLibraries() async throws -> [Library] {
        try await ensureReadableSchema()
        let hasArticleRevisions = try await query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'article_revisions'") { statement in
            var found = false
            while try statement.step() {
                found = true
            }
            return found
        }
        guard hasArticleRevisions else {
            throw SQLiteLibraryStoreError.invalidLibrary(databaseURL.path)
        }
        return [library]
    }

    public func articles(in libraryId: Library.ID) async throws -> [Article] {
        guard libraryId == library.id else { return [] }
        try await ensureReadableSchema()
        let sql = """
        SELECT
          f.id AS family_id,
          f.source AS source,
          f.external_id AS external_id,
          COALESCE(NULLIF(f.title, ''), f.external_id) AS title,
          r.id AS revision_id
        FROM article_families f
        JOIN article_revisions r ON r.family_id = f.id
        WHERE r.id = (
          SELECT latest.id
          FROM article_revisions latest
          WHERE latest.family_id = f.id
          ORDER BY latest.updated_at DESC, latest.created_at DESC
          LIMIT 1
        )
        ORDER BY r.updated_at DESC, f.title COLLATE NOCASE
        """
        return try await query(sql) { statement in
            var rows: [Article] = []
            while try statement.step() {
                rows.append(
                    Article(
                        id: statement.string("family_id"),
                        libraryId: library.id,
                        source: statement.string("source"),
                        externalId: statement.string("external_id"),
                        title: statement.string("title"),
                        activeRevisionId: statement.string("revision_id")
                    )
                )
            }
            return rows
        }
    }

    public func revision(id: ArticleRevision.ID) async throws -> ArticleRevision? {
        try await ensureReadableSchema()
        let sql = """
        SELECT id, family_id, version, bundle_path, status, created_at, updated_at
        FROM article_revisions
        WHERE id = ?
        LIMIT 1
        """
        return try await query(sql, bindings: [.text(id)]) { statement in
            guard try statement.step() else { return nil }
            return try statement.articleRevision()
        }
    }

    public func blocks(for revisionId: ArticleRevision.ID) async throws -> [DocumentBlock] {
        try await ensureReadableSchema()
        let sql = """
        SELECT
          id,
          article_revision_id,
          block_uid,
          structural_path,
          block_type,
          parent_uid,
          content_hash,
          context_hash,
          source_markdown,
          source_latex,
          metadata_json,
          created_at,
          updated_at
        FROM blocks
        WHERE article_revision_id = ?
        ORDER BY structural_path
        """
        return try await query(sql, bindings: [.text(revisionId)]) { statement in
            var rows: [DocumentBlock] = []
            while try statement.step() {
                rows.append(try statement.documentBlock())
            }
            return rows
        }
    }

    public func translations(for revisionId: ArticleRevision.ID, targetLanguage: String) async throws -> [Translation] {
        try await ensureReadableSchema()
        let sql = """
        SELECT
          tv.id AS id,
          tv.block_id AS block_id,
          tv.target_language AS target_language,
          tv.raw_markdown AS raw_markdown,
          tv.is_default AS is_default,
          tv.metadata_json AS metadata_json,
          b.block_uid AS current_block_uid,
          b.content_hash AS current_content_hash
        FROM translation_variants tv
        JOIN blocks b ON b.id = tv.block_id
        WHERE b.article_revision_id = ?
          AND tv.target_language = ?
        ORDER BY b.structural_path, tv.is_default DESC, tv.updated_at DESC
        """
        return try await query(sql, bindings: [.text(revisionId), .text(targetLanguage)]) { statement in
            var rows: [Translation] = []
            while try statement.step() {
                guard statement.translationMatchesCurrentBlock() else {
                    continue
                }
                rows.append(
                    Translation(
                        id: statement.string("id"),
                        blockId: statement.string("block_id"),
                        targetLanguage: statement.string("target_language"),
                        rawMarkdown: statement.string("raw_markdown"),
                        isDefault: statement.int("is_default") != 0
                    )
                )
            }
            return rows
        }
    }

    public func readingProgress(for revisionId: ArticleRevision.ID) async throws -> ArticleReadingProgress {
        try await ensureReadableSchema()
        let blockUIDs = try await orderedBlockUIDs(for: revisionId)
        let sql = """
        SELECT
          article_revision_id,
          active_block_uid,
          segment_count,
          block_seconds_json,
          total_seconds,
          created_at,
          updated_at
        FROM reading_progress
        WHERE article_revision_id = ?
        LIMIT 1
        """
        return try await query(sql, bindings: [.text(revisionId)]) { statement in
            guard try statement.step() else {
                return ArticleReadingProgress.empty(articleRevisionId: revisionId, blockUIDs: blockUIDs)
            }
            let blockSeconds = SQLiteValueDecoder.intDictionary(from: statement.string("block_seconds_json"))
            return ArticleReadingProgress(
                articleRevisionId: statement.string("article_revision_id"),
                activeBlockUid: statement.optionalString("active_block_uid"),
                segmentCount: statement.int("segment_count"),
                blockSeconds: blockSeconds,
                totalSeconds: statement.int("total_seconds"),
                createdAt: try SQLiteDateParser.date(from: statement.string("created_at")),
                updatedAt: try SQLiteDateParser.date(from: statement.string("updated_at"))
            )
        }
    }

    public func notes(for revisionId: ArticleRevision.ID) async throws -> [ReaderNote] {
        try await ensureReadableSchema()
        let sql = """
        SELECT id, article_revision_id, title, patch_markdown, metadata_json, created_at, updated_at
        FROM note_patches
        WHERE article_revision_id = ?
        ORDER BY updated_at DESC
        """
        return try await query(sql, bindings: [.text(revisionId)]) { statement in
            var rows: [ReaderNote] = []
            while try statement.step() {
                let metadata = SQLiteValueDecoder.stringDictionary(from: statement.string("metadata_json"))
                rows.append(
                    ReaderNote(
                        id: statement.string("id"),
                        articleRevisionId: statement.string("article_revision_id"),
                        blockUid: metadata["block_uid"],
                        title: statement.string("title"),
                        markdown: statement.string("patch_markdown"),
                        createdAt: try SQLiteDateParser.date(from: statement.string("created_at")),
                        updatedAt: try SQLiteDateParser.date(from: statement.string("updated_at"))
                    )
                )
            }
            return rows
        }
    }

    public func saveNote(_ note: ReaderNote) async throws {
        try await ensureWritableSchema()
        let metadata = SQLiteValueEncoder.jsonString(["block_uid": note.blockUid])
        let sourceRefs = SQLiteValueEncoder.jsonArrayString(
            note.blockUid.map { [["block_uid": $0]] } ?? []
        )
        let sql = """
        INSERT INTO note_patches(
          id,
          article_revision_id,
          status,
          title,
          patch_markdown,
          source_refs_json,
          metadata_json,
          created_at,
          updated_at
        )
        VALUES (?, ?, 'draft', ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          patch_markdown = excluded.patch_markdown,
          source_refs_json = excluded.source_refs_json,
          metadata_json = excluded.metadata_json,
          updated_at = excluded.updated_at
        """
        try await execute(
            sql,
            bindings: [
                .text(note.id),
                .text(note.articleRevisionId),
                .text(note.title),
                .text(note.markdown),
                .text(sourceRefs),
                .text(metadata),
                .text(SQLiteDateParser.string(from: note.createdAt)),
                .text(SQLiteDateParser.string(from: note.updatedAt))
            ],
            flags: SQLITE_OPEN_READWRITE
        )
    }

    private func ensureReadableSchema() async throws {
        let status = try await schemaStatus()
        guard status.isReadable else {
            throw SQLiteLibraryStoreError.unsupportedSchema(
                missingRequiredVersions: status.missingRequiredVersions,
                unknownVersions: status.unknownVersions
            )
        }
    }

    private func ensureWritableSchema() async throws {
        let status = try await schemaStatus()
        guard status.isWritable else {
            throw SQLiteLibraryStoreError.unsupportedSchema(
                missingRequiredVersions: status.missingRequiredVersions,
                unknownVersions: status.unknownVersions
            )
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

    private func orderedBlockUIDs(for revisionId: ArticleRevision.ID) async throws -> [String] {
        try await query(
            "SELECT block_uid FROM blocks WHERE article_revision_id = ? ORDER BY structural_path",
            bindings: [.text(revisionId)]
        ) { statement in
            var blockUIDs: [String] = []
            while try statement.step() {
                blockUIDs.append(statement.string("block_uid"))
            }
            return blockUIDs
        }
    }

    private func query<T>(
        _ sql: String,
        bindings: [SQLiteBinding] = [],
        flags: Int32 = SQLITE_OPEN_READONLY,
        _ body: (SQLiteStatement) throws -> T
    ) async throws -> T {
        let connection = try SQLiteConnection(url: databaseURL, flags: flags)
        defer { connection.close() }
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        try statement.bind(bindings)
        return try body(statement)
    }

    private func execute(
        _ sql: String,
        bindings: [SQLiteBinding],
        flags: Int32
    ) async throws {
        try await query(sql, bindings: bindings, flags: flags) { statement in
            guard sqlite3_step(statement.raw) == SQLITE_DONE else {
                throw SQLiteLibraryStoreError.stepFailed(statement.errorMessage)
            }
        }
    }
}

private final class SQLiteConnection {
    private var db: OpaquePointer?

    init(url: URL, flags: Int32) throws {
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            if let db {
                sqlite3_close(db)
            }
            throw SQLiteLibraryStoreError.openFailed(message)
        }
        sqlite3_busy_timeout(db, 3_000)
        _ = sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var raw: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &raw, nil) == SQLITE_OK, let raw else {
            throw SQLiteLibraryStoreError.prepareFailed(errorMessage)
        }
        return SQLiteStatement(raw: raw, connection: self)
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

private final class SQLiteStatement {
    let raw: OpaquePointer
    private unowned let connection: SQLiteConnection
    private lazy var columnIndexes = Self.makeColumnIndexes(raw)
    private var finalized = false

    init(raw: OpaquePointer, connection: SQLiteConnection) {
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

    func bind(_ bindings: [SQLiteBinding]) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(raw, index, value, -1, sqliteTransient)
            case .null:
                result = sqlite3_bind_null(raw, index)
            }
            guard result == SQLITE_OK else {
                throw SQLiteLibraryStoreError.bindFailed(errorMessage)
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
        throw SQLiteLibraryStoreError.stepFailed(errorMessage)
    }

    func articleRevision() throws -> ArticleRevision {
        ArticleRevision(
            id: string("id"),
            articleId: string("family_id"),
            version: string("version"),
            bundlePath: string("bundle_path"),
            status: string("status"),
            createdAt: try SQLiteDateParser.date(from: string("created_at")),
            updatedAt: try SQLiteDateParser.date(from: string("updated_at"))
        )
    }

    func documentBlock() throws -> DocumentBlock {
        DocumentBlock(
            id: string("id"),
            articleRevisionId: string("article_revision_id"),
            blockUid: string("block_uid"),
            structuralPath: string("structural_path"),
            blockType: DocumentBlockKind(rawValue: string("block_type")) ?? .unknown,
            parentUid: optionalString("parent_uid"),
            contentHash: string("content_hash"),
            contextHash: optionalString("context_hash"),
            sourceMarkdown: string("source_markdown"),
            sourceLatex: optionalString("source_latex"),
            metadata: SQLiteValueDecoder.stringDictionary(from: string("metadata_json")),
            createdAt: try SQLiteDateParser.date(from: string("created_at")),
            updatedAt: try SQLiteDateParser.date(from: string("updated_at"))
        )
    }

    func translationMatchesCurrentBlock() -> Bool {
        let metadata = SQLiteValueDecoder.stringDictionary(from: string("metadata_json"))
        guard let cachedHash = metadata["content_hash"] else {
            return true
        }
        return cachedHash == string("current_content_hash")
            || metadata["block_uid"] == string("current_block_uid")
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
}

private enum SQLiteBinding {
    case text(String)
    case null
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private enum SQLiteDateParser {
    static func date(from value: String) throws -> Date {
        let normalized = normalizedFractionalSeconds(value)
        if let date = fractionalFormatter().date(from: normalized) ?? plainFormatter().date(from: normalized) {
            return date
        }
        throw SQLiteLibraryStoreError.invalidDate(value)
    }

    static func string(from date: Date) -> String {
        fractionalFormatter().string(from: date)
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func plainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func normalizedFractionalSeconds(_ value: String) -> String {
        guard let dot = value.firstIndex(of: ".") else { return value }
        let fractionStart = value.index(after: dot)
        guard let timezoneStart = value[fractionStart...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) else {
            return value
        }
        let fraction = value[fractionStart..<timezoneStart]
        guard fraction.count > 3 else { return value }
        return "\(value[..<fractionStart])\(fraction.prefix(3))\(value[timezoneStart...])"
    }
}

private enum SQLiteValueDecoder {
    static func stringDictionary(from json: String) -> [String: String] {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in object {
            switch value {
            case let string as String:
                result[key] = string
            case let number as NSNumber:
                result[key] = number.stringValue
            default:
                continue
            }
        }
        return result
    }

    static func intDictionary(from json: String) -> [String: Int] {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        var result: [String: Int] = [:]
        for (key, value) in object {
            switch value {
            case let int as Int:
                result[key] = int
            case let number as NSNumber:
                result[key] = number.intValue
            case let string as String:
                result[key] = Int(string)
            default:
                continue
            }
        }
        return result
    }
}

private enum SQLiteValueEncoder {
    static func jsonString(_ dictionary: [String: String?]) -> String {
        let object = dictionary.compactMapValues { $0 }
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    static func jsonArrayString(_ array: [[String: String]]) -> String {
        guard
            JSONSerialization.isValidJSONObject(array),
            let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return string
    }
}

#else

public actor SQLiteLibraryStore: LibraryStore {
    public init(libraryDirectoryURL: URL, libraryName: String? = nil) throws {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public init(databaseURL: URL, libraryName: String? = nil) throws {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public func schemaStatus() async throws -> LibrarySchemaStatus {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public func listLibraries() async throws -> [Library] {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public func articles(in libraryId: Library.ID) async throws -> [Article] {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public func revision(id: ArticleRevision.ID) async throws -> ArticleRevision? {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public func blocks(for revisionId: ArticleRevision.ID) async throws -> [DocumentBlock] {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public func translations(for revisionId: ArticleRevision.ID, targetLanguage: String) async throws -> [Translation] {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public func readingProgress(for revisionId: ArticleRevision.ID) async throws -> ArticleReadingProgress {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public func notes(for revisionId: ArticleRevision.ID) async throws -> [ReaderNote] {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }

    public func saveNote(_ note: ReaderNote) async throws {
        throw SQLiteLibraryStoreError.sqliteUnavailable
    }
}

#endif
