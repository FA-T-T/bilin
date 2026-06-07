import XCTest
import BilinWorkspaceKit
@testable import BilinMacApp

#if canImport(SQLite3)
import SQLite3
#endif

@MainActor
final class ReaderWorkbenchSessionLaunchTests: XCTestCase {
    override func tearDown() {
        LaunchResearchAPIMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testInitialWorkbenchStaysEmptyWhenNoLibraryIsConfigured() async throws {
        let session = makeSession(environment: [:], researchAPIClient: makeHealthClient())

        await session.loadInitialWorkbench()
        try await Task.sleep(nanoseconds: 160_000_000)

        XCTAssertEqual(session.initialLaunchPolicy(), .openConfiguredLibrary)
        XCTAssertTrue(session.libraries.isEmpty)
        XCTAssertTrue(session.articles.isEmpty)
        XCTAssertNil(session.selectedLibraryId)
        XCTAssertNil(session.selectedLibraryItem)
        XCTAssertNil(session.loadError)
        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertEqual(session.researchAPIHealth?.app, "Ilios")
        XCTAssertEqual(session.researchWorkbenchStatus, "No library")
    }

    func testInitialWorkbenchReportsConfiguredBilinLibraryRecoveryWhenDatabaseIsMissing() async throws {
        let missingLibraryURL = temporaryDirectory()
        let defaults = makeWorkspaceDefaults()
        defaults.persistWorkspacePath(url: missingLibraryURL, kind: .bilinLibrary)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeHealthClient(),
            workspaceDefaults: defaults,
            environment: [:]
        )

        await session.loadInitialWorkbench()

        XCTAssertTrue(session.libraries.isEmpty)
        XCTAssertNil(session.selectedLibraryId)
        XCTAssertEqual(session.configuredBilinLibraryRecovery?.path, missingLibraryURL.path)
        XCTAssertTrue(session.configuredBilinLibraryRecovery?.message.contains("could not be found") ?? false)
        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertEqual(session.researchWorkbenchStatus, "Library needs attention")
        XCTAssertEqual(session.researchWorkbenchError, session.configuredBilinLibraryRecovery?.message)
    }

    func testOpeningMissingLibraryPreservesConnectedResearchAPIState() async throws {
        let session = makeSession(environment: [:])
        session.researchAPIStatus = "API connected"
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios", version: "0.3.6")
        session.researchAPIError = nil
        let missingLibraryURL = temporaryDirectory()

        await session.openLibrary(at: missingLibraryURL)

        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertEqual(session.researchAPIHealth?.app, "Ilios")
        XCTAssertNil(session.researchAPIError)
        XCTAssertTrue(session.libraries.isEmpty)
        XCTAssertNil(session.selectedLibraryId)
        XCTAssertNotNil(session.loadError)
    }

    func testPrototypeFixtureRequiresExplicitDevelopmentFlag() async {
        let session = makeSession(environment: ["BILIN_MAC_LOAD_PROTOTYPE_FIXTURE": "1"])

        await session.loadInitialWorkbench()

        XCTAssertEqual(session.initialLaunchPolicy(), .loadPrototypeFixture)
        XCTAssertFalse(session.libraries.isEmpty)
        XCTAssertNotNil(session.selectedLibraryId)
        XCTAssertFalse(session.blocks.isEmpty)
    }

    #if canImport(SQLite3)
    func testInitialWorkbenchOpensConfiguredZoteroLibrary() async throws {
        let zoteroDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: zoteroDirectory, withIntermediateDirectories: true)
        try createMinimalZoteroDatabase(at: zoteroDirectory.appendingPathComponent("zotero.sqlite"))

