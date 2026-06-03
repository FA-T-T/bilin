import XCTest
@testable import BilinImportKit

#if canImport(SQLite3)
import SQLite3

final class ZoteroSQLiteReaderTests: XCTestCase {
    func testReadsZoteroMetadataWithoutWriting() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let databaseURL = directoryURL.appendingPathComponent("zotero.sqlite")
        try createZoteroDatabase(at: databaseURL)

        let reader = try ZoteroSQLiteReader(configuration: ZoteroLibraryConfiguration(dataDirectoryURL: directoryURL))
        let schemaStatus = try await reader.schemaStatus()
        XCTAssertTrue(schemaStatus.isReadable)

        let collections = try await reader.collections()
        XCTAssertEqual(collections.first?.name, "Quantum")

        let items = try await reader.items(limit: 10)
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.title, "Expressibility of PQCs")
        XCTAssertEqual(item.creators.first?.displayName, "Jane Doe")
        XCTAssertEqual(item.tags, ["Quantum Physics"])
        XCTAssertEqual(item.collections.map(\.name), ["Quantum"])
        XCTAssertEqual(item.arxiv?.concreteIdentifier, "1905.10876")
        XCTAssertEqual(item.attachments.first?.resolvedFileURL?.lastPathComponent, "paper.pdf")
    }

    private func createZoteroDatabase(at url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer {
            sqlite3_close(db)
        }

        let sql = """
        CREATE TABLE items (
          itemID INTEGER PRIMARY KEY,
          itemTypeID INTEGER NOT NULL,
          dateAdded TEXT,
          dateModified TEXT,
          key TEXT NOT NULL
        );

        CREATE TABLE itemTypes (
          itemTypeID INTEGER PRIMARY KEY,
          typeName TEXT NOT NULL
        );

        CREATE TABLE fields (
          fieldID INTEGER PRIMARY KEY,
          fieldName TEXT NOT NULL
        );

        CREATE TABLE itemData (
          itemID INTEGER NOT NULL,
          fieldID INTEGER NOT NULL,
          valueID INTEGER NOT NULL
        );

        CREATE TABLE itemDataValues (
          valueID INTEGER PRIMARY KEY,
          value TEXT NOT NULL
        );

        CREATE TABLE collections (
          collectionID INTEGER PRIMARY KEY,
          collectionName TEXT NOT NULL,
          parentCollectionID INTEGER,
          key TEXT
        );

        CREATE TABLE collectionItems (
          collectionID INTEGER NOT NULL,
          itemID INTEGER NOT NULL
        );

        CREATE TABLE tags (
          tagID INTEGER PRIMARY KEY,
          name TEXT NOT NULL
        );

        CREATE TABLE itemTags (
          itemID INTEGER NOT NULL,
          tagID INTEGER NOT NULL
        );

        CREATE TABLE creators (
          creatorID INTEGER PRIMARY KEY,
          firstName TEXT,
          lastName TEXT,
          fieldMode INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE itemCreators (
          itemID INTEGER NOT NULL,
          creatorID INTEGER NOT NULL,
          creatorTypeID INTEGER NOT NULL,
          orderIndex INTEGER NOT NULL
        );

        CREATE TABLE creatorTypes (
          creatorTypeID INTEGER PRIMARY KEY,
          creatorType TEXT NOT NULL
        );

        CREATE TABLE itemAttachments (
          itemID INTEGER PRIMARY KEY,
          parentItemID INTEGER,
          contentType TEXT,
          path TEXT
        );

        CREATE TABLE deletedItems (
          itemID INTEGER PRIMARY KEY
        );

        INSERT INTO itemTypes(itemTypeID, typeName) VALUES
          (1, 'journalArticle'),
          (2, 'attachment');

        INSERT INTO items(itemID, itemTypeID, dateAdded, dateModified, key) VALUES
          (1, 1, '2026-06-03 08:00:00', '2026-06-03 08:10:00', 'ABCD1234'),
          (2, 2, '2026-06-03 08:00:00', '2026-06-03 08:10:00', 'PDF12345');

        INSERT INTO fields(fieldID, fieldName) VALUES
          (1, 'title'),
          (2, 'extra'),
          (3, 'url'),
          (4, 'abstractNote'),
          (5, 'libraryCatalog');

        INSERT INTO itemData(itemID, fieldID, valueID) VALUES
          (1, 1, 1),
          (1, 2, 2),
          (1, 3, 3),
          (1, 4, 4),
          (1, 5, 5);

        INSERT INTO itemDataValues(valueID, value) VALUES
          (1, 'Expressibility of PQCs'),
          (2, 'arXiv:1905.10876 [quant-ph]'),
          (3, 'https://arxiv.org/abs/1905.10876'),
          (4, 'Parameterized quantum circuits are studied.'),
          (5, 'arXiv.org');

        INSERT INTO collections(collectionID, collectionName, parentCollectionID, key) VALUES
          (1, 'Quantum', NULL, 'COLL1234');

        INSERT INTO collectionItems(collectionID, itemID) VALUES
          (1, 1);

        INSERT INTO tags(tagID, name) VALUES
          (1, 'Quantum Physics');

        INSERT INTO itemTags(itemID, tagID) VALUES
          (1, 1);

        INSERT INTO creators(creatorID, firstName, lastName, fieldMode) VALUES
          (1, 'Jane', 'Doe', 0);

        INSERT INTO creatorTypes(creatorTypeID, creatorType) VALUES
          (1, 'author');

        INSERT INTO itemCreators(itemID, creatorID, creatorTypeID, orderIndex) VALUES
          (1, 1, 1, 0);

        INSERT INTO itemAttachments(itemID, parentItemID, contentType, path) VALUES
          (2, 1, 'application/pdf', 'storage:paper.pdf');
        """

        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }
}
#endif
