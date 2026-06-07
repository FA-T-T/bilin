import XCTest
@testable import BilinWorkspaceKit

final class ResearchActionPlanCoordinatorTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testApproveResolvesLibraryAndSendsPayloadHash() async throws {
        let client = FakeResearchActionPlanClient()
        let patchApplier = RecordingPatchApplier()
        let coordinator = ResearchActionPlanCoordinator(
            client: client,
            patchApplier: patchApplier
        )
        let actionPlan = makeActionPlan(status: .pendingApproval, payloadHash: "payload-123")
        client.approveResponse = makeActionPlan(status: .approved)

        let updated = try await coordinator.approve(
            libraryIdentifier: "local-library",
            libraryPath: "/tmp/library",
            actionPlan: actionPlan
        )

        XCTAssertEqual(updated.status, .approved)
        XCTAssertEqual(client.events, ["resolve", "approve"])
        XCTAssertEqual(client.receivedLibraryIdentifier, "local-library")
        XCTAssertEqual(client.receivedLibraryPath, "/tmp/library")
        XCTAssertEqual(client.receivedExpectedPayloadHash, "payload-123")
        XCTAssertEqual(client.receivedTransitionPayload["approved_by"], "macos")
    }

    func testRejectResolvesLibraryAndSendsMacOSPayload() async throws {
        let client = FakeResearchActionPlanClient()
        let coordinator = ResearchActionPlanCoordinator(
            client: client,
            patchApplier: RecordingPatchApplier()
        )
        client.rejectResponse = makeActionPlan(status: .rejected)

        let updated = try await coordinator.reject(
            libraryIdentifier: "local-library",
            libraryPath: nil,
            actionPlan: makeActionPlan(status: .pendingApproval)
        )

        XCTAssertEqual(updated.status, .rejected)
        XCTAssertEqual(client.events, ["resolve", "reject"])
        XCTAssertEqual(client.receivedTransitionPayload["rejected_by"], "macos")
    }

    func testApplyStartsRunsLocalPatchAndMarksSucceeded() async throws {
        let client = FakeResearchActionPlanClient()
        let patchApplier = RecordingPatchApplier(
            result: .success(
                LocalFilePatchResult(
                    targetPath: "/tmp/Paper/main.typ",
                    bytes: 32,
                    alreadyPresent: false,
                    baseFileHash: "base",
                    appliedFileHash: "applied"
                )
            )
        )
        let coordinator = ResearchActionPlanCoordinator(
            client: client,
            patchApplier: patchApplier
        )
        client.startResponse = makeActionPlan(status: .running)
        client.succeedResponse = makeActionPlan(status: .succeeded)

        let outcome = try await coordinator.apply(
            libraryIdentifier: "local-library",
            libraryPath: "/tmp/library",
            actionPlan: makeActionPlan(status: .approved),
            configuration: WorkspaceConfiguration()
        )

        guard case .succeeded(_, let running, let succeeded, let localResult) = outcome else {
            return XCTFail("Expected succeeded outcome")
        }
        XCTAssertEqual(running.status, .running)
        XCTAssertEqual(succeeded.status, .succeeded)
        XCTAssertEqual(localResult.appliedFileHash, "applied")
        XCTAssertEqual(outcome.actionPlanUpdates.map(\.status), [.running, .succeeded])
        XCTAssertEqual(client.events, ["resolve", "start", "succeed"])
        XCTAssertEqual(client.receivedStartPayload["executor"], "macos")
        XCTAssertEqual(client.receivedSucceedResult["applied_file_hash"], "applied")
        XCTAssertEqual(patchApplier.appliedActionPlan?.status, .running)
    }

    func testNoteBridgePlanApprovesAndWritesObsidianMarkdownThroughLocalCoordinator() async throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
        let emptyHash = LocalFilePatchExecutor.contentHash(for: "")
        let build = NoteActionPlanBuilder().build(
            articleTitle: "Seed Paper",
            articleRevisionId: "rev-note",
            blockUid: "block-note",
            sourceMarkdown: "A source claim.",
            translationMarkdown: "A translated claim.",
            vaultPath: vaultURL.path,
            baseFileHash: emptyHash
        )
        let targetPath = try XCTUnwrap(build.targetPath)
        let pending = makeActionPlan(
            from: build.actionPlanDraft,
            id: "note-action-1",
            status: .pendingApproval
        )
        let approvedResponse = makeActionPlan(
            from: build.actionPlanDraft,
            id: "note-action-1",
            status: .approved
        )
        let runningResponse = makeActionPlan(
            from: build.actionPlanDraft,
            id: "note-action-1",
            status: .running
        )
        let succeededResponse = makeActionPlan(
            from: build.actionPlanDraft,
            id: "note-action-1",
            status: .succeeded
        )
        let client = FakeResearchActionPlanClient()
        client.approveResponse = approvedResponse
        client.startResponse = runningResponse
        client.succeedResponse = succeededResponse
        let coordinator = ResearchActionPlanCoordinator(
            client: client,
            patchApplier: LocalFilePatchExecutor()
        )
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault
            )
        )

        let approved = try await coordinator.approve(
            libraryIdentifier: "local-library",
            libraryPath: "/tmp/library",
            actionPlan: pending
        )
        let outcome = try await coordinator.apply(
            libraryIdentifier: "local-library",
            libraryPath: "/tmp/library",
            actionPlan: approved,
            configuration: configuration
        )

        guard case .succeeded(_, let running, let succeeded, let localResult) = outcome else {
            return XCTFail("Expected succeeded outcome")
        }
        let written = try String(contentsOfFile: targetPath, encoding: .utf8)
        XCTAssertEqual(client.events, ["resolve", "approve", "resolve", "start", "succeed"])
        XCTAssertEqual(client.receivedExpectedPayloadHash, pending.payloadHash)
        XCTAssertEqual(running.status, .running)
        XCTAssertEqual(succeeded.status, .succeeded)
        XCTAssertEqual(localResult.targetPath, targetPath)
        XCTAssertEqual(localResult.baseFileHash, emptyHash)
        XCTAssertEqual(client.receivedSucceedResult["target_path"], targetPath)
        XCTAssertEqual(client.receivedSucceedResult["applied_file_hash"], localResult.appliedFileHash)
        XCTAssertTrue(written.contains("<!-- ilios-action-plan:note-action-1 -->"))
        XCTAssertTrue(written.contains("> [!note] Source block ^ilios-rev-note-block-note"))
        XCTAssertTrue(written.contains("> A source claim."))
        XCTAssertTrue(written.contains("> A translated claim."))
    }

    func testNoteBridgePlanReportsConflictWhenObsidianFileChangesAfterPreview() async throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
        let targetURL = vaultURL.appendingPathComponent("Papers/Seed Paper.md")
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let originalText = "# Seed Paper\n"
        try originalText.write(to: targetURL, atomically: true, encoding: .utf8)
        let originalHash = LocalFilePatchExecutor.contentHash(for: originalText)
        let changedText = "# Seed Paper\n\nExternal edit.\n"
        try changedText.write(to: targetURL, atomically: true, encoding: .utf8)
        let changedHash = LocalFilePatchExecutor.contentHash(for: changedText)
        let build = NoteActionPlanBuilder().build(
            articleTitle: "Seed Paper",
            articleRevisionId: "rev-note",
            blockUid: "block-note",
            sourceMarkdown: "A source claim.",
            vaultPath: vaultURL.path,
            baseFileHash: originalHash
        )
        let approved = makeActionPlan(
            from: build.actionPlanDraft,
            id: "note-action-2",
            status: .approved
        )
        let runningResponse = makeActionPlan(
            from: build.actionPlanDraft,
            id: "note-action-2",
            status: .running
        )
        let failedResponse = makeActionPlan(
            from: build.actionPlanDraft,
            id: "note-action-2",
            status: .failed,
            errorMessage: "Target file changed since preview."
        )
        let client = FakeResearchActionPlanClient()
        client.startResponse = runningResponse
        client.failResponse = failedResponse
        let coordinator = ResearchActionPlanCoordinator(
            client: client,
            patchApplier: LocalFilePatchExecutor()
        )
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: makeRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault
            )
        )

        let outcome = try await coordinator.apply(
            libraryIdentifier: "local-library",
            libraryPath: "/tmp/library",
            actionPlan: approved,
            configuration: configuration
        )

        guard case .failed(_, let running, let failed, let errorMessage) = outcome else {
            return XCTFail("Expected failed outcome")
        }
        let written = try String(contentsOf: targetURL, encoding: .utf8)
        XCTAssertEqual(client.events, ["resolve", "start", "fail"])
        XCTAssertEqual(running?.status, .running)
        XCTAssertEqual(failed?.status, .failed)
        XCTAssertTrue(errorMessage.contains("Target file changed since preview"))
        XCTAssertEqual(client.receivedFailureError["code"], "file_changed_since_preview")
        XCTAssertEqual(client.receivedFailureError["expected_base_file_hash"], originalHash)
        XCTAssertEqual(client.receivedFailureError["observed_file_hash"], changedHash)
        XCTAssertEqual(client.receivedFailureError["target_path"], targetURL.path)
        XCTAssertEqual(client.receivedFailureError["target_note"], "Papers/Seed Paper.md")
        XCTAssertEqual(written, changedText)
        XCTAssertFalse(written.contains("A source claim."))
    }

    func testApplyLocalFailureMarksRemotePlanFailedAndReturnsRecoverableOutcome() async throws {
        let client = FakeResearchActionPlanClient()
        let patchApplier = RecordingPatchApplier(
            result: .failure(
                LocalFilePatchExecutionError.fileChangedSincePreview(
                    expected: "old",
                    observed: "new"
                )
            )
        )
        let coordinator = ResearchActionPlanCoordinator(
            client: client,
            patchApplier: patchApplier
        )
        client.startResponse = makeActionPlan(status: .running)
        client.failResponse = makeActionPlan(
            status: .failed,
            errorMessage: "Target file changed since preview."
        )

        let outcome = try await coordinator.apply(
            libraryIdentifier: "local-library",
            libraryPath: "/tmp/library",
            actionPlan: makeActionPlan(status: .approved),
            configuration: WorkspaceConfiguration()
        )

        guard case .failed(_, let running, let failed, let errorMessage) = outcome else {
            return XCTFail("Expected failed outcome")
        }
        XCTAssertEqual(running?.status, .running)
        XCTAssertEqual(failed?.status, .failed)
        XCTAssertTrue(errorMessage.contains("Target file changed since preview"))
        XCTAssertEqual(outcome.actionPlanUpdates.map(\.status), [.running, .failed])
        XCTAssertEqual(client.events, ["resolve", "start", "fail"])
        XCTAssertEqual(client.receivedFailureError["code"], "file_changed_since_preview")
        XCTAssertEqual(client.receivedFailureError["expected_base_file_hash"], "old")
        XCTAssertEqual(client.receivedFailureError["observed_file_hash"], "new")
        XCTAssertEqual(client.receivedFailureError["target_note"], "Papers/Seed.md")
        XCTAssertTrue(client.receivedFailureError["message"]?.contains("Target file changed since preview") ?? false)
    }

    func testApplyStartFailureDoesNotCallRemoteFailWithoutRunningPlan() async throws {
        let client = FakeResearchActionPlanClient()
        client.startError = FakeActionPlanError.startFailed
        let coordinator = ResearchActionPlanCoordinator(
            client: client,
            patchApplier: RecordingPatchApplier()
        )

        let outcome = try await coordinator.apply(
            libraryIdentifier: "local-library",
            libraryPath: "/tmp/library",
            actionPlan: makeActionPlan(status: .approved),
            configuration: WorkspaceConfiguration()
        )

        guard case .failed(_, let running, let failed, let errorMessage) = outcome else {
            return XCTFail("Expected failed outcome")
        }
        XCTAssertNil(running)
        XCTAssertNil(failed)
        XCTAssertEqual(errorMessage, "Remote start failed.")
        XCTAssertEqual(outcome.actionPlanUpdates, [])
        XCTAssertEqual(client.events, ["resolve", "start"])
    }

    func testApplyRemoteFailErrorPreservesOriginalLocalError() async throws {
        let client = FakeResearchActionPlanClient()
        let patchApplier = RecordingPatchApplier(
            result: .failure(LocalFilePatchExecutionError.missingPatchText)
        )
        let coordinator = ResearchActionPlanCoordinator(
            client: client,
            patchApplier: patchApplier
        )
        client.startResponse = makeActionPlan(status: .running)
        client.failError = FakeActionPlanError.failFailed

        let outcome = try await coordinator.apply(
            libraryIdentifier: "local-library",
            libraryPath: "/tmp/library",
            actionPlan: makeActionPlan(status: .approved),
            configuration: WorkspaceConfiguration()
        )

        guard case .failed(_, let running, let failed, let errorMessage) = outcome else {
            return XCTFail("Expected failed outcome")
        }
        XCTAssertEqual(running?.status, .running)
        XCTAssertNil(failed)
        XCTAssertEqual(errorMessage, "Action plan does not include patch text.")
        XCTAssertEqual(outcome.actionPlanUpdates.map(\.status), [.running])
        XCTAssertEqual(client.events, ["resolve", "start", "fail"])
    }

    func testApplyRequiresApprovalBeforeCallingRemoteClient() async {
        let client = FakeResearchActionPlanClient()
        let coordinator = ResearchActionPlanCoordinator(
            client: client,
            patchApplier: RecordingPatchApplier()
        )

        do {
            _ = try await coordinator.apply(
                libraryIdentifier: "local-library",
                libraryPath: "/tmp/library",
                actionPlan: makeActionPlan(status: .pendingApproval),
                configuration: WorkspaceConfiguration()
            )
            XCTFail("Expected approvalRequired")
        } catch ResearchActionPlanCoordinatorError.approvalRequired {
            XCTAssertTrue(client.events.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeActionPlan(
        status: AgentActionStatus,
        payloadHash: String = "payload-hash",
        errorMessage: String? = nil
    ) -> AgentActionPlan {
        AgentActionPlan(
            id: "action-1",
            kind: .writeObsidian,
            status: status,
            title: "Write note",
            summary: "Write a note patch.",
            requestedPermissions: [.writeObsidian],
            steps: [],
            payloadHash: payloadHash,
            payload: ["target_note": "Papers/Seed.md"],
            preview: ["patch": "> Patch"],
            createdAt: baseDate,
            updatedAt: baseDate,
            errorMessage: errorMessage
        )
    }

    private func makeActionPlan(
        from draft: AgentActionPlanDraft,
        id: String,
        status: AgentActionStatus,
        errorMessage: String? = nil
    ) -> AgentActionPlan {
        AgentActionPlan(
            id: id,
            kind: draft.kind,
            status: status,
            title: draft.title,
            summary: draft.description,
            requestedPermissions: draft.requiredPermissions,
            steps: [],
            payloadHash: "payload-\(id)",
            payload: draft.payload,
            preview: draft.preview,
            idempotencyKey: draft.idempotencyKey,
            createdAt: baseDate,
            updatedAt: baseDate,
            errorMessage: errorMessage
        )
    }

    private func makeTemporaryDirectory(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResearchActionPlanCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
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
}

private final class FakeResearchActionPlanClient: ResearchActionPlanRemoteClient, @unchecked Sendable {
    var events: [String] = []
    var receivedLibraryIdentifier: String?
    var receivedLibraryPath: String?
    var receivedExpectedPayloadHash: String?
    var receivedTransitionPayload: [String: String] = [:]
    var receivedStartPayload: [String: String] = [:]
    var receivedSucceedResult: [String: String] = [:]
    var receivedFailureError: [String: String] = [:]

    var approveResponse: AgentActionPlan?
    var rejectResponse: AgentActionPlan?
    var startResponse: AgentActionPlan?
    var succeedResponse: AgentActionPlan?
    var failResponse: AgentActionPlan?
    var startError: Error?
    var failError: Error?

    func resolveLibraryId(identifier: String, path: String?) async throws -> String {
        events.append("resolve")
        receivedLibraryIdentifier = identifier
        receivedLibraryPath = path
        return "backend-library"
    }

    func approveAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        expectedPayloadHash: String?,
        payload: [String: String]
    ) async throws -> AgentActionPlan {
        events.append("approve")
        receivedExpectedPayloadHash = expectedPayloadHash
        receivedTransitionPayload = payload
        return approveResponse ?? fallbackActionPlan(status: .approved)
    }

    func rejectAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        payload: [String: String]
    ) async throws -> AgentActionPlan {
        events.append("reject")
        receivedTransitionPayload = payload
        return rejectResponse ?? fallbackActionPlan(status: .rejected)
    }

    func startAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        payload: [String: String]
    ) async throws -> AgentActionPlan {
        events.append("start")
        if let startError {
            throw startError
        }
        receivedStartPayload = payload
        return startResponse ?? fallbackActionPlan(status: .running)
    }

    func succeedAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        result: [String: String]
    ) async throws -> AgentActionPlan {
        events.append("succeed")
        receivedSucceedResult = result
        return succeedResponse ?? fallbackActionPlan(status: .succeeded)
    }

    func failAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        error: [String: String]
    ) async throws -> AgentActionPlan {
        events.append("fail")
        if let failError {
            throw failError
        }
        receivedFailureError = error
        return failResponse ?? fallbackActionPlan(status: .failed)
    }

    private func fallbackActionPlan(status: AgentActionStatus) -> AgentActionPlan {
        AgentActionPlan(
            id: "action-1",
            kind: .writeObsidian,
            status: status,
            title: "Write note",
            summary: "Write a note patch.",
            requestedPermissions: [.writeObsidian],
            payloadHash: "payload-hash",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private enum FakeActionPlanError: Error, LocalizedError {
    case startFailed
    case failFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:
            return "Remote start failed."
        case .failFailed:
            return "Remote fail failed."
        }
    }
}

private final class RecordingPatchApplier: LocalActionPlanPatchApplying, @unchecked Sendable {
    var result: Result<LocalFilePatchResult, Error>
    var appliedActionPlan: AgentActionPlan?

    init(
        result: Result<LocalFilePatchResult, Error> = .success(
            LocalFilePatchResult(
                targetPath: "/tmp/Papers/Seed.md",
                bytes: 8,
                alreadyPresent: false
            )
        )
    ) {
        self.result = result
    }

    func apply(
        actionPlan: AgentActionPlan,
        configuration: WorkspaceConfiguration
    ) throws -> LocalFilePatchResult {
        appliedActionPlan = actionPlan
        return try result.get()
    }
}