        let defaults = makeWorkspaceDefaults()
        defaults.persistWorkspacePath(url: zoteroDirectory, kind: .zoteroLibrary)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeHealthClient(),
            workspaceDefaults: defaults,
            environment: [:]
        )

        await session.loadInitialWorkbench()

        XCTAssertEqual(session.workspaceDefaults.workspaceConfiguration.selectedZoteroLibrary?.path, zoteroDirectory.path)
        XCTAssertEqual(session.zoteroItems.count, 1)
        XCTAssertEqual(session.zoteroItems.first?.title, "Auto Loaded Zotero Paper")
        XCTAssertEqual(session.selectedLibraryItem?.zoteroItemId, session.zoteroItems.first?.id)
        XCTAssertEqual(session.researchAPIStatus, "API connected")
    }

    func testUseDetectedZoteroLibraryPersistsAndOpensMetadata() async throws {
        let zoteroDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: zoteroDirectory, withIntermediateDirectories: true)
        try createMinimalZoteroDatabase(at: zoteroDirectory.appendingPathComponent("zotero.sqlite"))
        let session = makeSession(environment: [:])
        let record = WorkspacePathRecord(
            id: "detected-zotero",
            name: "Zotero",
            path: zoteroDirectory.path,
            kind: .zoteroLibrary,
            status: .available,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        await session.useDetectedWorkspacePath(record)

        XCTAssertEqual(session.workspaceDefaults.workspaceConfiguration.selectedZoteroLibrary?.path, zoteroDirectory.path)
        XCTAssertEqual(session.zoteroItems.count, 1)
        XCTAssertEqual(session.zoteroItems.first?.title, "Auto Loaded Zotero Paper")
        XCTAssertEqual(session.selectedLibraryItem?.zoteroItemId, session.zoteroItems.first?.id)
        XCTAssertNil(session.loadError)
    }

    func testOpeningZoteroDoesNotCancelInFlightArticleSelection() async throws {
        let zoteroDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: zoteroDirectory, withIntermediateDirectories: true)
        try createMinimalZoteroDatabase(at: zoteroDirectory.appendingPathComponent("zotero.sqlite"))
        let session = makeSession(environment: [:])
        session.selectedLibraryItem = .article(id: "article-loading")
        session.selectedLibraryItemLoadState = .loading(.article(id: "article-loading"))
        let articleLoadTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
        }
        session.libraryItemSelectionTask = articleLoadTask
        let generation = session.selectionLoadGeneration

        await session.openZoteroLibrary(at: zoteroDirectory)

        XCTAssertEqual(session.selectedLibraryItem, .article(id: "article-loading"))
        XCTAssertEqual(session.selectedLibraryItemLoadState, .loading(.article(id: "article-loading")))
        XCTAssertEqual(session.selectionLoadGeneration, generation)
        XCTAssertFalse(articleLoadTask.isCancelled)
        articleLoadTask.cancel()
    }

    func testSelectingPaperAfterZoteroMetadataReloadsReaderBlocks() async throws {
        let zoteroDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: zoteroDirectory, withIntermediateDirectories: true)
        try createMinimalZoteroDatabase(at: zoteroDirectory.appendingPathComponent("zotero.sqlite"))
        let session = makeSession(environment: [:])

        await session.loadPrototypeFixture()
        let article = try XCTUnwrap(session.articles.first)
        XCTAssertEqual(session.selectedLibraryItem?.articleId, article.id)
        XCTAssertFalse(session.blocks.isEmpty)

        await session.openZoteroLibrary(at: zoteroDirectory)
        let zoteroItem = try XCTUnwrap(session.zoteroItems.first)
        session.requestLibraryItemSelection(.zoteroItem(id: zoteroItem.id))
        await waitUntil {
            session.selectedZoteroItem?.id == zoteroItem.id
        }
        XCTAssertTrue(session.blocks.isEmpty)

        session.requestLibraryItemSelection(.article(id: article.id))
        await waitUntil {
            session.selectedArticle?.id == article.id && !session.blocks.isEmpty
        }

        XCTAssertEqual(session.selectedLibraryItem, .article(id: article.id))
        XCTAssertNil(session.selectedZoteroItem)
        XCTAssertFalse(session.blocks.isEmpty)
        XCTAssertEqual(session.selectedLibraryItemLoadState, .loaded(.article(id: article.id)))
    }
    #endif

    private func makeSession(
        environment: [String: String],
        researchAPIClient: BilinResearchAPIClient? = nil
    ) -> ReaderWorkbenchSession {
        ReaderWorkbenchSession(
            researchAPIClient: researchAPIClient,
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator(),
            environment: environment
        )
    }

    private func makeHealthClient() -> BilinResearchAPIClient {
        LaunchResearchAPIMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/health")
            let response = HTTPURLResponse(
                url: URL(string: "http://127.0.0.1:8000/health")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data("""
                {
                  "status": "ok",
                  "app": "Ilios",
                  "version": "0.3.6"
                }
                """.utf8)
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LaunchResearchAPIMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return BilinResearchAPIClient(
            baseURL: URL(string: "http://127.0.0.1:8000")!,
            session: session
        )
    }

    private func makeWorkspaceDefaults() -> WorkspaceDefaultsModel {
        WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
    }

    private func isolatedWorkspaceConfigurationCoordinator() -> WorkspaceConfigurationCoordinator {
        let configurationURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("bilin-workbench-launch-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace-configuration.json")
        let store = WorkspaceConfigurationStore(configurationFileURL: configurationURL)
        return WorkspaceConfigurationCoordinator(
            configurationStore: store,
            pathDetector: WorkspacePathDetector(homeDirectoryURL: temporaryDirectory()),
            bookmarkDataProvider: { _ in nil }
        )
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("bilin-workbench-launch-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    #if canImport(SQLite3)
    private func createMinimalZoteroDatabase(at url: URL) throws {
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

        INSERT INTO itemTypes(itemTypeID, typeName) VALUES (1, 'journalArticle');
        INSERT INTO items(itemID, itemTypeID, dateAdded, dateModified, key)
          VALUES (1, 1, '2026-06-06 08:00:00', '2026-06-06 08:10:00', 'AUTO1234');
        INSERT INTO fields(fieldID, fieldName) VALUES (1, 'title');
        INSERT INTO itemData(itemID, fieldID, valueID) VALUES (1, 1, 1);
        INSERT INTO itemDataValues(valueID, value) VALUES (1, 'Auto Loaded Zotero Paper');
        """

        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }
    #endif
}

private final class LaunchResearchAPIMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
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
