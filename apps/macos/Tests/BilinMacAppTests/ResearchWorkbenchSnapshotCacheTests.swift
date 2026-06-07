import XCTest
import BilinImportKit
import BilinReaderKit
import BilinWorkspaceKit
@testable import BilinMacApp

@MainActor
final class ResearchWorkbenchSnapshotCacheTests: XCTestCase {
    func testReusesSnapshotWhenModelKeyDoesNotChange() {
        let session = ReaderWorkbenchSession()
        let cache = ResearchWorkbenchSnapshotCache()
        let key = ResearchWorkbenchSnapshotKey(session: session)
        var buildCount = 0

        _ = cache.snapshot(for: key) {
            buildCount += 1
            return ResearchWorkbenchSnapshot(session: session)
        }
        _ = cache.snapshot(for: key) {
            buildCount += 1
            return ResearchWorkbenchSnapshot(session: session)
        }

        XCTAssertEqual(buildCount, 1)
    }

    func testInvalidatesSnapshotWhenVisibleModelStateChanges() {
        let session = ReaderWorkbenchSession()
        let cache = ResearchWorkbenchSnapshotCache()
        var buildCount = 0

        _ = cache.snapshot(for: ResearchWorkbenchSnapshotKey(session: session)) {
            buildCount += 1
            return ResearchWorkbenchSnapshot(session: session)
        }

        session.researchAPIStatus = "Connected"
        _ = cache.snapshot(for: ResearchWorkbenchSnapshotKey(session: session)) {
            buildCount += 1
            return ResearchWorkbenchSnapshot(session: session)
        }

        XCTAssertEqual(buildCount, 2)
    }

    func testInvalidatesSnapshotWhenWorkbenchStatusChanges() {
        let session = ReaderWorkbenchSession()
        let cache = ResearchWorkbenchSnapshotCache()
        var buildCount = 0

        _ = cache.snapshot(for: ResearchWorkbenchSnapshotKey(session: session)) {
            buildCount += 1
            return ResearchWorkbenchSnapshot(session: session)
        }

        session.researchWorkbenchStatus = "Workbench unavailable"
        session.researchWorkbenchError = "Library is not registered."
        _ = cache.snapshot(for: ResearchWorkbenchSnapshotKey(session: session)) {
            buildCount += 1
            return ResearchWorkbenchSnapshot(session: session)
        }

        XCTAssertEqual(buildCount, 2)
    }

    func testSelectedBlockChangesSnapshotKey() {
        let session = ReaderWorkbenchSession()
        let firstBlock = makeBlock(uid: "p-1", structuralPath: "00001")
        let secondBlock = makeBlock(uid: "p-2", structuralPath: "00002")
        session.blocks = [firstBlock, secondBlock]
        session.selectedBlockUid = firstBlock.blockUid
        let firstKey = ResearchWorkbenchSnapshotKey(session: session)

        session.selectedBlockUid = secondBlock.blockUid
        let secondKey = ResearchWorkbenchSnapshotKey(session: session)

        XCTAssertNotEqual(firstKey, secondKey)
    }

    func testNoteReadinessRequiresSelectedBlockAndObsidianVault() {
        let block = makeBlock(uid: "p-1", structuralPath: "00001")

        let noBlock = ResearchWorkbenchSnapshot.noteActionReadiness(
            selectedBlock: nil,
            selectedObsidianVault: makePathRecord(kind: .obsidianVault),
            isAPIAvailable: true,
            isBusy: false
        )
        let noVault = ResearchWorkbenchSnapshot.noteActionReadiness(
            selectedBlock: block,
            selectedObsidianVault: nil,
            isAPIAvailable: true,
            isBusy: false
        )
        let ready = ResearchWorkbenchSnapshot.noteActionReadiness(
            selectedBlock: block,
            selectedObsidianVault: makePathRecord(kind: .obsidianVault),
            isAPIAvailable: true,
            isBusy: false
        )

        XCTAssertFalse(noBlock.isReady)
        XCTAssertEqual(noBlock.title, "Select a source block")
        XCTAssertFalse(noVault.isReady)
        XCTAssertEqual(noVault.title, "Choose an Obsidian vault")
        XCTAssertTrue(ready.isReady)
    }

    func testNoteReadinessRequiresResearchAPIAfterLocalConfigurationIsSatisfied() {
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let unavailable = ResearchWorkbenchSnapshot.noteActionReadiness(
            selectedBlock: block,
            selectedObsidianVault: makePathRecord(kind: .obsidianVault),
            isAPIAvailable: false,
            isBusy: false
        )

        XCTAssertFalse(unavailable.isReady)
        XCTAssertEqual(unavailable.title, "Check Research API")
    }

    func testNoteReadinessRequiresReadableObsidianVault() {
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let unavailable = ResearchWorkbenchSnapshot.noteActionReadiness(
            selectedBlock: block,
            selectedObsidianVault: makePathRecord(kind: .obsidianVault, status: .permissionRequired),
            isAPIAvailable: true,
            isBusy: false
        )

        XCTAssertFalse(unavailable.isReady)
        XCTAssertEqual(unavailable.title, "Reauthorize Obsidian vault")
    }

    func testWritingReadinessRequiresProjectAndMainFile() {
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let projectRoot = makePathRecord(kind: .writingProjectRoot)
        let noRoot = ResearchWorkbenchSnapshot.writingActionReadiness(
            selectedBlock: block,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            selectedWritingProjectRoot: nil,
            isAPIAvailable: true,
            isBusy: false
        )
        let noMainFile = ResearchWorkbenchSnapshot.writingActionReadiness(
            selectedBlock: block,
            writingProject: makeWritingProject(mainFilePath: nil),
            selectedWritingProjectRoot: projectRoot,
            isAPIAvailable: true,
            isBusy: false
        )
        let ready = ResearchWorkbenchSnapshot.writingActionReadiness(
            selectedBlock: block,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            selectedWritingProjectRoot: projectRoot,
            isAPIAvailable: true,
            isBusy: false
        )

        XCTAssertFalse(noRoot.isReady)
        XCTAssertEqual(noRoot.title, "Choose a writing project")
        XCTAssertFalse(noMainFile.isReady)
        XCTAssertEqual(noMainFile.title, "Select a project with a main file")
        XCTAssertTrue(ready.isReady)
    }

    func testWritingReadinessRequiresResearchAPIAfterLocalConfigurationIsSatisfied() {
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let unavailable = ResearchWorkbenchSnapshot.writingActionReadiness(
            selectedBlock: block,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            selectedWritingProjectRoot: makePathRecord(kind: .writingProjectRoot),
            isAPIAvailable: false,
            isBusy: false
        )

        XCTAssertFalse(unavailable.isReady)
        XCTAssertEqual(unavailable.title, "Check Research API")
    }

    func testWritingReadinessRequiresReadableWritingProject() {
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let unavailable = ResearchWorkbenchSnapshot.writingActionReadiness(
            selectedBlock: block,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            selectedWritingProjectRoot: makePathRecord(kind: .writingProjectRoot, status: .permissionRequired),
            isAPIAvailable: true,
            isBusy: false
        )

        XCTAssertFalse(unavailable.isReady)
        XCTAssertEqual(unavailable.title, "Reauthorize writing project")
    }

    func testResearchPlanReadinessRequiresSelectedPaperAndAPI() {
        let article = makeArticle()
        let enabledSkill = makePaperOutlineSkill()
        let noPaper = ResearchWorkbenchSnapshot.researchPlanActionReadiness(
            selectedArticle: nil,
            researchSkills: [enabledSkill],
            isAPIAvailable: true,
            isBusy: false
        )
        let noAPI = ResearchWorkbenchSnapshot.researchPlanActionReadiness(
            selectedArticle: article,
            researchSkills: [enabledSkill],
            isAPIAvailable: false,
            isBusy: false
        )
        let busy = ResearchWorkbenchSnapshot.researchPlanActionReadiness(
            selectedArticle: article,
            researchSkills: [enabledSkill],
            isAPIAvailable: true,
            isBusy: true
        )
        let ready = ResearchWorkbenchSnapshot.researchPlanActionReadiness(
            selectedArticle: article,
            researchSkills: [enabledSkill],
            isAPIAvailable: true,
            isBusy: false
        )

        XCTAssertFalse(noPaper.isReady)
        XCTAssertEqual(noPaper.title, "Select a paper")
        XCTAssertFalse(noAPI.isReady)
        XCTAssertEqual(noAPI.title, "Check Research API")
        XCTAssertFalse(busy.isReady)
        XCTAssertEqual(busy.title, "Research action in progress")
        XCTAssertTrue(ready.isReady)
    }

    func testResearchPlanReadinessRequiresEnabledPaperOutlineSkill() {
        let article = makeArticle()
        let missing = ResearchWorkbenchSnapshot.researchPlanActionReadiness(
            selectedArticle: article,
            researchSkills: [],
            isAPIAvailable: true,
            isBusy: false
        )
        let disabled = ResearchWorkbenchSnapshot.researchPlanActionReadiness(
            selectedArticle: article,
            researchSkills: [makePaperOutlineSkill(status: .disabled)],
            isAPIAvailable: true,
            isBusy: false
        )
        let taskMismatch = ResearchWorkbenchSnapshot.researchPlanActionReadiness(
            selectedArticle: article,
            researchSkills: [makePaperOutlineSkill(supportedTasks: [.writing])],
            isAPIAvailable: true,
            isBusy: false
        )

        XCTAssertFalse(missing.isReady)
        XCTAssertEqual(missing.title, "Index paper-outline skill")
        XCTAssertFalse(disabled.isReady)
        XCTAssertEqual(disabled.title, "Enable paper-outline skill")
        XCTAssertFalse(taskMismatch.isReady)
        XCTAssertEqual(taskMismatch.title, "Paper outline skill mismatch")
    }

    func testReadinessReportsBusyStateAfterConfigurationIsSatisfied() {
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let note = ResearchWorkbenchSnapshot.noteActionReadiness(
            selectedBlock: block,
            selectedObsidianVault: makePathRecord(kind: .obsidianVault),
            isAPIAvailable: true,
            isBusy: true
        )
        let writing = ResearchWorkbenchSnapshot.writingActionReadiness(
            selectedBlock: block,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            selectedWritingProjectRoot: makePathRecord(kind: .writingProjectRoot),
            isAPIAvailable: true,
            isBusy: true
        )

        XCTAssertFalse(note.isReady)
        XCTAssertEqual(note.title, "Research action in progress")
        XCTAssertFalse(writing.isReady)
        XCTAssertEqual(writing.title, "Research action in progress")
    }

    func testSnapshotNoteBridgePreviewDoesNotSynchronouslyReadTargetBaseHash() throws {
        let rootURL = temporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Vault", isDirectory: true)
        let targetURL = vaultURL.appendingPathComponent("Papers/No paper selected.md")
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let existingNote = "# No paper selected\n\nExisting Obsidian note.\n"
        try existingNote.write(to: targetURL, atomically: true, encoding: .utf8)
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let vault = makePathRecord(kind: .obsidianVault, path: vaultURL.path)
        let writingRoot = makePathRecord(kind: .writingProjectRoot, path: rootURL.path)
        let defaults = makeWorkspaceDefaults(
            selectedObsidianVault: vault,
            writingProjectRoot: writingRoot,
            mainFilePath: rootURL.appendingPathComponent("main.typ").path
        )
        let session = ReaderWorkbenchSession()
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid

        let snapshot = ResearchWorkbenchSnapshot(
            session: session,
            workspaceDefaults: defaults
        )

        let bridge = try XCTUnwrap(snapshot.noteBridge)
        let patch = try XCTUnwrap(bridge.pendingPatch)
        XCTAssertEqual(bridge.targetNotePath, "Papers/No paper selected.md")
        XCTAssertEqual(patch.targetPath, targetURL.path)
        XCTAssertNil(patch.baseFileHash)
        XCTAssertTrue(patch.patchText.contains("Paragraph p-1"))
    }

