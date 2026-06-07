import XCTest
@testable import BilinWorkspaceKit

final class LocalFilePatchExecutorTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testAppliesApprovedObsidianPatchInsideConfiguredVault() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
        let targetURL = vaultURL.appendingPathComponent("Papers/Seed.md")
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault
            )
        )
        let actionPlan = makeActionPlan(
            kind: .writeObsidian,
            payload: ["target_note": "Papers/Seed.md"],
            preview: ["patch": "> [!note]\n> Claim"]
        )

        let result = try LocalFilePatchExecutor().apply(
            actionPlan: actionPlan,
            configuration: configuration
        )

        XCTAssertEqual(result.targetPath, targetURL.path)
        XCTAssertFalse(result.alreadyPresent)
        let written = try String(contentsOf: targetURL, encoding: .utf8)
        XCTAssertEqual(result.baseFileHash, LocalFilePatchExecutor.contentHash(for: ""))
        XCTAssertEqual(result.appliedFileHash, LocalFilePatchExecutor.contentHash(for: written))
        XCTAssertEqual(result.actionResultPayload["applied_file_hash"], result.appliedFileHash)
        XCTAssertTrue(written.contains("<!-- ilios-action-plan:action-1 -->"))
        XCTAssertTrue(written.contains("> Claim"))
    }

    func testAppliesRunningPlanAfterBackendStart() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault
            )
        )
        let actionPlan = makeActionPlan(
            status: .running,
            kind: .writeObsidian,
            payload: ["target_note": "Papers/Seed.md"],
            preview: ["patch": "Patch after backend start"]
        )

        let result = try LocalFilePatchExecutor().apply(
            actionPlan: actionPlan,
            configuration: configuration
        )

        let written = try String(contentsOfFile: result.targetPath, encoding: .utf8)
        XCTAssertTrue(written.contains("Patch after backend start"))
    }

    func testAppliesWritingActionPlanBuilderPatchInsideWritingProject() throws {
        let rootURL = try makeTemporaryDirectory()
        let projectURL = rootURL.appendingPathComponent("Paper", isDirectory: true)
        let mainURL = projectURL.appendingPathComponent("main.typ")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let originalText = """
        = Introduction
        Intro.

        = Related Work
        Prior art.

        = Method
        Method body.
        """
        try originalText.write(to: mainURL, atomically: true, encoding: .utf8)
        let baseHash = LocalFilePatchExecutor.contentHash(for: originalText)
        let draft = WritingActionPlanBuilder().build(
            mainFileText: originalText,
            targetPath: mainURL.path,
            sourceBlock: "Inserted related-work note.",
            articleRevisionId: "rev-writing",
            blockUid: "block-writing",
            baseFileHash: baseHash,
            targetSectionPreference: "Related Work",
            patchId: "writing-patch"
        ).actionPlanDraft
        let actionPlan = AgentActionPlan(
            id: "writing-action-1",
            kind: draft.kind,
            status: .approved,
            title: draft.title,
            summary: draft.description,
            requestedPermissions: draft.requiredPermissions,
            steps: [],
            payloadHash: "payload-hash",
            payload: draft.payload,
            preview: draft.preview,
            idempotencyKey: draft.idempotencyKey,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        let configuration = WorkspaceConfiguration(
            writingProjectRoots: [
                makeRecord(
                    id: "writing-root",
                    name: "Paper",
                    path: projectURL.path,
                    kind: .writingProjectRoot
                )
            ]
        )

        let result = try LocalFilePatchExecutor().apply(
            actionPlan: actionPlan,
            configuration: configuration
        )

        XCTAssertEqual(result.targetPath, mainURL.path)
        XCTAssertEqual(result.baseFileHash, baseHash)
        let written = try String(contentsOf: mainURL, encoding: .utf8)
        XCTAssertTrue(written.contains("// ilios-action-plan:writing-action-1"))
        XCTAssertTrue(written.contains("Inserted related-work note."))
        let priorRange = try XCTUnwrap(written.range(of: "Prior art."))
        let markerRange = try XCTUnwrap(written.range(of: "// ilios-action-plan:writing-action-1"))
        let methodRange = try XCTUnwrap(written.range(of: "= Method"))
        XCTAssertLessThan(priorRange.lowerBound, markerRange.lowerBound)
        XCTAssertLessThan(markerRange.lowerBound, methodRange.lowerBound)
        XCTAssertEqual(result.appliedFileHash, LocalFilePatchExecutor.contentHash(for: written))
    }

    func testWritingPatchFallsBackToAppendWhenSectionAnchorIsMissing() throws {
        let rootURL = try makeTemporaryDirectory()
        let projectURL = rootURL.appendingPathComponent("Paper", isDirectory: true)
        let mainURL = projectURL.appendingPathComponent("main.typ")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let originalText = """
        = Introduction
        Intro.

        = Method
        Method body.
        """
        try originalText.write(to: mainURL, atomically: true, encoding: .utf8)
        let baseHash = LocalFilePatchExecutor.contentHash(for: originalText)
        let draft = WritingActionPlanBuilder().build(
            mainFileText: originalText,
            targetPath: mainURL.path,
            sourceBlock: "Append fallback note.",
            articleRevisionId: "rev-writing",
            blockUid: "block-writing-fallback",
            baseFileHash: baseHash,
            targetSectionPreference: "Related Work",
            patchId: "writing-patch-fallback"
        ).actionPlanDraft
        let actionPlan = AgentActionPlan(
            id: "writing-action-fallback",
            kind: draft.kind,
            status: .approved,
            title: draft.title,
            summary: draft.description,
            requestedPermissions: draft.requiredPermissions,
            steps: [],
            payloadHash: "payload-hash-fallback",
            payload: draft.payload,
            preview: draft.preview,
            idempotencyKey: draft.idempotencyKey,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        let configuration = WorkspaceConfiguration(
            writingProjectRoots: [
                makeRecord(
                    id: "writing-root",
                    name: "Paper",
                    path: projectURL.path,
                    kind: .writingProjectRoot
                )
            ]
        )

        _ = try LocalFilePatchExecutor().apply(
            actionPlan: actionPlan,
            configuration: configuration
        )

        let written = try String(contentsOf: mainURL, encoding: .utf8)
        let methodRange = try XCTUnwrap(written.range(of: "Method body."))
        let markerRange = try XCTUnwrap(written.range(of: "// ilios-action-plan:writing-action-fallback"))
        XCTAssertLessThan(methodRange.lowerBound, markerRange.lowerBound)
    }

    func testRepeatedApplyIsIdempotentForSameActionPlanMarker() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault
            )
        )
        let actionPlan = makeActionPlan(
            kind: .writeObsidian,
            payload: ["target_note": "Papers/Seed.md"],
            preview: ["patch": "Patch once"]
        )

        let first = try LocalFilePatchExecutor().apply(
            actionPlan: actionPlan,
            configuration: configuration
        )
        let second = try LocalFilePatchExecutor().apply(
            actionPlan: actionPlan,
            configuration: configuration
        )

        let written = try String(contentsOfFile: first.targetPath, encoding: .utf8)
        XCTAssertFalse(first.alreadyPresent)
        XCTAssertTrue(second.alreadyPresent)
        XCTAssertEqual(written.components(separatedBy: "Patch once").count - 1, 1)
    }

    func testObsidianPatchIsIdempotentWhenBlockAnchorAlreadyExistsWithDifferentActionMarker() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
        let targetURL = vaultURL.appendingPathComponent("Papers/Seed.md")
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingText = """
        # Seed

        > [!note] Source block ^ilios-rev-1-block-7
        > Existing claim.
        """
        try existingText.write(to: targetURL, atomically: true, encoding: .utf8)
        let staleHash = LocalFilePatchExecutor.contentHash(for: "")
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault
            )
        )
        let actionPlan = makeActionPlan(
            id: "action-2",
            kind: .writeObsidian,
            payload: [
                "target_note": "Papers/Seed.md",
                "block_anchor": "^ilios-rev-1-block-7",
                "base_file_hash": staleHash
            ],
            preview: [
                "patch": "> [!note] Source block ^ilios-rev-1-block-7\n> Duplicate claim."
            ]
        )

        let result = try LocalFilePatchExecutor().apply(
            actionPlan: actionPlan,
            configuration: configuration
        )

        let written = try String(contentsOf: targetURL, encoding: .utf8)
        XCTAssertTrue(result.alreadyPresent)
        XCTAssertEqual(written, existingText)
        XCTAssertFalse(written.contains("Duplicate claim."))
        XCTAssertFalse(written.contains("<!-- ilios-action-plan:action-2 -->"))
    }

    func testRejectsUnapprovedOrOutOfRootPatch() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
        let outsideURL = rootURL.appendingPathComponent("Outside/Seed.md")
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault
            )
        )
        let unapproved = makeActionPlan(
            status: .pendingApproval,
            kind: .writeObsidian,
            payload: ["target_note": "Papers/Seed.md"],
            preview: ["patch": "Patch"]
        )
        let outside = makeActionPlan(
            kind: .writeObsidian,
            payload: ["target_path": outsideURL.path],
            preview: ["patch": "Patch"]
        )

        XCTAssertThrowsError(
            try LocalFilePatchExecutor().apply(actionPlan: unapproved, configuration: configuration)
        )
        XCTAssertThrowsError(
            try LocalFilePatchExecutor().apply(actionPlan: outside, configuration: configuration)
        )
    }

    func testRejectsMissingPatchTextUnsupportedKindAndDirectoryTarget() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
        let projectURL = rootURL.appendingPathComponent("Paper", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault
            ),
            writingProjectRoots: [
                makeRecord(
                    id: "writing-root",
                    name: "Paper",
                    path: projectURL.path,
                    kind: .writingProjectRoot
                )
            ]
        )

        let missingPatch = makeActionPlan(
            kind: .writeObsidian,
            payload: ["target_note": "Papers/Seed.md"],
            preview: [:]
        )
        XCTAssertThrowsError(
            try LocalFilePatchExecutor().apply(actionPlan: missingPatch, configuration: configuration)
        ) { error in
            guard case LocalFilePatchExecutionError.missingPatchText = error else {
                return XCTFail("Expected missingPatchText, got \(error)")
            }
        }

        let unsupported = makeActionPlan(
            kind: .downloadPaper,
            payload: ["target_path": projectURL.appendingPathComponent("paper.pdf").path],
            preview: ["patch": "Patch"]
        )
        XCTAssertThrowsError(
            try LocalFilePatchExecutor().apply(actionPlan: unsupported, configuration: configuration)
        ) { error in
            guard case LocalFilePatchExecutionError.unsupportedActionKind("downloadPaper") = error else {
                return XCTFail("Expected unsupportedActionKind, got \(error)")
            }
        }

        let directoryTarget = makeActionPlan(
            kind: .editManuscript,
            payload: ["target_path": projectURL.path],
            preview: ["patch": "#block[Patch]"]
        )
        XCTAssertThrowsError(
            try LocalFilePatchExecutor().apply(actionPlan: directoryTarget, configuration: configuration)
        ) { error in
            guard case LocalFilePatchExecutionError.targetIsDirectory(let path) = error else {
                return XCTFail("Expected targetIsDirectory, got \(error)")
            }
            XCTAssertEqual(path, projectURL.path)
        }
    }

    func testRejectsPatchWhenTargetChangedSincePreview() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
        let targetURL = vaultURL.appendingPathComponent("Papers/Seed.md")
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "original text".write(to: targetURL, atomically: true, encoding: .utf8)
        let originalHash = LocalFilePatchExecutor.contentHash(for: "original text")
        let changedHash = LocalFilePatchExecutor.contentHash(for: "changed text")
        try "changed text".write(to: targetURL, atomically: true, encoding: .utf8)
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault
            )
        )
        let actionPlan = makeActionPlan(
            kind: .writeObsidian,
            payload: [
                "target_note": "Papers/Seed.md",
                "base_file_hash": originalHash
            ],
            preview: ["patch": "Patch from stale preview"]
        )

        XCTAssertThrowsError(
            try LocalFilePatchExecutor().apply(actionPlan: actionPlan, configuration: configuration)
        ) { error in
            guard case LocalFilePatchExecutionError.fileChangedSincePreview(
                let expected,
                let observed
            ) = error else {
                return XCTFail("Expected fileChangedSincePreview, got \(error)")
            }
            XCTAssertEqual(expected, originalHash)
            XCTAssertEqual(observed, changedHash)
        }
        let written = try String(contentsOf: targetURL, encoding: .utf8)
        XCTAssertFalse(written.contains("Patch from stale preview"))
    }

    private func makeTemporaryDirectory(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalFilePatchExecutorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return rootURL
    }

    private func makeRecord(
        id: String,
        name: String,
        path: String,
        kind: WorkspacePathKind
    ) -> WorkspacePathRecord {
        WorkspacePathRecord(
            id: id,
            name: name,
            path: path,
            kind: kind,
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }

    private func makeActionPlan(
        id: String = "action-1",
        status: AgentActionStatus = .approved,
        kind: AgentActionKind,
        payload: [String: String],
        preview: [String: String]
    ) -> AgentActionPlan {
        AgentActionPlan(
            id: id,
            kind: kind,
            status: status,
            title: "Apply patch",
            summary: "Apply a local file patch.",
            requestedPermissions: [.writeObsidian],
            steps: [],
            payloadHash: "sha256-payload",
            payload: payload,
            preview: preview,
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }
}
