import XCTest
import BilinReaderKit
@testable import BilinStore

#if canImport(SQLite3)
import SQLite3

final class SQLiteLibraryStoreTests: XCTestCase {
    func testReadsLibraryArticleBlocksTranslationsAndNotes() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let databaseURL = directoryURL.appendingPathComponent("library.sqlite")
        try createDatabase(at: databaseURL)

        let store = try SQLiteLibraryStore(libraryDirectoryURL: directoryURL, libraryName: "Fixture Library")
        let libraries = try await store.listLibraries()
        XCTAssertEqual(libraries.first?.name, "Fixture Library")

        let articles = try await store.articles(in: try XCTUnwrap(libraries.first?.id))
        XCTAssertEqual(articles.map(\.title), ["A Native Reader"])
        XCTAssertEqual(articles.first?.activeRevisionId, "revision-1")

        let revision = try await store.revision(id: "revision-1")
        XCTAssertEqual(revision?.articleId, "family-1")

        let blocks = try await store.blocks(for: "revision-1")
        XCTAssertEqual(blocks.map(\.blockUid), ["title-1", "p-1", "eq-1"])
        XCTAssertEqual(blocks.last?.blockType, .equation)
        XCTAssertEqual(blocks.last?.sourceLatex, "E = mc^2")

        let translations = try await store.translations(for: "revision-1", targetLanguage: "zh-CN")
        XCTAssertEqual(translations.count, 1)
        XCTAssertEqual(translations.first?.rawMarkdown, "Translated paragraph.")

        let note = ReaderNote(
            id: "note-1",
            articleRevisionId: "revision-1",
            blockUid: "p-1",
            title: "Claim",
            markdown: "Native store works.",
            createdAt: Date(timeIntervalSince1970: 1_706_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_706_000_000)
        )
        try await store.saveNote(note)

        let notes = try await store.notes(for: "revision-1")
        XCTAssertEqual(notes.first?.blockUid, "p-1")
        XCTAssertEqual(notes.first?.markdown, "Native store works.")
    }

    private func createDatabase(at url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer {
            sqlite3_close(db)
        }

        let sql = """
        CREATE TABLE article_families (
          id TEXT PRIMARY KEY,
          source TEXT NOT NULL,
          external_id TEXT NOT NULL,
          title TEXT,
          metadata_json TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE article_revisions (
          id TEXT PRIMARY KEY,
          family_id TEXT NOT NULL,
          version TEXT NOT NULL,
          bundle_path TEXT NOT NULL,
          status TEXT NOT NULL,
          manifest_version INTEGER NOT NULL DEFAULT 1,
          metadata_json TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE blocks (
          id TEXT PRIMARY KEY,
          article_revision_id TEXT NOT NULL,
          block_uid TEXT NOT NULL,
          structural_path TEXT NOT NULL,
          block_type TEXT NOT NULL,
          parent_uid TEXT,
          content_hash TEXT NOT NULL,
          context_hash TEXT,
          source_markdown TEXT NOT NULL,
          source_latex TEXT,
          metadata_json TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE translation_variants (
          id TEXT PRIMARY KEY,
          block_id TEXT NOT NULL,
          target_language TEXT NOT NULL,
          provider_profile_id TEXT,
          model TEXT,
          raw_markdown TEXT NOT NULL,
          render_ast_json TEXT,
          validation_status TEXT NOT NULL DEFAULT 'unchecked',
          glossary_version TEXT,
          is_default INTEGER NOT NULL DEFAULT 0,
          metadata_json TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE note_patches (
          id TEXT PRIMARY KEY,
          article_revision_id TEXT NOT NULL,
          status TEXT NOT NULL,
          title TEXT NOT NULL,
          patch_markdown TEXT NOT NULL,
          source_refs_json TEXT NOT NULL DEFAULT '[]',
          metadata_json TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        INSERT INTO article_families(
          id, source, external_id, title, metadata_json, created_at, updated_at
        ) VALUES (
          'family-1', 'fixture', 'native-reader', 'A Native Reader', '{}',
          '2026-06-03T08:00:00.123456+00:00',
          '2026-06-03T08:00:00.123456+00:00'
        );

        INSERT INTO article_revisions(
          id, family_id, version, bundle_path, status, manifest_version, metadata_json, created_at, updated_at
        ) VALUES (
          'revision-1', 'family-1', 'v1', '/tmp/native-reader', 'ready', 1, '{}',
          '2026-06-03T08:00:00.123456+00:00',
          '2026-06-03T08:00:01.123456+00:00'
        );

        INSERT INTO blocks(
          id, article_revision_id, block_uid, structural_path, block_type, parent_uid,
          content_hash, context_hash, source_markdown, source_latex, metadata_json, created_at, updated_at
        ) VALUES
          ('block-title', 'revision-1', 'title-1', '00001', 'title', NULL, 'h1', NULL,
           'A Native Reader', NULL, '{}', '2026-06-03T08:00:00.123456+00:00', '2026-06-03T08:00:00.123456+00:00'),
          ('block-p', 'revision-1', 'p-1', '00002', 'paragraph', NULL, 'h2', NULL,
           'This is a native reader.', NULL, '{"level": 1}', '2026-06-03T08:00:00.123456+00:00', '2026-06-03T08:00:00.123456+00:00'),
          ('block-eq', 'revision-1', 'eq-1', '00003', 'equation', NULL, 'h3', NULL,
           '$$E = mc^2$$', 'E = mc^2', '{}', '2026-06-03T08:00:00.123456+00:00', '2026-06-03T08:00:00.123456+00:00');

        INSERT INTO translation_variants(
          id, block_id, target_language, raw_markdown, validation_status, is_default,
          metadata_json, created_at, updated_at
        ) VALUES (
          'translation-1', 'block-p', 'zh-CN', 'Translated paragraph.', 'ok', 1, '{}',
          '2026-06-03T08:00:00.123456+00:00',
          '2026-06-03T08:00:00.123456+00:00'
        ), (
          'translation-stale', 'block-p', 'zh-CN', 'Stale paragraph.', 'ok', 0, '{"content_hash": "old-hash"}',
          '2026-06-03T08:00:00.123456+00:00',
          '2026-06-03T08:00:01.123456+00:00'
        );
        """

        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }
}
#endif
