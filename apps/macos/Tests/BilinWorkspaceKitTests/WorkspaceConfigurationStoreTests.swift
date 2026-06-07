import XCTest
@testable import BilinWorkspaceKit

final class WorkspaceConfigurationStoreTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testRoundTripPersistsAllWorkspacePathRecords() throws {
        let store = try makeStore()
        let configuration = WorkspaceConfiguration(
            selectedBilinLibrary: makeRecord(
                id: "bilin-library",
                name: "Bilin Library",
                path: "/Users/example/Bilin",
                kind: .bilinLibrary
            ),
            selectedZoteroLibrary: makeRecord(
                id: "zotero-library",
                name: "Zotero",
                path: "/Users/example/Zotero/zotero.sqlite",
                kind: .zoteroLibrary,
                status: .permissionRequired
            ),
            selectedObsidianVault: makeRecord(
                id: "obsidian-vault",
                name: "Research Notes",
                path: "/Users/example/Notes",
                kind: .obsidianVault
            ),
            writingProjectRoots: [
                makeRecord(
                    id: "writing-typst",
                    name: "DAC Typst Draft",
                    path: "/Users/example/DACDraft",
                    kind: .writingProjectRoot
                ),
                makeRecord(
                    id: "writing-tex",
                    name: "Journal TeX Draft",
                    path: "/Users/example/JournalDraft",
                    kind: .writingProjectRoot,
                    status: .missing
                )
            ]
        )

        try store.save(configuration)