    func testSnapshotNoteBridgeShowsSelectedExcerptScope() throws {
        let rootURL = temporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let selectedExcerpt = "Selected claim $x_i$ [@smith2024]."
        let selectedHash = ReaderSelectionSnapshot.sha256TextHash(for: selectedExcerpt)
        let defaults = makeWorkspaceDefaults(
            selectedObsidianVault: makePathRecord(kind: .obsidianVault, path: vaultURL.path),
            writingProjectRoot: makePathRecord(kind: .writingProjectRoot, path: rootURL.path),
            mainFilePath: rootURL.appendingPathComponent("main.typ").path
        )
        let session = ReaderWorkbenchSession()
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.readerTextSelection = ReaderTextSelection(
            blockUid: block.blockUid,
            text: selectedExcerpt,
            textHash: selectedHash
        )

        let snapshot = ResearchWorkbenchSnapshot(
            session: session,
            workspaceDefaults: defaults
        )

        let bridge = try XCTUnwrap(snapshot.noteBridge)
        let patch = try XCTUnwrap(bridge.pendingPatch)
        XCTAssertEqual(bridge.sourcePayload.markdown, selectedExcerpt)
        XCTAssertEqual(bridge.sourcePayload.contentHash, selectedHash)
        XCTAssertEqual(bridge.provenance.selectedTextHash, selectedHash)
        XCTAssertEqual(WorkbenchSourceScope.resolve(bridge), .selectedExcerpt(hash: selectedHash))
        XCTAssertEqual(WorkbenchSourceScope.resolve(bridge).displayName, "Selected excerpt")
        XCTAssertEqual(WorkbenchSourceScope.resolve(bridge).previewTitle, "Selected excerpt payload")
        XCTAssertTrue(patch.patchText.contains("> Selected claim $x_i$ [@smith2024]."))
        XCTAssertFalse(patch.patchText.contains("> Paragraph p-1"))
    }

    func testSnapshotNoteBridgeUsesPendingSelectedExcerptBeforeDebounceCommits() throws {
        let rootURL = temporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let selectedExcerpt = "Freshly selected claim for Note Bridge."
        let selectedHash = ReaderSelectionSnapshot.sha256TextHash(for: selectedExcerpt)
        let defaults = makeWorkspaceDefaults(
            selectedObsidianVault: makePathRecord(kind: .obsidianVault, path: vaultURL.path),
            writingProjectRoot: makePathRecord(kind: .writingProjectRoot, path: rootURL.path),
            mainFilePath: rootURL.appendingPathComponent("main.typ").path
        )
        let session = ReaderWorkbenchSession()
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.updateReaderTextSelection(blockUid: block.blockUid, selectedText: selectedExcerpt)
        XCTAssertNil(session.readerTextSelection)

        let snapshot = ResearchWorkbenchSnapshot(
            session: session,
            workspaceDefaults: defaults
        )

        let bridge = try XCTUnwrap(snapshot.noteBridge)
        XCTAssertEqual(bridge.sourcePayload.markdown, selectedExcerpt)
        XCTAssertEqual(bridge.sourcePayload.contentHash, selectedHash)
        XCTAssertEqual(bridge.provenance.selectedTextHash, selectedHash)
        XCTAssertEqual(WorkbenchSourceScope.resolve(bridge), .selectedExcerpt(hash: selectedHash))
    }

    func testSnapshotWritingDockShowsSelectedExcerptScope() throws {
        let rootURL = temporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Vault", isDirectory: true)
        let writingRootURL = rootURL.appendingPathComponent("Writing", isDirectory: true)
        let mainFileURL = writingRootURL.appendingPathComponent("main.typ")
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: writingRootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let selectedExcerpt = "Selected related-work claim with $x_i$."
        let selectedHash = ReaderSelectionSnapshot.sha256TextHash(for: selectedExcerpt)
        let defaults = makeWorkspaceDefaults(
            selectedObsidianVault: makePathRecord(kind: .obsidianVault, path: vaultURL.path),
            writingProjectRoot: makePathRecord(kind: .writingProjectRoot, path: writingRootURL.path),
            mainFilePath: mainFileURL.path
        )
        let session = ReaderWorkbenchSession()
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.readerTextSelection = ReaderTextSelection(
            blockUid: block.blockUid,
            text: selectedExcerpt,
            textHash: selectedHash
        )

        let snapshot = ResearchWorkbenchSnapshot(
            session: session,
            workspaceDefaults: defaults
        )

        let patch = try XCTUnwrap(snapshot.writingProject.pendingPatches.first)
        XCTAssertEqual(patch.provenance.first?.selectedTextHash, selectedHash)
        XCTAssertEqual(WorkbenchSourceScope.resolve(patch), .selectedExcerpt(hash: selectedHash))
        XCTAssertEqual(WorkbenchSourceScope.resolve(patch)?.displayName, "Selected excerpt")
        XCTAssertEqual(WorkbenchSourceScope.resolve(patch)?.selectionHash, selectedHash)
        XCTAssertTrue(patch.patchText.contains(selectedExcerpt))
        XCTAssertFalse(patch.patchText.contains("Paragraph p-1"))
    }

    func testSnapshotWritingDockTargetsFirstRealSectionWhenRelatedWorkIsAbsent() throws {
        let rootURL = temporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Vault", isDirectory: true)
        let writingRootURL = rootURL.appendingPathComponent("Writing", isDirectory: true)
        let mainFileURL = writingRootURL.appendingPathComponent("main.typ")
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: writingRootURL, withIntermediateDirectories: true)
        try """
        = Introduction
        Context.

        = Method
        Approach.

        = Discussion
        Implications.
        """.write(to: mainFileURL, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let defaults = makeWorkspaceDefaults(
            selectedObsidianVault: makePathRecord(kind: .obsidianVault, path: vaultURL.path),
            writingProjectRoot: makePathRecord(kind: .writingProjectRoot, path: writingRootURL.path),
            mainFilePath: mainFileURL.path
        )
        defaults.writingProjectLocation = WritingProjectLocator().locate(rootPath: writingRootURL.path)
        let session = ReaderWorkbenchSession()
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid

        let snapshot = ResearchWorkbenchSnapshot(
            session: session,
            workspaceDefaults: defaults
        )

        let patch = try XCTUnwrap(snapshot.writingProject.pendingPatches.first)
        XCTAssertEqual(snapshot.writingTargetSection, "Introduction")
        XCTAssertEqual(patch.targetSectionPath, ["Introduction"])
        XCTAssertEqual(patch.targetAnchor, "introduction")
        XCTAssertFalse(patch.targetSectionPath.contains("Related Work"))
    }

    func testSnapshotWritingDockDoesNotPreferRelatedWorkWhenNoTargetIsSelected() throws {
        let rootURL = temporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Vault", isDirectory: true)
        let writingRootURL = rootURL.appendingPathComponent("Writing", isDirectory: true)
        let mainFileURL = writingRootURL.appendingPathComponent("main.typ")
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: writingRootURL, withIntermediateDirectories: true)
        try """
        = Introduction
        Context.

        = Related Work
        Prior work.

        = Discussion
        Implications.
        """.write(to: mainFileURL, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let defaults = makeWorkspaceDefaults(
            selectedObsidianVault: makePathRecord(kind: .obsidianVault, path: vaultURL.path),
            writingProjectRoot: makePathRecord(kind: .writingProjectRoot, path: writingRootURL.path),
            mainFilePath: mainFileURL.path
        )
        defaults.writingProjectLocation = WritingProjectLocator().locate(rootPath: writingRootURL.path)
        let session = ReaderWorkbenchSession()
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid

        let snapshot = ResearchWorkbenchSnapshot(
            session: session,
            workspaceDefaults: defaults
        )

        let patch = try XCTUnwrap(snapshot.writingProject.pendingPatches.first)
        XCTAssertEqual(snapshot.writingTargetSection, "Introduction")
        XCTAssertEqual(snapshot.writingTargetSectionOptions, ["Introduction", "Related Work", "Discussion", "Append to end"])
        XCTAssertEqual(patch.targetSectionPath, ["Introduction"])
        XCTAssertEqual(patch.targetAnchor, "introduction")
    }

    func testSnapshotWritingDockFallsBackWhenSelectedTargetNoLongerExists() throws {
        let rootURL = temporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Vault", isDirectory: true)
        let writingRootURL = rootURL.appendingPathComponent("Writing", isDirectory: true)
        let mainFileURL = writingRootURL.appendingPathComponent("main.typ")
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: writingRootURL, withIntermediateDirectories: true)
        try """
        = Introduction
        Context.

        = Method
        Approach.
        """.write(to: mainFileURL, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let defaults = makeWorkspaceDefaults(
            selectedObsidianVault: makePathRecord(kind: .obsidianVault, path: vaultURL.path),
            writingProjectRoot: makePathRecord(kind: .writingProjectRoot, path: writingRootURL.path),
            mainFilePath: mainFileURL.path
        )
        defaults.writingProjectLocation = WritingProjectLocator().locate(rootPath: writingRootURL.path)
        let session = ReaderWorkbenchSession()
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.selectedWritingTargetSection = "Discussion"

        let snapshot = ResearchWorkbenchSnapshot(
            session: session,
            workspaceDefaults: defaults
        )

        let patch = try XCTUnwrap(snapshot.writingProject.pendingPatches.first)
        XCTAssertEqual(snapshot.writingTargetSection, "Introduction")
        XCTAssertEqual(snapshot.writingTargetSectionOptions, ["Introduction", "Method", "Append to end"])
        XCTAssertEqual(patch.targetSectionPath, ["Introduction"])
        XCTAssertEqual(patch.targetAnchor, "introduction")
    }

    func testSnapshotWritingDockUsesSelectedTargetSection() throws {
        let rootURL = temporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Vault", isDirectory: true)
        let writingRootURL = rootURL.appendingPathComponent("Writing", isDirectory: true)
        let mainFileURL = writingRootURL.appendingPathComponent("main.typ")
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: writingRootURL, withIntermediateDirectories: true)
        try """
        = Introduction
        Context.

        = Method
        Approach.

        = Discussion
        Implications.
        """.write(to: mainFileURL, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let block = makeBlock(uid: "p-1", structuralPath: "00001")
        let defaults = makeWorkspaceDefaults(
            selectedObsidianVault: makePathRecord(kind: .obsidianVault, path: vaultURL.path),
            writingProjectRoot: makePathRecord(kind: .writingProjectRoot, path: writingRootURL.path),
            mainFilePath: mainFileURL.path
        )
        defaults.writingProjectLocation = WritingProjectLocator().locate(rootPath: writingRootURL.path)
        let session = ReaderWorkbenchSession()
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.selectedWritingTargetSection = "Discussion"

        let snapshot = ResearchWorkbenchSnapshot(
            session: session,
            workspaceDefaults: defaults
        )

        let patch = try XCTUnwrap(snapshot.writingProject.pendingPatches.first)
        XCTAssertEqual(snapshot.writingTargetSection, "Discussion")
        XCTAssertEqual(snapshot.writingTargetSectionOptions, ["Introduction", "Method", "Discussion", "Append to end"])
        XCTAssertEqual(patch.targetSectionPath, ["Discussion"])
        XCTAssertEqual(patch.targetAnchor, "discussion")
    }

