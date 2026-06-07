import XCTest
import BilinReaderKit
import BilinWorkspaceKit
@testable import BilinMacApp

@MainActor
final class ReaderWorkbenchSessionDefaultsTests: XCTestCase {
    func testTwoReaderSessionsShareDefaultsButKeepReaderStateIndependent() {
        let defaults = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let first = ReaderWorkbenchSession(workspaceDefaults: defaults, environment: [:])
        let second = ReaderWorkbenchSession(workspaceDefaults: defaults, environment: [:])
        let firstBlock = makeBlock(uid: "first-block")
        let secondBlock = makeBlock(uid: "second-block")
        first.blocks = [firstBlock]
        second.blocks = [secondBlock]
        first.selectedBlockUid = firstBlock.blockUid
        second.selectedBlockUid = secondBlock.blockUid

        defaults.persistWorkspacePath(url: existingTemporaryDirectory(), kind: .obsidianVault)

        XCTAssertEqual(first.workspaceDefaults.workspaceConfiguration.selectedObsidianVault?.path, defaults.workspaceConfiguration.selectedObsidianVault?.path)
        XCTAssertEqual(second.workspaceDefaults.workspaceConfiguration.selectedObsidianVault?.path, defaults.workspaceConfiguration.selectedObsidianVault?.path)
        XCTAssertNotEqual(first.sessionID, second.sessionID)
        XCTAssertEqual(first.selectedBlockUid, "first-block")
        XCTAssertEqual(second.selectedBlockUid, "second-block")
    }

    func testResearchWorkbenchSnapshotReadsCurrentDefaults() {
        let defaults = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let session = ReaderWorkbenchSession(workspaceDefaults: defaults, environment: [:])
        let block = makeBlock(uid: "source-block")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")

        let before = ResearchWorkbenchSnapshot(session: session, workspaceDefaults: defaults)
        XCTAssertFalse(before.noteActionReadiness.isReady)
        XCTAssertNil(before.selectedObsidianVault)

        defaults.persistWorkspacePath(url: existingTemporaryDirectory(), kind: .obsidianVault)
        let after = ResearchWorkbenchSnapshot(session: session, workspaceDefaults: defaults)

        XCTAssertTrue(after.noteActionReadiness.isReady)
        XCTAssertEqual(after.selectedObsidianVault?.path, defaults.workspaceConfiguration.selectedObsidianVault?.path)
    }

    func testCommandReadinessRequiresLibraryBlockWorkspaceAndIdleState() {
        let defaults = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let session = ReaderWorkbenchSession(workspaceDefaults: defaults, environment: [:])
        let block = makeBlock(uid: "source-block")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")

        XCTAssertFalse(session.canPrepareSelectedBlockNoteActionPlan)
        XCTAssertFalse(session.canPrepareSelectedBlockWritingActionPlan)

        session.selectedLibraryId = "library-1"
        XCTAssertFalse(session.canPrepareSelectedBlockNoteActionPlan)
        XCTAssertFalse(session.canPrepareSelectedBlockWritingActionPlan)

        defaults.persistWorkspacePath(url: existingTemporaryDirectory(), kind: .obsidianVault)
        XCTAssertTrue(session.canPrepareSelectedBlockNoteActionPlan)
        XCTAssertFalse(session.canPrepareSelectedBlockWritingActionPlan)

        let emptyWritingProject = temporaryDirectory()
        try? FileManager.default.createDirectory(
            at: emptyWritingProject,
            withIntermediateDirectories: true
        )
        defaults.persistWorkspacePath(url: emptyWritingProject, kind: .writingProjectRoot)
        XCTAssertFalse(session.canPrepareSelectedBlockWritingActionPlan)

        try? "#let title = [Draft]\n".write(
            to: emptyWritingProject.appendingPathComponent("main.typ"),
            atomically: true,
            encoding: .utf8
        )
        defaults.persistWorkspacePath(url: emptyWritingProject, kind: .writingProjectRoot)
        XCTAssertTrue(session.canPrepareSelectedBlockWritingActionPlan)

        session.researchAPIBusy = true
        XCTAssertFalse(session.canPrepareSelectedBlockNoteActionPlan)
        XCTAssertFalse(session.canPrepareSelectedBlockWritingActionPlan)
    }

