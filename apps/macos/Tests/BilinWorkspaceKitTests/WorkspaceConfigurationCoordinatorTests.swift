import XCTest
@testable import BilinWorkspaceKit

final class WorkspaceConfigurationCoordinatorTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let updatedDate = Date(timeIntervalSince1970: 1_800_000_600)

    func testPersistPathNormalizesBilinAndZoteroDatabaseFiles() throws {
        let rootURL = try makeTemporaryDirectory()
        let libraryURL = rootURL.appendingPathComponent("Bilin", isDirectory: true)
        let zoteroURL = rootURL.appendingPathComponent("Zotero", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zoteroURL, withIntermediateDirectories: true)
        let libraryDatabaseURL = libraryURL.appendingPathComponent("library.sqlite")
        let zoteroDatabaseURL = zoteroURL.appendingPathComponent("zotero.sqlite")
        try Data().write(to: libraryDatabaseURL)
        try Data().write(to: zoteroDatabaseURL)
        let coordinator = try makeCoordinator(bookmarkData: Data("bookmark".utf8))

        _ = try coordinator.persistPath(url: libraryDatabaseURL, kind: .bilinLibrary, now: baseDate)
        let configuration = try coordinator.persistPath(url: zoteroDatabaseURL, kind: .zoteroLibrary, now: baseDate)

        XCTAssertEqual(configuration.selectedBilinLibrary?.id, "selected-bilin-library")
        XCTAssertEqual(configuration.selectedBilinLibrary?.path, libraryURL.path)
        XCTAssertEqual(configuration.selectedBilinLibrary?.status, .available)
        XCTAssertEqual(configuration.selectedBilinLibrary?.securityScopedBookmarkData, Data("bookmark".utf8))
        XCTAssertEqual(configuration.selectedZoteroLibrary?.id, "selected-zotero-library")
        XCTAssertEqual(configuration.selectedZoteroLibrary?.path, zoteroURL.path)
        XCTAssertEqual(configuration.selectedZoteroLibrary?.status, .available)
    }

    func testPersistDetectedPathRecordPreservesDetectedIdentityAndRefreshesStatus() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Research Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let coordinator = try makeCoordinator(bookmarkData: Data("vault".utf8))
        let detected = WorkspacePathRecord(
            id: "detected-obsidian-research-notes",
            name: "Research Notes",
            path: vaultURL.path,
            kind: .obsidianVault,
            status: .missing,
            createdAt: baseDate,
            updatedAt: baseDate
        )

        let configuration = try coordinator.persistDetectedPathRecord(detected, now: updatedDate)

        XCTAssertEqual(configuration.selectedObsidianVault?.id, detected.id)
        XCTAssertEqual(configuration.selectedObsidianVault?.path, vaultURL.path)
        XCTAssertEqual(configuration.selectedObsidianVault?.status, .available)
        XCTAssertEqual(configuration.selectedObsidianVault?.createdAt, baseDate)
        XCTAssertEqual(configuration.selectedObsidianVault?.updatedAt, updatedDate)
        XCTAssertEqual(configuration.selectedObsidianVault?.securityScopedBookmarkData, Data("vault".utf8))
    }

    func testPersistPathMarksUnreadableLocationAsPermissionRequired() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Research Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: vaultURL.path
            )
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: vaultURL.path
        )
        let coordinator = try makeCoordinator(bookmarkData: Data("vault".utf8))

        let configuration = try coordinator.persistPath(url: vaultURL, kind: .obsidianVault, now: baseDate)

        XCTAssertEqual(configuration.selectedObsidianVault?.status, .permissionRequired)
    }

    func testPersistPathRequiresBilinLibraryDatabase() throws {
        let rootURL = try makeTemporaryDirectory()
        let libraryURL = rootURL.appendingPathComponent("Bilin", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let coordinator = try makeCoordinator(bookmarkData: nil)

        let configuration = try coordinator.persistPath(url: libraryURL, kind: .bilinLibrary, now: baseDate)

        XCTAssertEqual(configuration.selectedBilinLibrary?.path, libraryURL.path)
        XCTAssertEqual(configuration.selectedBilinLibrary?.status, .missing)
    }

    func testPersistPathRequiresZoteroDatabase() throws {
        let rootURL = try makeTemporaryDirectory()
        let zoteroURL = rootURL.appendingPathComponent("Zotero", isDirectory: true)
        try FileManager.default.createDirectory(at: zoteroURL, withIntermediateDirectories: true)
        let coordinator = try makeCoordinator(bookmarkData: nil)

        let configuration = try coordinator.persistPath(url: zoteroURL, kind: .zoteroLibrary, now: baseDate)

        XCTAssertEqual(configuration.selectedZoteroLibrary?.path, zoteroURL.path)
        XCTAssertEqual(configuration.selectedZoteroLibrary?.status, .missing)
    }

    func testRefreshConfiguredPathStatusesRevalidatesExistingRecords() throws {
        let rootURL = try makeTemporaryDirectory()
        let zoteroURL = rootURL.appendingPathComponent("Zotero", isDirectory: true)
        try FileManager.default.createDirectory(at: zoteroURL, withIntermediateDirectories: true)
        let coordinator = try makeCoordinator(bookmarkData: Data("bookmark".utf8))
        let missing = try coordinator.persistPath(url: zoteroURL, kind: .zoteroLibrary, now: baseDate)
        XCTAssertEqual(missing.selectedZoteroLibrary?.status, .missing)

        try Data().write(to: zoteroURL.appendingPathComponent("zotero.sqlite"))
        let refreshed = try coordinator.refreshConfiguredPathStatuses(now: updatedDate)

        XCTAssertEqual(refreshed.selectedZoteroLibrary?.path, zoteroURL.path)
        XCTAssertEqual(refreshed.selectedZoteroLibrary?.status, .available)
        XCTAssertEqual(refreshed.selectedZoteroLibrary?.createdAt, baseDate)
        XCTAssertEqual(refreshed.selectedZoteroLibrary?.updatedAt, updatedDate)
        XCTAssertEqual(refreshed.selectedZoteroLibrary?.securityScopedBookmarkData, Data("bookmark".utf8))
    }

    func testRefreshConfiguredPathStatusesDoesNotRewriteUnchangedRecords() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Research Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        let coordinator = try makeCoordinator(bookmarkData: nil)
        let current = try coordinator.persistPath(url: vaultURL, kind: .obsidianVault, now: baseDate)

        let refreshed = try coordinator.refreshConfiguredPathStatuses(now: updatedDate)

        XCTAssertEqual(refreshed.selectedObsidianVault, current.selectedObsidianVault)
        XCTAssertEqual(refreshed.selectedObsidianVault?.updatedAt, baseDate)
    }

    func testDetectPathRecordsDelegatesToWorkspacePathDetector() throws {
        let homeURL = try makeTemporaryDirectory()
        let vaultURL = homeURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("ResearchVault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: vaultURL.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        let coordinator = try makeCoordinator(
            detector: WorkspacePathDetector(homeDirectoryURL: homeURL),
            bookmarkData: nil
        )

        let records = coordinator.detectPathRecords(now: baseDate)

        XCTAssertTrue(records.contains { record in
            record.kind == .obsidianVault && record.path == vaultURL.path
        })
    }

    private func makeCoordinator(
        detector: WorkspacePathDetector = WorkspacePathDetector(),
        bookmarkData: Data?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> WorkspaceConfigurationCoordinator {
        let store = try makeStore(file: file, line: line)
        return WorkspaceConfigurationCoordinator(
            configurationStore: store,
            pathDetector: detector,
            bookmarkDataProvider: { _ in bookmarkData }
        )
    }

    private func makeStore(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> WorkspaceConfigurationStore {
        let rootURL = try makeTemporaryDirectory(file: file, line: line)
        return WorkspaceConfigurationStore(
            configurationFileURL: rootURL.appendingPathComponent("workspace-configuration.json")
        )
    }

    private func makeTemporaryDirectory(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BilinWorkspaceCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return rootURL
    }
}