        let loaded = try store.load()
        XCTAssertEqual(loaded, configuration)
    }

    func testMissingConfigurationFileLoadsEmptyConfiguration() throws {
        let store = try makeStore()

        let loaded = try store.load()

        XCTAssertEqual(loaded, WorkspaceConfiguration())
    }

    func testSaveCreatesParentDirectoryWhenMissing() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BilinWorkspaceKitTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let store = WorkspaceConfigurationStore(
            configurationFileURL: rootURL
                .appendingPathComponent("nested", isDirectory: true)
                .appendingPathComponent("workspace-configuration.json")
        )
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "obsidian-vault",
                name: "Research Notes",
                path: "/Users/example/Notes",
                kind: .obsidianVault
            )
        )

        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testCorruptConfigurationReturnsStructuredErrorAndLeavesBytesUntouched() throws {
        let store = try makeStore()
        let corruptData = Data("{\"selectedBilinLibrary\":".utf8)
        try corruptData.write(to: store.configurationFileURL)

        XCTAssertThrowsError(try store.load()) { error in
            guard case WorkspaceConfigurationStoreError.corruptConfiguration(let url, _) = error else {
                return XCTFail("Expected corruptConfiguration, got \(error)")
            }
            XCTAssertEqual(url, store.configurationFileURL)
        }
        XCTAssertEqual(try Data(contentsOf: store.configurationFileURL), corruptData)

        XCTAssertThrowsError(
            try store.updatePathRecord(
                makeRecord(
                    id: "bilin-library",
                    name: "Bilin Library",
                    path: "/Users/example/Bilin",
                    kind: .bilinLibrary
                )
            )
        )
        XCTAssertEqual(try Data(contentsOf: store.configurationFileURL), corruptData)
    }

    func testUpdatingOnePathTypePreservesOtherPathRecords() throws {
        let store = try makeStore()
        let originalBilin = makeRecord(
            id: "bilin-library",
            name: "Bilin Library",
            path: "/Users/example/Bilin",
            kind: .bilinLibrary
        )
        let originalZotero = makeRecord(
            id: "zotero-library",
            name: "Zotero",
            path: "/Users/example/Zotero/zotero.sqlite",
            kind: .zoteroLibrary
        )
        let originalVault = makeRecord(
            id: "obsidian-vault",
            name: "Research Notes",
            path: "/Users/example/Notes",
            kind: .obsidianVault
        )
        let originalWritingProject = makeRecord(
            id: "writing-typst",
            name: "DAC Typst Draft",
            path: "/Users/example/DACDraft",
            kind: .writingProjectRoot
        )
        try store.save(
            WorkspaceConfiguration(
                selectedBilinLibrary: originalBilin,
                selectedZoteroLibrary: originalZotero,
                selectedObsidianVault: originalVault,
                writingProjectRoots: [originalWritingProject]
            )
        )

        let updatedZotero = makeRecord(
            id: "zotero-library",
            name: "Main Zotero",
            path: "/Users/example/Zotero/storage.sqlite",
            kind: .zoteroLibrary,
            status: .available
        )
        let updated = try store.updatePathRecord(updatedZotero)

        XCTAssertEqual(updated.selectedBilinLibrary, originalBilin)
        XCTAssertEqual(updated.selectedZoteroLibrary, updatedZotero)
        XCTAssertEqual(updated.selectedObsidianVault, originalVault)
        XCTAssertEqual(updated.writingProjectRoots, [originalWritingProject])
        XCTAssertEqual(try store.load(), updated)
    }

    func testUpdatingWritingProjectRootPreservesSiblingRoots() throws {
        let store = try makeStore()
        let typstRoot = makeRecord(
            id: "writing-typst",
            name: "DAC Typst Draft",
            path: "/Users/example/DACDraft",
            kind: .writingProjectRoot
        )
        let texRoot = makeRecord(
            id: "writing-tex",
            name: "Journal TeX Draft",
            path: "/Users/example/JournalDraft",
            kind: .writingProjectRoot
        )
        try store.save(WorkspaceConfiguration(writingProjectRoots: [typstRoot, texRoot]))

        let updatedTypstRoot = makeRecord(
            id: "writing-typst",
            name: "DAC Camera Ready",
            path: "/Users/example/DACCameraReady",
            kind: .writingProjectRoot,
            status: .permissionRequired
        )
        let updated = try store.updatePathRecord(updatedTypstRoot)

        XCTAssertEqual(updated.writingProjectRoots, [updatedTypstRoot, texRoot])
    }

    func testRemovingOnePathRecordPreservesOtherConfiguredLocations() throws {
        let store = try makeStore()
        let library = makeRecord(
            id: "bilin-library",
            name: "Bilin Library",
            path: "/Users/example/Bilin",
            kind: .bilinLibrary
        )
        let vault = makeRecord(
            id: "obsidian-vault",
            name: "Research Notes",
            path: "/Users/example/Notes",
            kind: .obsidianVault
        )
        let typstRoot = makeRecord(
            id: "writing-typst",
            name: "DAC Typst Draft",
            path: "/Users/example/DACDraft",
            kind: .writingProjectRoot
        )
        let texRoot = makeRecord(
            id: "writing-tex",
            name: "Journal TeX Draft",
            path: "/Users/example/JournalDraft",
            kind: .writingProjectRoot
        )
        try store.save(
            WorkspaceConfiguration(
                selectedBilinLibrary: library,
                selectedObsidianVault: vault,
                writingProjectRoots: [typstRoot, texRoot]
            )
        )

        let withoutVault = try store.removePathRecord(kind: .obsidianVault)
        let withoutTypst = try store.removePathRecord(kind: .writingProjectRoot, id: typstRoot.id)

        XCTAssertEqual(withoutVault.selectedBilinLibrary, library)
        XCTAssertNil(withoutVault.selectedObsidianVault)
        XCTAssertEqual(withoutVault.writingProjectRoots, [typstRoot, texRoot])
        XCTAssertEqual(withoutTypst.selectedBilinLibrary, library)
        XCTAssertNil(withoutTypst.selectedObsidianVault)
        XCTAssertEqual(withoutTypst.writingProjectRoots, [texRoot])
        XCTAssertEqual(try store.load(), withoutTypst)
    }

    func testSecurityScopedBookmarkDataIsOpaqueAndRoundTrips() throws {
        let store = try makeStore()
        let bookmarkData = Data([0x00, 0xff, 0x7f, 0x42, 0x10, 0x80])
        let vault = makeRecord(
            id: "obsidian-vault",
            name: "Research Notes",
            path: "/Users/example/Notes",
            kind: .obsidianVault,
            securityScopedBookmarkData: bookmarkData
        )

        try store.save(WorkspaceConfiguration(selectedObsidianVault: vault))

        let loaded = try store.load()
        XCTAssertEqual(loaded.selectedObsidianVault?.securityScopedBookmarkData, bookmarkData)
        XCTAssertEqual(loaded.selectedObsidianVault, vault)
    }

    private func makeStore(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> WorkspaceConfigurationStore {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BilinWorkspaceKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return WorkspaceConfigurationStore(
            configurationFileURL: rootURL.appendingPathComponent("workspace-configuration.json")
        )
    }

    private func makeRecord(
        id: String,
        name: String,
        path: String,
        kind: WorkspacePathKind,
        status: ExternalFileTargetStatus = .available,
        securityScopedBookmarkData: Data? = nil
    ) -> WorkspacePathRecord {
        WorkspacePathRecord(
            id: id,
            name: name,
            path: path,
            kind: kind,
            status: status,
            securityScopedBookmarkData: securityScopedBookmarkData,
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }
}