    func testCommandReadinessRequiresResearchAPIConnection() {
        let defaults = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let session = ReaderWorkbenchSession(workspaceDefaults: defaults, environment: [:])
        let block = makeBlock(uid: "source-block")
        let writingProject = temporaryDirectory()
        try? FileManager.default.createDirectory(
            at: writingProject,
            withIntermediateDirectories: true
        )
        try? "#let title = [Draft]\n".write(
            to: writingProject.appendingPathComponent("main.typ"),
            atomically: true,
            encoding: .utf8
        )
        session.selectedLibraryId = "library-1"
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        defaults.persistWorkspacePath(url: existingTemporaryDirectory(), kind: .obsidianVault)
        defaults.persistWorkspacePath(url: writingProject, kind: .writingProjectRoot)

        XCTAssertFalse(session.canPrepareSelectedBlockNoteActionPlan)
        XCTAssertFalse(session.canPrepareSelectedBlockWritingActionPlan)

        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")
        session.researchAPIError = nil

        XCTAssertTrue(session.canPrepareSelectedBlockNoteActionPlan)
        XCTAssertTrue(session.canPrepareSelectedBlockWritingActionPlan)
    }

    func testCommandReadinessRequiresReadableWorkspaceLocations() {
        let defaults = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let session = ReaderWorkbenchSession(workspaceDefaults: defaults, environment: [:])
        let block = makeBlock(uid: "source-block")
        let writingProject = temporaryDirectory()
        try? FileManager.default.createDirectory(
            at: writingProject,
            withIntermediateDirectories: true
        )
        try? "#let title = [Draft]\n".write(
            to: writingProject.appendingPathComponent("main.typ"),
            atomically: true,
            encoding: .utf8
        )
        session.selectedLibraryId = "library-1"
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")
        defaults.persistWorkspacePath(url: existingTemporaryDirectory(), kind: .obsidianVault)
        defaults.persistWorkspacePath(url: writingProject, kind: .writingProjectRoot)

        XCTAssertTrue(session.canPrepareSelectedBlockNoteActionPlan)
        XCTAssertTrue(session.canPrepareSelectedBlockWritingActionPlan)

        defaults.workspaceConfiguration.selectedObsidianVault?.status = .permissionRequired
        XCTAssertFalse(session.canPrepareSelectedBlockNoteActionPlan)
        XCTAssertTrue(session.canPrepareSelectedBlockWritingActionPlan)

        defaults.workspaceConfiguration.selectedObsidianVault?.status = .available
        defaults.workspaceConfiguration.writingProjectRoots[0].status = .permissionRequired
        XCTAssertTrue(session.canPrepareSelectedBlockNoteActionPlan)
        XCTAssertFalse(session.canPrepareSelectedBlockWritingActionPlan)
    }

    func testSnapshotKeyIncludesSessionIdentity() {
        let defaults = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let first = ReaderWorkbenchSession(workspaceDefaults: defaults, environment: [:])
        let second = ReaderWorkbenchSession(workspaceDefaults: defaults, environment: [:])

        let firstKey = ResearchWorkbenchSnapshotKey(session: first, workspaceDefaults: defaults)
        let secondKey = ResearchWorkbenchSnapshotKey(session: second, workspaceDefaults: defaults)

        XCTAssertNotEqual(firstKey, secondKey)
    }

    private func makeBlock(uid: String) -> DocumentBlock {
        DocumentBlock(
            id: "block-\(uid)",
            articleRevisionId: "revision-1",
            blockUid: uid,
            structuralPath: "00001",
            blockType: .paragraph,
            contentHash: "hash-\(uid)",
            sourceMarkdown: "Paragraph \(uid)",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func isolatedWorkspaceConfigurationCoordinator() -> WorkspaceConfigurationCoordinator {
        let configurationURL = temporaryDirectory()
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
            .appendingPathComponent("bilin-session-defaults-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func existingTemporaryDirectory() -> URL {
        let url = temporaryDirectory()
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}
