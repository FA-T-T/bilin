import XCTest
import BilinWorkspaceKit
@testable import BilinMacApp

@MainActor
final class WorkspaceDefaultsModelTests: XCTestCase {
    func testInitDetectsUniqueAvailableZoteroAndObsidianLocationsWithoutPersisting() throws {
        let homeURL = temporaryDirectory()
        let vaultURL = homeURL.appendingPathComponent("Documents/Research Vault", isDirectory: true)
        let zoteroURL = homeURL.appendingPathComponent("Zotero", isDirectory: true)
        try FileManager.default.createDirectory(
            at: vaultURL.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: zoteroURL, withIntermediateDirectories: true)
        try Data().write(to: zoteroURL.appendingPathComponent("zotero.sqlite"))

        let model = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator(homeDirectoryURL: homeURL)
        )

        XCTAssertNil(model.workspaceConfiguration.selectedObsidianVault)
        XCTAssertNil(model.workspaceConfiguration.selectedZoteroLibrary)
        XCTAssertEqual(
            model.uniqueAvailableDetectedWorkspacePath(kind: .obsidianVault)?.path,
            vaultURL.path
        )
        XCTAssertEqual(
            model.uniqueAvailableDetectedWorkspacePath(kind: .zoteroLibrary)?.path,
            zoteroURL.path
        )
        XCTAssertNil(model.workspaceConfigurationError)
    }

    func testInitDoesNotAutoUseAmbiguousDetectedObsidianLocations() throws {
        let homeURL = temporaryDirectory()
        let firstVaultURL = homeURL.appendingPathComponent("Documents/First Vault", isDirectory: true)
        let secondVaultURL = homeURL.appendingPathComponent("Documents/Second Vault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: firstVaultURL.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondVaultURL.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )

        let model = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator(homeDirectoryURL: homeURL)
        )

        XCTAssertNil(model.workspaceConfiguration.selectedObsidianVault)
        XCTAssertEqual(model.detectedWorkspacePaths.filter { $0.kind == .obsidianVault }.count, 2)
    }

    func testDetectWorkspacePathsDoesNotAutoPersistUniqueDetectedApplicationLocations() throws {
        let homeURL = temporaryDirectory()
        let vaultURL = homeURL.appendingPathComponent("Documents/Research Vault", isDirectory: true)
        let zoteroURL = homeURL.appendingPathComponent("Zotero", isDirectory: true)
        try FileManager.default.createDirectory(
            at: vaultURL.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: zoteroURL, withIntermediateDirectories: true)
        try Data().write(to: zoteroURL.appendingPathComponent("zotero.sqlite"))
        let model = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator(homeDirectoryURL: homeURL)
        )

        model.detectWorkspacePaths()

        XCTAssertNil(model.workspaceConfiguration.selectedObsidianVault)
        XCTAssertNil(model.workspaceConfiguration.selectedZoteroLibrary)
        XCTAssertEqual(
            model.uniqueAvailableDetectedWorkspacePath(kind: .obsidianVault)?.path,
            vaultURL.path
        )
        XCTAssertEqual(
            model.uniqueAvailableDetectedWorkspacePath(kind: .zoteroLibrary)?.path,
            zoteroURL.path
        )
    }

    func testUseDetectedWorkspacePathPersistsDefaultLocation() {
        let rootURL = temporaryDirectory()
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let model = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let record = WorkspacePathRecord(
            id: "detected-obsidian",
            name: "Research Vault",
            path: rootURL.path,
            kind: .obsidianVault,
            status: .available,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        model.useDetectedWorkspacePath(record)

        XCTAssertEqual(model.workspaceConfiguration.selectedObsidianVault?.path, rootURL.path)
        XCTAssertNil(model.workspaceConfigurationError)
    }

    func testMissingDetectedWorkspacePathReportsConfigurationError() {
        let model = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let record = WorkspacePathRecord(
            id: "missing-writing",
            name: "Missing Writing Project",
            path: "/tmp/bilin-missing-writing-\(UUID().uuidString)",
            kind: .writingProjectRoot,
            status: .missing,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        model.useDetectedWorkspacePath(record)

        XCTAssertTrue(model.workspaceConfiguration.writingProjectRoots.isEmpty)
        XCTAssertEqual(model.workspaceConfigurationError, "\(record.path) is not available.")
    }

    func testForgetWorkspacePathClearsConfigurationWithoutDeletingDetectedLocation() {
        let rootURL = temporaryDirectory()
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let model = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let record = WorkspacePathRecord(
            id: "writing-project",
            name: "Draft Project",
            path: rootURL.path,
            kind: .writingProjectRoot,
            status: .available,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        model.useDetectedWorkspacePath(record)

        model.forgetWorkspacePath(record)

        XCTAssertTrue(model.workspaceConfiguration.writingProjectRoots.isEmpty)
        XCTAssertEqual(model.writingProjectLocation.rootPath, "Choose a writing project")
        XCTAssertEqual(model.writingProjectLocation.status, .missing)
        XCTAssertNil(model.workspaceConfigurationError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.path))
    }

    func testDetectWorkspacePathsRefreshesConfiguredWritingProjectStatus() throws {
        let rootURL = temporaryDirectory()
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "#show: doc => doc\n".write(
            to: rootURL.appendingPathComponent("main.typ"),
            atomically: true,
            encoding: .utf8
        )
        let model = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        model.persistWorkspacePath(url: rootURL, kind: .writingProjectRoot)
        XCTAssertEqual(model.workspaceConfiguration.writingProjectRoots.first?.status, .available)
        XCTAssertEqual(model.writingProjectLocation.status, .linked)

        try FileManager.default.removeItem(at: rootURL)
        model.detectWorkspacePaths()

        XCTAssertEqual(model.workspaceConfiguration.writingProjectRoots.first?.status, .missing)
        XCTAssertEqual(model.writingProjectLocation.status, .missing)
        XCTAssertNil(model.workspaceConfigurationError)
    }

    func testUniqueAvailableDetectedWorkspacePathRequiresExactlyOneAvailableMatch() {
        let model = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let detectedVault = WorkspacePathRecord(
            id: "detected-obsidian",
            name: "Research Vault",
            path: "/tmp/research-vault",
            kind: .obsidianVault,
            status: .available,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        model.detectedWorkspacePaths = [
            detectedVault,
            WorkspacePathRecord(
                id: "missing-zotero",
                name: "Missing Zotero",
                path: "/tmp/missing-zotero",
                kind: .zoteroLibrary,
                status: .missing,
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0)
            )
        ]

        XCTAssertEqual(
            model.uniqueAvailableDetectedWorkspacePath(kind: .obsidianVault)?.id,
            detectedVault.id
        )
        XCTAssertNil(model.uniqueAvailableDetectedWorkspacePath(kind: .zoteroLibrary))

        model.detectedWorkspacePaths.append(
            WorkspacePathRecord(
                id: "second-obsidian",
                name: "Second Vault",
                path: "/tmp/second-vault",
                kind: .obsidianVault,
                status: .available,
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0)
            )
        )

        XCTAssertNil(model.uniqueAvailableDetectedWorkspacePath(kind: .obsidianVault))
    }

    private func isolatedWorkspaceConfigurationCoordinator(
        homeDirectoryURL: URL? = nil
    ) -> WorkspaceConfigurationCoordinator {
        let configurationURL = temporaryDirectory()
            .appendingPathComponent("workspace-configuration.json")
        let store = WorkspaceConfigurationStore(configurationFileURL: configurationURL)
        let detector = WorkspacePathDetector(homeDirectoryURL: homeDirectoryURL ?? temporaryDirectory())
        return WorkspaceConfigurationCoordinator(
            configurationStore: store,
            pathDetector: detector,
            bookmarkDataProvider: { _ in nil }
        )
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("bilin-workspace-defaults-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