    func testSetupItemsReportRecoverableMissingDependencies() {
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: nil,
            selectedWritingProjectRoot: nil,
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: nil),
            isAPIAvailable: false,
            researchAPIStatus: "API unavailable",
            researchAPIError: nil,
            researchWorkbenchStatus: "No library",
            researchWorkbenchError: nil,
            detectedWorkspacePaths: []
        )

        XCTAssertEqual(
            items.map(\.id),
            ["research-api", "obsidian-vault", "writing-project", "detect-local-apps"]
        )
        XCTAssertEqual(items.first?.action, .refreshAPI)
        XCTAssertEqual(items[1].action, .chooseObsidianVault)
        XCTAssertEqual(items[2].action, .chooseWritingProject)
        XCTAssertEqual(items[3].action, .detectLocalApps)
    }

    func testOnlyBackendRefreshSetupActionsRequireIdleResearchAction() {
        let detectedVault = makePathRecord(kind: .obsidianVault)
        let disabledSkill = makePaperOutlineSkill(status: .disabled)

        XCTAssertTrue(ResearchWorkbenchSetupAction.refreshAPI.requiresIdleResearchAction)
        XCTAssertTrue(ResearchWorkbenchSetupAction.refreshWorkbench.requiresIdleResearchAction)
        XCTAssertTrue(ResearchWorkbenchSetupAction.indexResearchSkills.requiresIdleResearchAction)
        XCTAssertTrue(ResearchWorkbenchSetupAction.enableResearchSkill(disabledSkill).requiresIdleResearchAction)
        XCTAssertNil(ResearchWorkbenchSetupAction.indexResearchSkills.confirmationTitle)
        XCTAssertEqual(
            ResearchWorkbenchSetupAction.enableResearchSkill(disabledSkill).confirmationTitle,
            "Enable Paper Outline?"
        )
        XCTAssertFalse(ResearchWorkbenchSetupAction.detectLocalApps.requiresIdleResearchAction)
        XCTAssertFalse(ResearchWorkbenchSetupAction.chooseBilinLibrary.requiresIdleResearchAction)
        XCTAssertFalse(ResearchWorkbenchSetupAction.chooseZoteroLibrary.requiresIdleResearchAction)
        XCTAssertFalse(ResearchWorkbenchSetupAction.useDetectedWorkspacePath(detectedVault).requiresIdleResearchAction)
        XCTAssertFalse(ResearchWorkbenchSetupAction.chooseObsidianVault.requiresIdleResearchAction)
        XCTAssertFalse(ResearchWorkbenchSetupAction.chooseWritingProject.requiresIdleResearchAction)
    }

    func testSetupItemsDoNotCallUncheckedResearchAPIUnavailable() throws {
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: makePathRecord(kind: .obsidianVault),
            selectedWritingProjectRoot: makePathRecord(kind: .writingProjectRoot),
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            isAPIAvailable: false,
            researchAPIStatus: "Not connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "No library",
            researchWorkbenchError: nil,
            detectedWorkspacePaths: [makePathRecord(kind: .obsidianVault)]
        )

        let apiItem = try XCTUnwrap(items.first { $0.id == "research-api" })
        XCTAssertEqual(apiItem.title, "Research API not checked")
        XCTAssertEqual(apiItem.action, .refreshAPI)
    }

    func testSetupItemsReportReadyWhenCoreWorkflowIsConfigured() {
        let vault = makePathRecord(kind: .obsidianVault)
        let writingRoot = makePathRecord(kind: .writingProjectRoot)
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: vault,
            selectedWritingProjectRoot: writingRoot,
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            isAPIAvailable: true,
            researchAPIStatus: "API connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "Workbench ready",
            researchWorkbenchError: nil,
            detectedWorkspacePaths: [vault],
            researchSkills: [makePaperOutlineSkill()]
        )

        XCTAssertEqual(items.map(\.id), ["ready"])
        XCTAssertNil(items[0].action)
        XCTAssertTrue(items[0].isReady)
    }

    func testSetupItemsReportPermissionAndMainFileProblems() {
        let vault = makePathRecord(kind: .obsidianVault, status: .permissionRequired)
        let writingRoot = makePathRecord(kind: .writingProjectRoot)
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: ConfiguredBilinLibraryRecovery(
                name: "Papers",
                path: "/tmp/missing-library",
                message: "The configured library is missing."
            ),
            selectedObsidianVault: vault,
            selectedWritingProjectRoot: writingRoot,
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: nil),
            isAPIAvailable: true,
            researchAPIStatus: "API connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "No library",
            researchWorkbenchError: nil,
            detectedWorkspacePaths: [vault],
            researchSkills: [makePaperOutlineSkill()]
        )

        XCTAssertEqual(
            items.map(\.id),
            [
                "bilin-library-recovery",
                "obsidian-vault-permission",
                "writing-project-main-file"
            ]
        )
        XCTAssertEqual(items[0].action, .chooseBilinLibrary)
        XCTAssertEqual(items[1].action, .chooseObsidianVault)
        XCTAssertEqual(items[2].action, .chooseWritingProject)
    }

    func testSetupItemsUseSingleDetectedObsidianVaultDirectly() throws {
        let detectedVault = makePathRecord(kind: .obsidianVault)
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: nil,
            selectedWritingProjectRoot: makePathRecord(kind: .writingProjectRoot),
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            isAPIAvailable: true,
            researchAPIStatus: "API connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "Workbench ready",
            researchWorkbenchError: nil,
            detectedWorkspacePaths: [detectedVault],
            researchSkills: [makePaperOutlineSkill()]
        )

        let vaultItem = try XCTUnwrap(items.first { $0.id == "obsidian-vault" })
        XCTAssertEqual(vaultItem.action, .useDetectedWorkspacePath(detectedVault))
    }

    func testSetupItemsExposeDetectedZoteroAsNonBlockingSuggestion() {
        let vault = makePathRecord(kind: .obsidianVault)
        let zotero = makePathRecord(kind: .zoteroLibrary)
        let writingRoot = makePathRecord(kind: .writingProjectRoot)
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: vault,
            selectedWritingProjectRoot: writingRoot,
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            isAPIAvailable: true,
            researchAPIStatus: "API connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "Workbench ready",
            researchWorkbenchError: nil,
            detectedWorkspacePaths: [vault, zotero],
            researchSkills: [makePaperOutlineSkill()]
        )

        XCTAssertEqual(items.map(\.id), ["zotero-library-detected"])
        XCTAssertEqual(items[0].action, .useDetectedWorkspacePath(zotero))
        XCTAssertEqual(items[0].tintRole, .secondary)
    }

    func testSetupItemsOmitDetectedZoteroWhenAlreadyConfigured() {
        let vault = makePathRecord(kind: .obsidianVault)
        let zotero = makePathRecord(kind: .zoteroLibrary)
        let writingRoot = makePathRecord(kind: .writingProjectRoot)
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: vault,
            selectedWritingProjectRoot: writingRoot,
            selectedZoteroLibrary: zotero,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            isAPIAvailable: true,
            researchAPIStatus: "API connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "Workbench ready",
            researchWorkbenchError: nil,
            detectedWorkspacePaths: [vault, zotero],
            researchSkills: [makePaperOutlineSkill()]
        )

        XCTAssertEqual(items.map(\.id), ["ready"])
    }

    func testSetupItemsPromoteLocationUnavailableWorkbenchError() throws {
        let vault = makePathRecord(kind: .obsidianVault)
        let writingRoot = makePathRecord(kind: .writingProjectRoot)
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: vault,
            selectedWritingProjectRoot: writingRoot,
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            isAPIAvailable: true,
            researchAPIStatus: "API connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "Location unavailable",
            researchWorkbenchError: "Missing Vault is missing: /tmp/missing-vault",
            detectedWorkspacePaths: [vault]
        )

        let issue = try XCTUnwrap(items.first { $0.id == "workbench-location-unavailable" })
        XCTAssertEqual(issue.title, "Local location unavailable")
        XCTAssertEqual(issue.action, .detectLocalApps)
        XCTAssertEqual(issue.tintRole, .warning)
    }

    func testSetupItemsPromoteZoteroUnavailableWorkbenchError() throws {
        let vault = makePathRecord(kind: .obsidianVault)
        let writingRoot = makePathRecord(kind: .writingProjectRoot)
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: vault,
            selectedWritingProjectRoot: writingRoot,
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            isAPIAvailable: true,
            researchAPIStatus: "API connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "Zotero unavailable",
            researchWorkbenchError: "zotero.sqlite could not be opened",
            detectedWorkspacePaths: [vault]
        )

        let issue = try XCTUnwrap(items.first { $0.id == "workbench-zotero-unavailable" })
        XCTAssertEqual(issue.title, "Zotero library unavailable")
        XCTAssertEqual(issue.action, .chooseZoteroLibrary)
        XCTAssertEqual(issue.tintRole, .warning)
    }

    func testSetupItemsPromoteWorkbenchUnavailableError() throws {
        let vault = makePathRecord(kind: .obsidianVault)
        let writingRoot = makePathRecord(kind: .writingProjectRoot)
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: vault,
            selectedWritingProjectRoot: writingRoot,
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            isAPIAvailable: true,
            researchAPIStatus: "API connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "Workbench unavailable",
            researchWorkbenchError: "Library has no registered backend record.",
            detectedWorkspacePaths: [vault]
        )

        let issue = try XCTUnwrap(items.first { $0.id == "workbench-unavailable" })
        XCTAssertEqual(issue.action, .refreshWorkbench)
    }

    func testSetupItemsExposeDisabledReadingOutlineSkillAsAuditableEnableAction() throws {
        let vault = makePathRecord(kind: .obsidianVault)
        let writingRoot = makePathRecord(kind: .writingProjectRoot)
        let disabledSkill = makePaperOutlineSkill(status: .disabled)
        let items = ResearchWorkbenchSnapshot.setupItems(
            configuredBilinLibraryRecovery: nil,
            selectedObsidianVault: vault,
            selectedWritingProjectRoot: writingRoot,
            selectedZoteroLibrary: nil,
            writingProject: makeWritingProject(mainFilePath: "/tmp/main.typ"),
            isAPIAvailable: true,
            researchAPIStatus: "API connected",
            researchAPIError: nil,
            researchWorkbenchStatus: "Workbench ready",
            researchWorkbenchError: nil,
            detectedWorkspacePaths: [vault],
            researchSkills: [disabledSkill]
        )

        let skillItem = try XCTUnwrap(items.first { $0.id == "paper-outline-skill-disabled" })
        XCTAssertEqual(skillItem.action, .enableResearchSkill(disabledSkill))
        XCTAssertTrue(skillItem.detail.contains("Permissions: provider_call."))
        XCTAssertTrue(skillItem.detail.contains("Source: /tmp/paper-outline/SKILL.md."))
        XCTAssertTrue(skillItem.detail.contains("Digest: sha256:paper-outline."))
        XCTAssertTrue(skillItem.action?.confirmationMessage?.contains("send this digest and permission list") ?? false)
    }

    func testSnapshotSeparatesNoteBridgeAndWritingDockActionPlans() {
        let session = ReaderWorkbenchSession()
        let selectedBlock = makeBlock(uid: "p-1", structuralPath: "00001")
        let vault = makePathRecord(kind: .obsidianVault, path: "/tmp/current-vault")
        let writingRoot = makePathRecord(kind: .writingProjectRoot, path: "/tmp/current-writing")
        let currentNoteTargetPath = "/tmp/current-vault/Papers/No paper selected.md"
        let currentWritingTargetPath = "/tmp/current-writing/main.typ"
        let defaults = makeWorkspaceDefaults(
            selectedObsidianVault: vault,
            writingProjectRoot: writingRoot,
            mainFilePath: currentWritingTargetPath
        )
        session.blocks = [
            selectedBlock,
            makeBlock(uid: "p-2", structuralPath: "00002")
        ]
        session.selectedBlockUid = selectedBlock.blockUid
        let notePlan = makeActionPlan(
            id: "note",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: currentNoteTargetPath
        )
        let notePatchPlan = makeActionPlan(
            id: "note-patch",
            kind: .notePatch,
            blockUid: "p-1",
            targetPath: currentNoteTargetPath
        )
        let staleNoteBlockPlan = makeActionPlan(
            id: "stale-note-block",
            kind: .writeObsidian,
            blockUid: "p-2",
            targetPath: currentNoteTargetPath
        )
        let staleNoteTargetPlan = makeActionPlan(
            id: "stale-note-target",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/old-vault/Papers/No paper selected.md"
        )
        let writingPlan = makeActionPlan(
            id: "writing",
            kind: .editManuscript,
            blockUid: "p-1",
            targetPath: currentWritingTargetPath
        )
        let writingPatchPlan = makeActionPlan(
            id: "writing-patch",
            kind: .writingPatch,
            blockUid: "p-1",
            targetPath: currentWritingTargetPath
        )
        let staleWritingTargetPlan = makeActionPlan(
            id: "stale-writing-target",
            kind: .editManuscript,
            blockUid: "p-1",
            targetPath: "/tmp/old-writing/main.typ"
        )
        let unrelatedPlan = makeActionPlan(
            id: "download",
            kind: .downloadPaper,
            blockUid: "p-1",
            targetPath: currentNoteTargetPath
        )
        session.researchActionPlans = [
            notePlan,
            writingPlan,
            unrelatedPlan,
            notePatchPlan,
            writingPatchPlan,
            staleNoteBlockPlan,
            staleNoteTargetPlan,
            staleWritingTargetPlan
        ]

        let snapshot = ResearchWorkbenchSnapshot(
            session: session,
            workspaceDefaults: defaults
        )

        XCTAssertEqual(snapshot.noteActionPlans.map(\.id), ["note", "note-patch"])
        XCTAssertEqual(snapshot.writingActionPlans.map(\.id), ["writing", "writing-patch"])
    }

    func testSnapshotFiltersResearchPlanActionPlansByCurrentArticleRevision() {
        let session = ReaderWorkbenchSession()
        let article = makeArticle()
        session.articles = [article]
        session.selectedLibraryItem = .article(id: article.id)
        session.researchSkills = [makePaperOutlineSkill()]
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")
        let current = makeResearchPlanActionPlan(
            id: "current-outline",
            articleRevisionId: "revision-1"
        )
        let stale = makeResearchPlanActionPlan(
            id: "stale-outline",
            articleRevisionId: "revision-2"
        )
        let unrelated = makeActionPlan(
            id: "note",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/current-vault/Papers/Paper.md"
        )
        session.researchActionPlans = [current, stale, unrelated]

        let snapshot = ResearchWorkbenchSnapshot(session: session)

        XCTAssertTrue(snapshot.researchPlanActionReadiness.isReady)
        XCTAssertEqual(snapshot.researchPlanActionPlans.map(\.id), ["current-outline"])
        XCTAssertTrue(snapshot.noteActionPlans.isEmpty)
        XCTAssertTrue(snapshot.writingActionPlans.isEmpty)
    }

    func testSnapshotShowsResearchPlanActionPlansForSelectedZoteroItem() {
        let session = ReaderWorkbenchSession()
        session.zoteroItems = [
            ZoteroItem(
                id: 42,
                key: "ZOT42",
                itemType: "journalArticle",
                title: "Zotero ArXiv Paper",
                abstractNote: nil,
                date: nil,
                doi: nil,
                url: nil,
                extra: nil,
                libraryCatalog: nil
            )
        ]
        session.selectedLibraryItem = .zoteroItem(id: 42)
        let currentImport = makeZoteroImportActionPlan(id: "current-zotero-import", zoteroItemId: 42)
        let staleImport = makeZoteroImportActionPlan(id: "stale-zotero-import", zoteroItemId: 99)
        let outline = makeResearchPlanActionPlan(
            id: "article-outline",
            articleRevisionId: "revision-1"
        )
        session.researchActionPlans = [currentImport, staleImport, outline]

        let snapshot = ResearchWorkbenchSnapshot(session: session)

        XCTAssertEqual(snapshot.researchPlanActionPlans.map(\.id), ["current-zotero-import"])
        XCTAssertTrue(snapshot.noteActionPlans.isEmpty)
        XCTAssertTrue(snapshot.writingActionPlans.isEmpty)
    }

    func testZoteroImportActionPlansExposeImportBundleApplyCommand() {
        XCTAssertEqual(
            AgentActionPlanLocalExecutionPolicy.applyButtonTitle(for: .downloadPaper),
            "Write Import Bundle"
        )
        XCTAssertEqual(
            AgentActionPlanLocalExecutionPolicy.applyButtonHelp(for: .downloadPaper),
            "Write the approved import bundle into the local Bilin library."
        )
        XCTAssertEqual(
            AgentActionPlanLocalExecutionPolicy.applyButtonTitle(for: .importLibrary),
            "Write Import Bundle"
        )
        XCTAssertEqual(
            AgentActionPlanLocalExecutionPolicy.applyButtonHelp(for: .importLibrary),
            "Write the approved import bundle into the local Bilin library."
        )
    }

    func testActionPlanApprovalPolicyNamesTheActionBeingConfirmed() {
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonTitle(for: .writeObsidian),
            "Approve Note Patch"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonHelp(for: .writeObsidian),
            "Approve this Note Bridge patch before any local Markdown write runs."
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonTitle(for: .notePatch),
            "Reject Note Patch"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonHelp(for: .notePatch),
            "Reject this Note Bridge patch without writing local Markdown."
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonTitle(for: .writingPatch),
            "Approve Writing Patch"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonHelp(for: .writingPatch),
            "Approve this Writing Dock patch before any Typst or TeX write runs."
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonTitle(for: .editManuscript),
            "Reject Writing Patch"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonHelp(for: .editManuscript),
            "Reject this Writing Dock patch without writing Typst or TeX."
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonTitle(for: .downloadPaper),
            "Approve Import"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonHelp(for: .downloadPaper),
            "Approve this import plan before any local library bundle is written."
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonTitle(for: .importLibrary),
            "Reject Import"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonHelp(for: .importLibrary),
            "Reject this import plan without writing a local library bundle."
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonTitle(for: .generateResearchOutline),
            "Approve Outline"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonHelp(for: .generateResearchOutline),
            "Approve this Research Plan outline action before provider execution."
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonTitle(for: .generateResearchOutline),
            "Reject Outline"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonHelp(for: .generateResearchOutline),
            "Reject this Research Plan outline action without provider execution."
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonTitle(for: .installSkill),
            "Approve Skill Install"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonTitle(for: .enableSkill),
            "Reject Skill Enable"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonTitle(for: .providerCall),
            "Approve Provider Call"
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.approveButtonHelp(for: .providerCall),
            "Approve this provider call before any model request is sent."
        )
        XCTAssertEqual(
            AgentActionPlanApprovalPolicy.rejectButtonTitle(for: .custom),
            "Reject Action"
        )
    }

    func testActionPlanExecutionPoliciesExplainApplyAndRunCommands() {
        XCTAssertEqual(
            AgentActionPlanLocalExecutionPolicy.applyButtonHelp(for: .writeObsidian),
            "Write the approved Note Bridge patch to the target Markdown file."
        )
        XCTAssertEqual(
            AgentActionPlanLocalExecutionPolicy.applyButtonHelp(for: .writingPatch),
            "Write the approved Writing Dock patch to the target Typst or TeX file."
        )
        XCTAssertNil(AgentActionPlanLocalExecutionPolicy.applyButtonHelp(for: .generateResearchOutline))
        XCTAssertEqual(
            AgentActionPlanRemoteExecutionPolicy.runButtonTitle(for: .generateResearchOutline),
            "Generate Outline"
        )
        XCTAssertEqual(
            AgentActionPlanRemoteExecutionPolicy.runButtonHelp(for: .generateResearchOutline),
            "Run the approved outline action through the Research API."
        )
        XCTAssertNil(AgentActionPlanRemoteExecutionPolicy.runButtonHelp(for: .writeObsidian))
    }

    func testSnapshotUsesGeneratedReadingOutlineFromSucceededResearchPlanAction() throws {
        let session = ReaderWorkbenchSession()
        let article = makeArticle()
        session.articles = [article]
        session.selectedLibraryItem = .article(id: article.id)
        session.blocks = [makeBlock(uid: "p-1", structuralPath: "00001")]
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")
        let outlineJSON = """
        {
          "title": "Agent mastery outline",
          "summary": "Understand the proof obligations before reading the benchmark table.",
          "items": [
            {
              "id": "generated-claim",
              "kind": "claim",
              "title": "Core convergence claim",
              "summaryMarkdown": "Track the assumptions that make the convergence statement true.",
              "importance": "high"
            }
          ],
          "questions": ["Which assumption fails outside the toy setting?"],
          "paperMasteryOutlines": [
            {
              "paper_id": "2401.00001",
              "paper_title": "Research Paper",
              "claim": ["The optimization procedure converges."],
              "method": ["Construct the surrogate objective."],
              "followUp": ["Compare against a nonconvex baseline."]
            }
          ]
        }
        """
        session.researchActionPlans = [
            makeResearchPlanActionPlan(
                id: "generated-outline",
                articleRevisionId: "revision-1",
                status: .succeeded,
                result: ["reading_outline": outlineJSON]
            )
        ]

        let snapshot = ResearchWorkbenchSnapshot(session: session)

        XCTAssertEqual(snapshot.outline.title, "Agent mastery outline")
        XCTAssertEqual(snapshot.outline.status, .ready)
        XCTAssertEqual(snapshot.outline.summary, "Understand the proof obligations before reading the benchmark table.")
        XCTAssertEqual(snapshot.outline.items.first?.title, "Core convergence claim")
        XCTAssertEqual(snapshot.outline.questions, ["Which assumption fails outside the toy setting?"])
        let mastery = try XCTUnwrap(snapshot.outline.paperMasteryOutlines.first)
        XCTAssertEqual(mastery.claim, ["The optimization procedure converges."])
        XCTAssertEqual(mastery.method, ["Construct the surrogate objective."])
        XCTAssertEqual(mastery.followUp, ["Compare against a nonconvex baseline."])
    }

    func testSnapshotPrefersPersistedResearchPlanOutlineOverActionResult() throws {
        let session = ReaderWorkbenchSession()
        let article = makeArticle()
        session.articles = [article]
        session.selectedLibraryItem = .article(id: article.id)
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")
        session.researchPlans = [
            makeResearchPlan(
                id: "persisted-plan",
                articleRevisionId: "revision-1",
                status: .completed,
                outline: ReadingOutline(
                    id: "persisted-outline",
                    articleRevisionId: "revision-1",
                    title: "Persisted mastery outline",
                    status: .ready,
                    items: [
                        ReadingOutlineItem(
                            id: "persisted-item",
                            kind: .claim,
                            title: "Persisted claim",
                            summaryMarkdown: "This came from the saved ResearchPlan."
                        )
                    ],
                    summary: "Saved outline survives workbench refresh.",
                    questions: ["Which saved question remains open?"],
                    generatedAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            )
        ]
        session.researchActionPlans = [
            makeResearchPlanActionPlan(
                id: "action-outline",
                articleRevisionId: "revision-1",
                status: .succeeded,
                result: [
                    "reading_outline": """
                    {
                      "title": "Action result outline",
                      "summary": "This should lose to the persisted plan."
                    }
                    """
                ]
            )
        ]

        let snapshot = ResearchWorkbenchSnapshot(session: session)

        XCTAssertEqual(snapshot.outline.title, "Persisted mastery outline")
        XCTAssertEqual(snapshot.outline.summary, "Saved outline survives workbench refresh.")
        XCTAssertEqual(snapshot.outline.items.first?.title, "Persisted claim")
        XCTAssertEqual(snapshot.outline.questions, ["Which saved question remains open?"])
    }

    func testSnapshotKeyChangesWhenPersistedResearchPlansChange() {
        let session = ReaderWorkbenchSession()
        let firstKey = ResearchWorkbenchSnapshotKey(session: session)

        session.researchPlans = [
            makeResearchPlan(
                id: "persisted-plan",
                articleRevisionId: "revision-1",
                status: .completed,
                outline: ReadingOutline(
                    id: "persisted-outline",
                    articleRevisionId: "revision-1",
                    title: "Persisted mastery outline",
                    generatedAt: Date(timeIntervalSince1970: 0),
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
            )
        ]
        let secondKey = ResearchWorkbenchSnapshotKey(session: session)

        XCTAssertNotEqual(firstKey, secondKey)
    }

    func testActionPlanTargetFreshnessDetectsCurrentAndStaleTargets() {
        let targetPath = "/tmp/current-vault/Papers/No paper selected.md"
        let currentText = "Current external note"
        let currentHash = LocalFilePatchExecutor.contentHash(for: currentText)
        let staleHash = LocalFilePatchExecutor.contentHash(for: "Earlier external note")
        let currentPlan = makeActionPlan(
            id: "current",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: targetPath,
            baseFileHash: currentHash
        )
        let stalePlan = makeActionPlan(
            id: "stale",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: targetPath,
            baseFileHash: staleHash
        )
        let untrackedPlan = makeActionPlan(
            id: "untracked",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: targetPath
        )

        XCTAssertEqual(
            AgentActionPlanTargetFreshness.evaluate(currentPlan, fileReader: { _ in currentText }),
            .current
        )
        XCTAssertEqual(
            AgentActionPlanTargetFreshness.evaluate(stalePlan, fileReader: { _ in currentText }),
            .stale(expectedHash: staleHash, observedHash: currentHash)
        )
        XCTAssertEqual(
            AgentActionPlanTargetFreshness.evaluate(untrackedPlan, fileReader: { _ in currentText }),
            .notTracked
        )
    }

    func testStaleActionPlanBlocksOnlyPreWriteStatuses() {
        let freshness = AgentActionPlanTargetFreshness.stale(
            expectedHash: LocalFilePatchExecutor.contentHash(for: "Before"),
            observedHash: LocalFilePatchExecutor.contentHash(for: "After")
        )

        XCTAssertTrue(freshness.blocksLocalWrite(for: .pendingApproval))
        XCTAssertTrue(freshness.blocksLocalWrite(for: .approved))
        XCTAssertFalse(freshness.blocksLocalWrite(for: .failed))
        XCTAssertFalse(freshness.blocksLocalWrite(for: .succeeded))
        XCTAssertFalse(AgentActionPlanTargetFreshness.current.blocksLocalWrite(for: .approved))
        XCTAssertFalse(AgentActionPlanTargetFreshness.notTracked.blocksLocalWrite(for: .approved))
    }

    func testActionPlanRowActionsRecoverInsteadOfApprovingStaleLocalWrites() {
        let plan = makeActionPlan(
            id: "stale-note",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/current-vault/Papers/Paper.md",
            status: .pendingApproval
        )
        let actions = AgentActionPlanRowActions.resolve(
            plan,
            targetFreshness: .stale(expectedHash: "before", observedHash: "after"),
            hasApprove: true,
            hasReject: true,
            hasApply: true,
            hasRun: true,
            hasRecover: true
        )

        XCTAssertTrue(actions.showsRecovery)
        XCTAssertTrue(actions.showsRegenerate)
        XCTAssertTrue(actions.showsContextPreview)
        XCTAssertTrue(actions.showsAbandon)
        XCTAssertFalse(actions.showsApprove)
        XCTAssertFalse(actions.showsReject)
        XCTAssertFalse(actions.showsApply)
        XCTAssertFalse(actions.showsRun)
    }

    func testActionPlanRowActionsExposeOnlyRunnableApprovedActions() {
        let notePlan = makeActionPlan(
            id: "approved-note",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/current-vault/Papers/Paper.md",
            status: .approved
        )
        let outlinePlan = makeResearchPlanActionPlan(
            id: "approved-outline",
            articleRevisionId: "revision-1",
            status: .approved
        )

        let noteActions = AgentActionPlanRowActions.resolve(
            notePlan,
            targetFreshness: .current,
            hasApprove: true,
            hasReject: true,
            hasApply: true,
            hasRun: true,
            hasRecover: true
        )
        let outlineActions = AgentActionPlanRowActions.resolve(
            outlinePlan,
            targetFreshness: .notTracked,
            hasApprove: true,
            hasReject: true,
            hasApply: true,
            hasRun: true,
            hasRecover: true
        )

        XCTAssertTrue(noteActions.showsApply)
        XCTAssertFalse(noteActions.showsRun)
        XCTAssertFalse(noteActions.showsApprove)
        XCTAssertFalse(noteActions.showsReject)
        XCTAssertFalse(noteActions.showsRecovery)

        XCTAssertFalse(outlineActions.showsApply)
        XCTAssertTrue(outlineActions.showsRun)
        XCTAssertFalse(outlineActions.showsApprove)
        XCTAssertFalse(outlineActions.showsReject)
        XCTAssertFalse(outlineActions.showsRecovery)
    }

    func testActionPlanRowActionsKeepFailedActionContextVisibleWithoutRecoveryCallbacks() {
        let failedOutline = makeResearchPlanActionPlan(
            id: "failed-outline",
            articleRevisionId: "revision-1",
            status: .failed
        )
        let actions = AgentActionPlanRowActions.resolve(
            failedOutline,
            targetFreshness: .notTracked,
            hasApprove: false,
            hasReject: false,
            hasApply: false,
            hasRun: false,
            hasRecover: false
        )

        XCTAssertTrue(actions.showsRecovery)
        XCTAssertFalse(actions.showsRegenerate)
        XCTAssertTrue(actions.showsContextPreview)
        XCTAssertFalse(actions.showsAbandon)
        XCTAssertFalse(actions.showsApprove)
        XCTAssertFalse(actions.showsReject)
        XCTAssertFalse(actions.showsApply)
        XCTAssertFalse(actions.showsRun)
    }

    func testActionPlanRowActionsKeepLocalRecoveryVisibleWhileResearchActionIsBusy() {
        let failedConflict = makeActionPlan(
            id: "failed-conflict-busy",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            status: .failed,
            error: [
                "code": "file_changed_since_preview",
                "message": "Target file changed since preview."
            ]
        )

        let actions = AgentActionPlanRowActions.resolve(
            failedConflict,
            targetFreshness: .stale(expectedHash: "before", observedHash: "after"),
            hasApprove: true,
            hasReject: true,
            hasApply: true,
            hasRun: true,
            hasRecover: true,
            isResearchActionBusy: true
        )

        XCTAssertTrue(actions.showsRecovery)
        XCTAssertFalse(actions.showsRegenerate)
        XCTAssertTrue(actions.showsContextPreview)
        XCTAssertTrue(actions.showsAbandon)
        XCTAssertFalse(actions.showsApprove)
        XCTAssertFalse(actions.showsReject)
        XCTAssertFalse(actions.showsApply)
        XCTAssertFalse(actions.showsRun)
    }

    func testActionPlanRowActionsHideMutatingActionsWhileResearchActionIsBusy() {
        let pendingNote = makeActionPlan(
            id: "pending-note-busy",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/current-vault/Papers/Paper.md",
            status: .pendingApproval
        )
        let approvedNote = makeActionPlan(
            id: "approved-note-busy",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/current-vault/Papers/Paper.md",
            status: .approved
        )
        let approvedOutline = makeResearchPlanActionPlan(
            id: "approved-outline-busy",
            articleRevisionId: "revision-1",
            status: .approved
        )

        let pendingActions = AgentActionPlanRowActions.resolve(
            pendingNote,
            targetFreshness: .current,
            hasApprove: true,
            hasReject: true,
            hasApply: true,
            hasRun: true,
            hasRecover: true,
            isResearchActionBusy: true
        )
        let approvedNoteActions = AgentActionPlanRowActions.resolve(
            approvedNote,
            targetFreshness: .current,
            hasApprove: true,
            hasReject: true,
            hasApply: true,
            hasRun: true,
            hasRecover: true,
            isResearchActionBusy: true
        )
        let approvedOutlineActions = AgentActionPlanRowActions.resolve(
            approvedOutline,
            targetFreshness: .notTracked,
            hasApprove: true,
            hasReject: true,
            hasApply: true,
            hasRun: true,
            hasRecover: true,
            isResearchActionBusy: true
        )

        XCTAssertFalse(pendingActions.showsApprove)
        XCTAssertFalse(pendingActions.showsReject)
        XCTAssertFalse(approvedNoteActions.showsApply)
        XCTAssertFalse(approvedOutlineActions.showsRun)
    }

    func testActionPlanStatusPresentationUsesInterruptionTintForTerminalFailures() {
        XCTAssertEqual(AgentActionPlanStatusPresentation.resolve(.failed).tintRole, .warning)
        XCTAssertEqual(AgentActionPlanStatusPresentation.resolve(.rejected).tintRole, .warning)
        XCTAssertEqual(AgentActionPlanStatusPresentation.resolve(.cancelled).tintRole, .warning)
        XCTAssertEqual(AgentActionPlanStatusPresentation.resolve(.succeeded).tintRole, .accent)
        XCTAssertEqual(AgentActionPlanStatusPresentation.resolve(.draft).tintRole, .secondary)
    }

    func testActionPlanRecoveryPresentationClassifiesFileConflictAndImportFailure() throws {
        let failedConflict = makeActionPlan(
            id: "failed-conflict",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            status: .failed,
            error: [
                "code": "file_changed_since_preview",
                "message": "Target file changed since preview.",
                "expected_base_file_hash": "before",
                "observed_file_hash": "after"
            ]
        )
        let staleApproved = makeActionPlan(
            id: "stale-approved",
            kind: .writingPatch,
            blockUid: "p-1",
            targetPath: "/tmp/paper/main.typ",
            status: .approved
        )
        let failedImport = makeZoteroImportActionPlan(
            id: "failed-import",
            zoteroItemId: 42,
            status: .failed,
            error: [
                "code": "zotero_import_bundle_failed",
                "message": "Attachment missing"
            ]
        )

        let conflictPresentation = try XCTUnwrap(AgentActionPlanRecoveryPresentation.resolve(failedConflict))
        let stalePresentation = try XCTUnwrap(AgentActionPlanRecoveryPresentation.resolve(
            staleApproved,
            targetFreshness: .stale(expectedHash: "before", observedHash: "after")
        ))
        let importPresentation = try XCTUnwrap(AgentActionPlanRecoveryPresentation.resolve(failedImport))

        XCTAssertEqual(conflictPresentation.regenerateTitle, "Regenerate Patch")
        XCTAssertEqual(conflictPresentation.contextPreviewButtonTitle, "View Current Diff")
        XCTAssertEqual(conflictPresentation.contextPreviewTitle, "Diff Preview")
        XCTAssertEqual(conflictPresentation.contextPreviewKind, .diff)
        XCTAssertEqual(conflictPresentation.abandonTitle, "Abandon Write")
        XCTAssertEqual(conflictPresentation.contextPreviewToggleTitle(isExpanded: false), "View Current Diff")
        XCTAssertEqual(conflictPresentation.contextPreviewToggleTitle(isExpanded: true), "Hide Current Diff")
        XCTAssertEqual(conflictPresentation.contextPreviewToggleSystemImage(isExpanded: false), "doc.text.magnifyingglass")
        XCTAssertEqual(conflictPresentation.contextPreviewToggleSystemImage(isExpanded: true), "chevron.up.square")
        XCTAssertEqual(
            conflictPresentation.contextPreviewToggleHelp(isExpanded: false),
            "Compare the current target file context with the planned local write before regenerating or abandoning this attempt."
        )
        XCTAssertEqual(stalePresentation.message, conflictPresentation.message)

        XCTAssertEqual(importPresentation.message, "The import did not finish. Regenerate the import plan, inspect the action payload, or dismiss this attempt.")
        XCTAssertEqual(importPresentation.regenerateTitle, "Regenerate Import Plan")
        XCTAssertEqual(importPresentation.contextPreviewButtonTitle, "View Payload")
        XCTAssertEqual(importPresentation.contextPreviewTitle, "Action Payload")
        XCTAssertEqual(importPresentation.contextPreviewKind, .actionContext)
        XCTAssertEqual(importPresentation.abandonTitle, "Dismiss Action")
        XCTAssertEqual(importPresentation.contextPreviewToggleTitle(isExpanded: true), "Hide Payload")
        XCTAssertEqual(
            importPresentation.contextPreviewToggleHelp(isExpanded: false),
            "Inspect the recorded action payload before deciding whether to regenerate or dismiss this attempt."
        )
    }

    func testActionPlanRecoveryFileActionsExposeTargetFilesForFailedAndStaleWrites() {
        let failedConflict = makeActionPlan(
            id: "failed-conflict-target",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            status: .failed,
            error: [
                "code": "file_changed_since_preview",
                "message": "Target file changed since preview."
            ]
        )
        let staleApproved = makeActionPlan(
            id: "stale-approved-target",
            kind: .writingPatch,
            blockUid: "p-1",
            targetPath: "/tmp/paper/main.typ",
            status: .approved
        )
        let pendingCurrent = makeActionPlan(
            id: "pending-current-target",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            status: .pendingApproval
        )
        let failedImport = makeZoteroImportActionPlan(
            id: "failed-import-target",
            zoteroItemId: 42,
            status: .failed
        )

        XCTAssertEqual(
            AgentActionPlanRecoveryFileActions.resolve(failedConflict),
            [
                AgentActionPlanResultFileAction(
                    kind: .openFile,
                    title: "Open Target",
                    systemImage: "doc.text.magnifyingglass",
                    path: "/tmp/Vault/Papers/Paper.md"
                ),
                AgentActionPlanResultFileAction(
                    kind: .revealInFinder,
                    title: "Reveal Target",
                    systemImage: "folder",
                    path: "/tmp/Vault/Papers/Paper.md"
                )
            ]
        )
        XCTAssertEqual(
            AgentActionPlanRecoveryFileActions.resolve(
                staleApproved,
                targetFreshness: .stale(expectedHash: "before", observedHash: "after")
            ),
            [
                AgentActionPlanResultFileAction(
                    kind: .openFile,
                    title: "Open Target",
                    systemImage: "doc.text.magnifyingglass",
                    path: "/tmp/paper/main.typ"
                ),
                AgentActionPlanResultFileAction(
                    kind: .revealInFinder,
                    title: "Reveal Target",
                    systemImage: "folder",
                    path: "/tmp/paper/main.typ"
                )
            ]
        )
        XCTAssertTrue(AgentActionPlanRecoveryFileActions.resolve(pendingCurrent).isEmpty)
        XCTAssertTrue(AgentActionPlanRecoveryFileActions.resolve(failedImport).isEmpty)
    }

    func testActionPlanRecoveryTargetPathFeedsFileActionsFreshnessAndDiffPreview() {
        let recoveryTargetPath = "/tmp/Vault/Papers/Recovered.md"
        let baseHash = LocalFilePatchExecutor.contentHash(for: "Original note")
        let failedPlan = makeActionPlan(
            id: "failed-recovery-target",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "",
            baseFileHash: baseHash,
            status: .failed,
            payload: [
                "recovery_target_path": recoveryTargetPath,
                "patch": "> [!note]\n> Recovered note"
            ],
            error: [
                "code": "file_changed_since_preview",
                "observed_file_hash": LocalFilePatchExecutor.contentHash(for: "Current note")
            ]
        )

        XCTAssertEqual(
            AgentActionPlanRecoveryFileActions.resolve(failedPlan).map(\.path),
            [recoveryTargetPath, recoveryTargetPath]
        )
        XCTAssertEqual(
            AgentActionPlanTargetFreshness.evaluate(failedPlan) { path in
                path == recoveryTargetPath ? "Current note" : nil
            },
            .stale(
                expectedHash: baseHash,
                observedHash: LocalFilePatchExecutor.contentHash(for: "Current note")
            )
        )

        let diffPreview = AgentActionPlanDiffPreview.render(failedPlan) { path in
            path == recoveryTargetPath ? "Current note" : nil
        }
        XCTAssertTrue(diffPreview.contains("Target: \(recoveryTargetPath)"))
        XCTAssertTrue(diffPreview.contains("Recovered note"))
    }

    func testActionPlanTargetFreshnessPreviewShowsVerifiedAndChangedTargets() throws {
        let baseHash = LocalFilePatchExecutor.contentHash(for: "Current file text")
        let pendingCurrent = makeActionPlan(
            id: "pending-current-target-preview",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            baseFileHash: baseHash,
            status: .pendingApproval
        )
        let approvedStale = makeActionPlan(
            id: "approved-stale-target-preview",
            kind: .writingPatch,
            blockUid: "p-1",
            targetPath: "/tmp/paper/main.typ",
            baseFileHash: "before",
            status: .approved
        )
        let succeededCurrent = makeActionPlan(
            id: "succeeded-current-target-preview",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            baseFileHash: baseHash,
            status: .succeeded
        )

        let currentPreview = try XCTUnwrap(AgentActionPlanTargetFreshnessPreview.resolve(
            pendingCurrent,
            targetFreshness: .current
        ))
        let stalePreview = try XCTUnwrap(AgentActionPlanTargetFreshnessPreview.resolve(
            approvedStale,
            targetFreshness: .stale(expectedHash: "before", observedHash: "after")
        ))

        XCTAssertEqual(currentPreview.title, "Target verified")
        XCTAssertTrue(currentPreview.value.contains("Target file matches the preview base hash."))
        XCTAssertTrue(currentPreview.value.contains("Target: /tmp/Vault/Papers/Paper.md"))
        XCTAssertTrue(currentPreview.value.contains("Base hash: \(baseHash)"))
        XCTAssertEqual(stalePreview.title, "Target changed")
        XCTAssertTrue(stalePreview.value.contains("Expected base hash: before"))
        XCTAssertTrue(stalePreview.value.contains("Observed current hash: after"))
        XCTAssertNil(AgentActionPlanTargetFreshnessPreview.resolve(succeededCurrent, targetFreshness: .current))
    }

    func testActionPlanDiffPreviewFocusesCurrentTargetContextAndPlannedWrite() {
        let currentText = [
            "# Paper Notes",
            "",
            "## Background",
            "Earlier note.",
            "",
            "## Related Work",
            "External editor changed this section.",
            "",
            "## Limitations",
            "Still open."
        ].joined(separator: "\n")
        let originalText = [
            "# Paper Notes",
            "",
            "## Background",
            "Earlier note.",
            "",
            "## Related Work",
            "",
            "## Limitations",
            "Still open."
        ].joined(separator: "\n")
        let expectedHash = LocalFilePatchExecutor.contentHash(for: originalText)
        let observedHash = LocalFilePatchExecutor.contentHash(for: currentText)
        let plan = makeActionPlan(
            id: "note-conflict",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            baseFileHash: expectedHash,
            payload: [
                "target_anchor": "## Related Work"
            ],
            preview: [
                "patch": "> New related-work excerpt\n\n<!-- ^p-1 -->"
            ]
        )

        let preview = AgentActionPlanDiffPreview.render(plan, fileReader: { _ in currentText })

        XCTAssertTrue(preview.contains("Target: /tmp/Vault/Papers/Paper.md"))
        XCTAssertTrue(preview.contains("Expected base hash: \(expectedHash)"))
        XCTAssertTrue(preview.contains("Observed current hash: \(observedHash)"))
        XCTAssertTrue(preview.contains("--- Current target context"))
        XCTAssertTrue(preview.contains("   6 | ## Related Work"))
        XCTAssertTrue(preview.contains("External editor changed this section."))
        XCTAssertTrue(preview.contains("+++ Planned local write"))
        XCTAssertTrue(preview.contains("<!-- ilios-action-plan:note-conflict -->"))
        XCTAssertTrue(preview.contains("> New related-work excerpt"))
        XCTAssertTrue(preview.contains("<!-- /ilios-action-plan:note-conflict -->"))
    }

    func testActionPlanAuditPreviewExposesPatchBeforeApproval() throws {
        let notePlan = makeActionPlan(
            id: "note-preview",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            baseFileHash: "base-hash-1",
            payload: [
                "target_anchor": "## Related Work"
            ],
            preview: ["patch": "> Selected note excerpt"]
        )
        let writingPlan = makeActionPlan(
            id: "writing-preview",
            kind: .editManuscript,
            blockUid: "p-1",
            targetPath: "/tmp/paper/main.typ",
            baseFileHash: "base-hash-2",
            payload: ["preview_markdown": "#quote[Selected manuscript excerpt]"]
        )
        let outlinePlan = makeResearchPlanActionPlan(
            id: "outline-preview",
            articleRevisionId: "revision-1",
            result: ["reading_outline": #"{"title":"Master paper"}"#]
        )
        let zoteroPlan = makeZoteroImportActionPlan(
            id: "zotero-preview",
            zoteroItemId: 42,
            preview: [
                "candidate_summary": "Zotero ArXiv Paper\narXiv: 2401.00001v2",
                "import_summary": "Download the arXiv paper before import."
            ]
        )

        let notePreview = try XCTUnwrap(AgentActionPlanAuditPreview.resolve(notePlan))
        let writingPreview = try XCTUnwrap(AgentActionPlanAuditPreview.resolve(writingPlan))
        let outlinePreview = try XCTUnwrap(AgentActionPlanAuditPreview.resolve(outlinePlan))
        let zoteroPreview = try XCTUnwrap(AgentActionPlanAuditPreview.resolve(zoteroPlan))

        XCTAssertEqual(notePreview.title, "Note Patch Preview")
        XCTAssertNil(notePreview.maxLines)
        XCTAssertTrue(notePreview.value.contains("Target: /tmp/Vault/Papers/Paper.md"))
        XCTAssertTrue(notePreview.value.contains("Anchor: ## Related Work"))
        XCTAssertTrue(notePreview.value.contains("Source block: p-1"))
        XCTAssertTrue(notePreview.value.contains("Base hash: base-hash-1"))
        XCTAssertTrue(notePreview.value.contains("> Selected note excerpt"))
        XCTAssertEqual(writingPreview.title, "Writing Patch Preview")
        XCTAssertNil(writingPreview.maxLines)
        XCTAssertTrue(writingPreview.value.contains("Target: /tmp/paper/main.typ"))
        XCTAssertTrue(writingPreview.value.contains("Source block: p-1"))
        XCTAssertTrue(writingPreview.value.contains("Base hash: base-hash-2"))
        XCTAssertTrue(writingPreview.value.contains("#quote[Selected manuscript excerpt]"))
        XCTAssertEqual(outlinePreview.title, "Outline Preview")
        XCTAssertEqual(outlinePreview.maxLines, 12)
        XCTAssertEqual(outlinePreview.value, #"{"title":"Master paper"}"#)
        XCTAssertEqual(zoteroPreview.title, "Zotero Import Preview")
        XCTAssertEqual(zoteroPreview.maxLines, 12)
        XCTAssertEqual(
            zoteroPreview.value,
            "Zotero ArXiv Paper\narXiv: 2401.00001v2\n\nDownload the arXiv paper before import."
        )
    }

    func testWorkbenchCopyActionsKeepMetadataAndPreviewValuesExact() {
        let longPath = "/tmp/Vault/Papers/Very Long Folder Name/Paper With A Long Title.md"
        let valuePresentation = WorkbenchValuePresentation.metadata(value: longPath)
        let metadataAction = WorkbenchCopyAction.value(
            label: "Target file",
            value: "/tmp/Vault/Papers/Paper.md"
        )
        let fallbackMetadataAction = WorkbenchCopyAction.value(
            label: "   ",
            value: "sha256:abc123"
        )
        let previewAction = WorkbenchCopyAction.preview(
            title: "Note Patch Preview",
            value: "Target: /tmp/Vault/Papers/Paper.md\n\n> Selected note excerpt"
        )
        let fallbackPreviewAction = WorkbenchCopyAction.preview(
            title: "   ",
            value: "payload"
        )

        XCTAssertEqual(valuePresentation.value, longPath)
        XCTAssertEqual(valuePresentation.hoverHelp, longPath)
        XCTAssertEqual(valuePresentation.lineLimit, 2)
        XCTAssertEqual(metadataAction.title, "Copy Target file")
        XCTAssertEqual(metadataAction.help, "Copy Target file value")
        XCTAssertEqual(metadataAction.systemImage, "doc.on.doc")
        XCTAssertEqual(metadataAction.value, "/tmp/Vault/Papers/Paper.md")
        XCTAssertEqual(fallbackMetadataAction.title, "Copy Value")
        XCTAssertEqual(fallbackMetadataAction.help, "Copy value")
        XCTAssertEqual(fallbackMetadataAction.value, "sha256:abc123")
        XCTAssertEqual(previewAction.title, "Copy Note Patch Preview")
        XCTAssertEqual(previewAction.help, "Copy preview text")
        XCTAssertEqual(previewAction.value, "Target: /tmp/Vault/Papers/Paper.md\n\n> Selected note excerpt")
        XCTAssertEqual(fallbackPreviewAction.title, "Copy Preview")
        XCTAssertEqual(fallbackPreviewAction.value, "payload")
    }

    func testActionPlanAuditMetadataExposesTargetAndBaseHashBeforeApproval() throws {
        let notePlan = makeActionPlan(
            id: "note-audit",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            baseFileHash: "base-hash-1"
        )
        let stepTargetPlan = AgentActionPlan(
            id: "step-audit",
            kind: .writingPatch,
            status: .pendingApproval,
            title: "step-audit",
            summary: "Test step target fallback",
            requestedPermissions: [],
            steps: [
                AgentActionStep(
                    id: "step-1",
                    kind: .writeFile,
                    title: "Write manuscript patch",
                    targetPath: "/tmp/paper/main.typ"
                )
            ],
            payloadHash: "payload-step-audit",
            payload: ["base_hash": "base-hash-2"],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let outlinePlan = AgentActionPlan(
            id: "outline-audit",
            kind: .generateResearchOutline,
            status: .pendingApproval,
            title: "outline-audit",
            summary: "Generate outline",
            requestedPermissions: [.providerCall],
            steps: [],
            payloadHash: "payload-outline-audit",
            payload: ["target_note": "Research Plan for revision-1"],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let zoteroPlan = makeZoteroImportActionPlan(
            id: "zotero-audit",
            zoteroItemId: 42,
            payload: [
                "zotero_key": "ZOT42",
                "arxiv_id": "2401.00001",
                "local_library_path": "/tmp/bilin-library"
            ]
        )

        let noteMetadata = try XCTUnwrap(AgentActionPlanAuditMetadata.resolve(notePlan))
        let stepMetadata = try XCTUnwrap(AgentActionPlanAuditMetadata.resolve(stepTargetPlan))
        let outlineMetadata = try XCTUnwrap(AgentActionPlanAuditMetadata.resolve(outlinePlan))
        let zoteroMetadata = try XCTUnwrap(AgentActionPlanAuditMetadata.resolve(zoteroPlan))

        XCTAssertEqual(
            noteMetadata.rows,
            [
                AgentActionPlanAuditMetadata.Row(label: "Target file", value: "/tmp/Vault/Papers/Paper.md", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Base hash", value: "base-hash-1", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Source block", value: "p-1", monospaced: true)
            ]
        )
        XCTAssertEqual(
            stepMetadata.rows,
            [
                AgentActionPlanAuditMetadata.Row(label: "Target file", value: "/tmp/paper/main.typ", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Base hash", value: "base-hash-2", monospaced: true)
            ]
        )
        XCTAssertEqual(
            outlineMetadata.rows,
            [
                AgentActionPlanAuditMetadata.Row(label: "Requested permissions", value: "Provider call"),
                AgentActionPlanAuditMetadata.Row(label: "Target note", value: "Research Plan for revision-1")
            ]
        )
        XCTAssertEqual(
            zoteroMetadata.rows,
            [
                AgentActionPlanAuditMetadata.Row(
                    label: "Requested permissions",
                    value: "Network, Download paper, Import library, Write library bundle"
                ),
                AgentActionPlanAuditMetadata.Row(label: "Zotero item", value: "42 · ZOT42", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "arXiv", value: "2401.00001", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Target library", value: "/tmp/bilin-library", monospaced: true)
            ]
        )
    }

    func testActionPlanAuditMetadataExposesRecoveryContext() throws {
        let recoveryPlan = makeActionPlan(
            id: "note-recovery",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            baseFileHash: "current-base",
            payload: [
                "recovering_from_action_plan_id": "failed-note",
                "recovery_patch_strategy": "rebase_on_current_target",
                "previous_base_file_hash": "previous-base",
                "observed_file_hash": "observed-after-conflict",
                "recovery_target_path": "/tmp/Vault/Papers/Paper.md",
                "recovered_at": "2026-06-07T00:00:00.000Z"
            ]
        )

        let metadata = try XCTUnwrap(AgentActionPlanAuditMetadata.resolve(recoveryPlan))

        XCTAssertEqual(
            metadata.rows,
            [
                AgentActionPlanAuditMetadata.Row(label: "Target file", value: "/tmp/Vault/Papers/Paper.md", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Base hash", value: "current-base", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Source block", value: "p-1", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Recovery from", value: "failed-note", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Recovery strategy", value: "Rebase on current target"),
                AgentActionPlanAuditMetadata.Row(label: "Previous base hash", value: "previous-base", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Observed file hash", value: "observed-after-conflict", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Recovery target", value: "/tmp/Vault/Papers/Paper.md", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Recovered at", value: "2026-06-07T00:00:00.000Z")
            ]
        )
    }

    func testActionPlanAuditMetadataExposesResearchOutlineInputs() throws {
        let plan = makeResearchPlanActionPlan(
            id: "outline-audit-inputs",
            articleRevisionId: "revision-1",
            payload: [
                "topic": "Research Paper",
                "skill_provenance": """
                {"digest":"sha256:paper-outline","skill_slug":"paper-outline","source":"project","version":"1.0.0"}
                """,
                "candidate_papers": """
                [
                  {"id":"paper-1","title":"First Candidate"},
                  {"id":"paper-2","metadata":{"title":"Second Candidate"}}
                ]
                """,
                "payload": """
                {
                  "selected_block_uid": "p-1",
                  "visible_blocks": [
                    {"block_uid":"p-1","block_type":"paragraph"},
                    {"block_uid":"eq-1","block_type":"equation"}
                  ]
                }
                """
            ]
        )

        let metadata = try XCTUnwrap(AgentActionPlanAuditMetadata.resolve(plan))

        XCTAssertEqual(
            metadata.rows,
            [
                AgentActionPlanAuditMetadata.Row(label: "Requested permissions", value: "Provider call"),
                AgentActionPlanAuditMetadata.Row(label: "Article revision", value: "revision-1", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Topic", value: "Research Paper"),
                AgentActionPlanAuditMetadata.Row(label: "Research skill", value: "paper-outline 1.0.0", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Skill source", value: "project", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Candidate papers", value: "2"),
                AgentActionPlanAuditMetadata.Row(label: "Candidate titles", value: "First Candidate\nSecond Candidate"),
                AgentActionPlanAuditMetadata.Row(label: "Reader blocks", value: "2"),
                AgentActionPlanAuditMetadata.Row(label: "Selected block", value: "p-1", monospaced: true)
            ]
        )
    }

    func testActionPlanAuditMetadataExposesNoteBridgeWriteContext() throws {
        let notePlan = makeActionPlan(
            id: "note-audit",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            baseFileHash: "current-note-hash",
            payload: [
                "article_revision_id": "revision-1",
                "block_anchor": "^ilios-revision-1-p-1",
                "target_note": "Papers/Paper.md",
                "target_vault_path": "/tmp/Vault",
                "source_markdown": "Selected theorem.",
                "translation_markdown": "选中的定理。",
                "selected_text_hash": "selected-hash",
                "callout_type": "note"
            ]
        )

        let metadata = try XCTUnwrap(AgentActionPlanAuditMetadata.resolve(notePlan))

        XCTAssertEqual(
            metadata.rows,
            [
                AgentActionPlanAuditMetadata.Row(label: "Target file", value: "/tmp/Vault/Papers/Paper.md", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Base hash", value: "current-note-hash", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Article revision", value: "revision-1", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Source block", value: "p-1", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Block anchor", value: "^ilios-revision-1-p-1", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Markdown note", value: "Papers/Paper.md", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Obsidian vault", value: "/tmp/Vault", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Source scope", value: "Selected excerpt"),
                AgentActionPlanAuditMetadata.Row(label: "Selection hash", value: "selected-hash", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Translation", value: "Included"),
                AgentActionPlanAuditMetadata.Row(label: "Callout", value: "note")
            ]
        )
    }

    func testActionPlanAuditMetadataExposesWritingPatchInsertionStrategy() throws {
        let writingPlan = makeActionPlan(
            id: "writing-audit",
            kind: .writingPatch,
            blockUid: "p-1",
            targetPath: "/tmp/paper/main.typ",
            baseFileHash: "current-main-hash",
            payload: [
                "article_revision_id": "revision-1",
                "source_markdown": "Selected related work claim.",
                "selected_text_hash": "selected-hash",
                "target_section_path": #"["Related Work","Learned Indexes"]"#,
                "target_anchor": "related-work",
                "insertion_mode": "section_end",
                "insertion_line": "42",
                "bibliography_paths": #"["refs/paper.bib","refs/appendix.bib"]"#
            ]
        )

        let metadata = try XCTUnwrap(AgentActionPlanAuditMetadata.resolve(writingPlan))

        XCTAssertEqual(
            metadata.rows,
            [
                AgentActionPlanAuditMetadata.Row(label: "Target file", value: "/tmp/paper/main.typ", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Base hash", value: "current-main-hash", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Article revision", value: "revision-1", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Source block", value: "p-1", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Source scope", value: "Selected excerpt"),
                AgentActionPlanAuditMetadata.Row(label: "Selection hash", value: "selected-hash", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Target section", value: "Related Work > Learned Indexes"),
                AgentActionPlanAuditMetadata.Row(label: "Target anchor", value: "related-work", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Insertion mode", value: "section_end"),
                AgentActionPlanAuditMetadata.Row(label: "Insertion line", value: "42", monospaced: true),
                AgentActionPlanAuditMetadata.Row(label: "Bibliography", value: "refs/paper.bib\nrefs/appendix.bib", monospaced: true)
            ]
        )
    }

    func testActionPlanResultMetadataExposesPatchAndZoteroBundleOutputs() throws {
        let patchPlan = makeActionPlan(
            id: "patch-result",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            result: [
                "target_path": "/tmp/Vault/Papers/Paper.md",
                "bytes": "512",
                "already_present": "false",
                "base_file_hash": "base-hash-1",
                "applied_file_hash": "applied-hash-1"
            ]
        )
        let zoteroPlan = makeZoteroImportActionPlan(
            id: "zotero-result",
            zoteroItemId: 42,
            status: .succeeded,
            result: [
                "bundle_path": "/tmp/library/imports/zotero/ZOT42",
                "metadata_path": "/tmp/library/imports/zotero/ZOT42/metadata.json",
                "bytes": "1200",
                "copied_attachment_count": "1",
                "missing_attachment_count": "0",
                "already_present": "false"
            ]
        )

        let patchMetadata = try XCTUnwrap(AgentActionPlanResultMetadata.resolve(patchPlan))
        let zoteroMetadata = try XCTUnwrap(AgentActionPlanResultMetadata.resolve(zoteroPlan))

        XCTAssertEqual(
            patchMetadata.rows,
            [
                AgentActionPlanResultMetadata.Row(label: "Applied file", value: "/tmp/Vault/Papers/Paper.md", monospaced: true),
                AgentActionPlanResultMetadata.Row(label: "Bytes", value: "512"),
                AgentActionPlanResultMetadata.Row(label: "Already present", value: "false"),
                AgentActionPlanResultMetadata.Row(label: "Base file hash", value: "base-hash-1", monospaced: true),
                AgentActionPlanResultMetadata.Row(label: "Applied file hash", value: "applied-hash-1", monospaced: true)
            ]
        )
        XCTAssertEqual(
            zoteroMetadata.rows,
            [
                AgentActionPlanResultMetadata.Row(label: "Import bundle", value: "/tmp/library/imports/zotero/ZOT42", monospaced: true),
                AgentActionPlanResultMetadata.Row(label: "Metadata file", value: "/tmp/library/imports/zotero/ZOT42/metadata.json", monospaced: true),
                AgentActionPlanResultMetadata.Row(label: "Bytes", value: "1200"),
                AgentActionPlanResultMetadata.Row(label: "Copied attachments", value: "1"),
                AgentActionPlanResultMetadata.Row(label: "Missing attachments", value: "0"),
                AgentActionPlanResultMetadata.Row(label: "Already present", value: "false")
            ]
        )
    }

    func testActionPlanResultFileActionsExposeMacFileTargetsOnlyAfterSuccess() {
        let appliedPatchPlan = makeActionPlan(
            id: "patch-result-actions",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            status: .succeeded,
            result: [
                "target_path": "/tmp/Vault/Papers/Paper.md"
            ]
        )
        let pendingPatchPlan = makeActionPlan(
            id: "pending-patch-result-actions",
            kind: .writeObsidian,
            blockUid: "p-1",
            targetPath: "/tmp/Vault/Papers/Paper.md",
            status: .pendingApproval,
            result: [
                "target_path": "/tmp/Vault/Papers/Paper.md"
            ]
        )
        let missingPathPlan = makeActionPlan(
            id: "missing-path-result-actions",
            kind: .writingPatch,
            blockUid: "p-1",
            targetPath: "/tmp/project/main.tex",
            status: .succeeded,
            result: [
                "target_path": "   "
            ]
        )
        let zoteroPlan = makeZoteroImportActionPlan(
            id: "zotero-result-actions",
            zoteroItemId: 42,
            status: .succeeded,
            result: [
                "bundle_path": "/tmp/library/imports/zotero/ZOT42"
            ]
        )

        XCTAssertEqual(
            AgentActionPlanResultFileActions.resolve(appliedPatchPlan),
            [
                AgentActionPlanResultFileAction(
                    kind: .openFile,
                    title: "Open File",
                    systemImage: "doc.text.magnifyingglass",
                    path: "/tmp/Vault/Papers/Paper.md"
                ),
                AgentActionPlanResultFileAction(
                    kind: .revealInFinder,
                    title: "Reveal in Finder",
                    systemImage: "folder",
                    path: "/tmp/Vault/Papers/Paper.md"
                )
            ]
        )
        XCTAssertEqual(
            AgentActionPlanResultFileActions.resolve(zoteroPlan),
            [
                AgentActionPlanResultFileAction(
                    kind: .revealInFinder,
                    title: "Reveal Bundle",
                    systemImage: "folder",
                    path: "/tmp/library/imports/zotero/ZOT42"
                )
            ]
        )
        XCTAssertTrue(AgentActionPlanResultFileActions.resolve(pendingPatchPlan).isEmpty)
        XCTAssertTrue(AgentActionPlanResultFileActions.resolve(missingPathPlan).isEmpty)
    }

    func testSnapshotKeyIncludesLibraryRecoveryState() {
        let session = ReaderWorkbenchSession()
        let firstKey = ResearchWorkbenchSnapshotKey(session: session)

        session.configuredBilinLibraryRecovery = ConfiguredBilinLibraryRecovery(
            name: "Papers",
            path: "/tmp/missing-library",
            message: "The configured library is missing."
        )
        let secondKey = ResearchWorkbenchSnapshotKey(session: session)

        XCTAssertNotEqual(firstKey, secondKey)
    }

    private func makeBlock(uid: String, structuralPath: String) -> DocumentBlock {
        DocumentBlock(
            id: "block-\(uid)",
            articleRevisionId: "revision-1",
            blockUid: uid,
            structuralPath: structuralPath,
            blockType: .paragraph,
            contentHash: "hash-\(uid)",
            sourceMarkdown: "Paragraph \(uid)",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeArticle(
        id: String = "article-1",
        revisionId: String = "revision-1"
    ) -> Article {
        Article(
            id: id,
            libraryId: "library-1",
            source: "arxiv",
            externalId: "2401.00001",
            title: "Research Paper",
            activeRevisionId: revisionId
        )
    }

    private func makePathRecord(
        kind: WorkspacePathKind,
        status: ExternalFileTargetStatus = .available,
        path: String? = nil
    ) -> WorkspacePathRecord {
        WorkspacePathRecord(
            id: "path-\(kind.rawValue)",
            name: kind.rawValue,
            path: path ?? "/tmp/\(kind.rawValue)",
            kind: kind,
            status: status,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeWritingProject(mainFilePath: String?) -> WritingProject {
        WritingProject(
            id: "writing-project",
            name: "Writing Project",
            rootPath: "/tmp/writing",
            kind: .typst,
            status: mainFilePath == nil ? .needsMainFile : .linked,
            mainFilePath: mainFilePath,
            bibliographyFilePaths: [],
            detectedFilePaths: mainFilePath.map { [$0] } ?? [],
            pendingPatches: [],
            sourceProvenance: [],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makePaperOutlineSkill(
        status: ResearchSkillStatus = .enabled,
        supportedTasks: [ResearchSkillTask] = [.paperReading]
    ) -> ResearchSkill {
        ResearchSkill(
            id: "skill-paper-outline",
            slug: "paper-outline",
            title: "Paper Outline",
            description: "Build per-paper mastery outlines.",
            digest: "sha256:paper-outline",
            source: ResearchSkillSource(kind: .project, identifier: "/tmp/paper-outline/SKILL.md"),
            status: status,
            permissions: [.providerCall],
            supportedTasks: supportedTasks,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeActionPlan(
        id: String,
        kind: AgentActionKind,
        blockUid: String,
        targetPath: String,
        baseFileHash: String? = nil,
        status: AgentActionStatus = .pendingApproval,
        payload extraPayload: [String: String] = [:],
        preview: [String: String]? = nil,
        result: [String: String]? = nil,
        error: [String: String]? = nil,
        errorMessage: String? = nil
    ) -> AgentActionPlan {
        var payload = [
            "block_uid": blockUid,
            "target_path": targetPath
        ]
        payload.merge(extraPayload) { _, new in new }
        if let baseFileHash {
            payload["base_file_hash"] = baseFileHash
        }

        return AgentActionPlan(
            id: id,
            kind: kind,
            status: status,
            title: id,
            summary: "Test action plan",
            requestedPermissions: [],
            steps: [],
            payloadHash: "payload-\(id)",
            payload: payload,
            preview: preview,
            result: result,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            error: error,
            errorMessage: errorMessage
        )
    }

    private func makeResearchPlanActionPlan(
        id: String,
        articleRevisionId: String,
        status: AgentActionStatus = .pendingApproval,
        payload extraPayload: [String: String] = [:],
        result: [String: String]? = nil
    ) -> AgentActionPlan {
        var payload = [
            "article_revision_id": articleRevisionId
        ]
        payload.merge(extraPayload) { _, new in new }

        return AgentActionPlan(
            id: id,
            kind: .generateResearchOutline,
            status: status,
            title: id,
            summary: "Generate a paper-specific reading outline.",
            requestedPermissions: [.providerCall],
            steps: [],
            payloadHash: "payload-\(id)",
            payload: payload,
            result: result,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeZoteroImportActionPlan(
        id: String,
        zoteroItemId: Int64,
        status: AgentActionStatus = .pendingApproval,
        payload extraPayload: [String: String] = [:],
        preview: [String: String]? = nil,
        result: [String: String]? = nil,
        error: [String: String]? = nil,
        errorMessage: String? = nil
    ) -> AgentActionPlan {
        var payload = [
            "source": "zotero",
            "zotero_item_id": String(zoteroItemId),
            "zotero_key": "ZOT\(zoteroItemId)"
        ]
        payload.merge(extraPayload) { _, new in new }

        return AgentActionPlan(
            id: id,
            kind: .downloadPaper,
            status: status,
            title: id,
            summary: "Prepare Zotero import.",
            requestedPermissions: [.network, .downloadPaper, .importLibrary, .writeLibraryBundle],
            steps: [],
            payloadHash: "payload-\(id)",
            payload: payload,
            preview: preview,
            result: result,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            error: error,
            errorMessage: errorMessage
        )
    }

    private func makeResearchPlan(
        id: String,
        articleRevisionId: String,
        status: ResearchPlanStatus,
        outline: ReadingOutline
    ) -> ResearchPlan {
        ResearchPlan(
            id: id,
            kind: .paperReading,
            status: status,
            title: outline.title,
            articleRevisionId: articleRevisionId,
            payloadHash: "payload-\(id)",
            readingOutline: outline,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeWorkspaceDefaults(
        selectedObsidianVault: WorkspacePathRecord,
        writingProjectRoot: WorkspacePathRecord,
        mainFilePath: String
    ) -> WorkspaceDefaultsModel {
        let defaults = WorkspaceDefaultsModel(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        defaults.workspaceConfiguration = WorkspaceConfiguration(
            selectedObsidianVault: selectedObsidianVault,
            writingProjectRoots: [writingProjectRoot]
        )
        defaults.writingProjectLocation = WritingProjectLocation(
            rootPath: writingProjectRoot.path,
            kind: .typst,
            status: .linked,
            mainFilePath: mainFilePath,
            bibliographyFilePaths: [],
            detectedFilePaths: [mainFilePath]
        )
        return defaults
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
            .appendingPathComponent("bilin-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
