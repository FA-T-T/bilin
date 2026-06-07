import XCTest
@testable import BilinWorkspaceKit

final class ActionPlanRecoveryContextBuilderTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testBuildsRecoveryContextFromObsidianTargetNoteAndCurrentFileHash() throws {
        let rootURL = try makeTemporaryDirectory()
        let vaultURL = rootURL.appendingPathComponent("Vault", isDirectory: true)
        let noteURL = vaultURL.appendingPathComponent("Papers/Seed.md")
        try FileManager.default.createDirectory(
            at: noteURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "changed note".write(to: noteURL, atomically: true, encoding: .utf8)
        let actionPlan = makeActionPlan(
            payload: [
                "target_note": "Papers/Seed.md",
                "base_file_hash": "old-hash"
            ],
            errorMessage: "Target file changed since preview."
        )
        let configuration = WorkspaceConfiguration(
            selectedObsidianVault: WorkspacePathRecord(
                id: "vault",
                name: "Vault",
                path: vaultURL.path,
                kind: .obsidianVault,
                createdAt: baseDate,
                updatedAt: baseDate
            )
        )

        let context = ActionPlanRecoveryContextBuilder().build(
            from: actionPlan,
            configuration: configuration,
            recoveredAt: baseDate
        )

        XCTAssertEqual(context.recoveringFromActionPlanId, "failed-action")
        XCTAssertEqual(context.targetPath, noteURL.path)
        XCTAssertEqual(context.targetNote, "Papers/Seed.md")
        XCTAssertEqual(context.previousBaseFileHash, "old-hash")
        XCTAssertEqual(context.observedFileHash, LocalFilePatchExecutor.contentHash(for: "changed note"))
        XCTAssertEqual(context.errorMessage, "Target file changed since preview.")
        XCTAssertEqual(context.payloadFields["recovery_kind"], "regenerate_patch")
        XCTAssertEqual(context.payloadFields["previous_base_file_hash"], "old-hash")
        XCTAssertEqual(context.previewFields["recovery_summary"]?.contains("failed-action"), true)
    }

    func testBuildsRecoveryContextFromExplicitTargetPath() throws {
        let rootURL = try makeTemporaryDirectory()
        let targetURL = rootURL.appendingPathComponent("Paper/main.typ")
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "= Current".write(to: targetURL, atomically: true, encoding: .utf8)
        let actionPlan = makeActionPlan(
            payload: [
                "target_path": targetURL.path,
                "target_content_hash": "old-writing-hash"
            ]
        )

        let context = ActionPlanRecoveryContextBuilder().build(
            from: actionPlan,
            configuration: WorkspaceConfiguration(),
            recoveredAt: baseDate
        )

        XCTAssertEqual(context.targetPath, targetURL.path)
        XCTAssertEqual(context.previousBaseFileHash, "old-writing-hash")
        XCTAssertEqual(context.observedFileHash, LocalFilePatchExecutor.contentHash(for: "= Current"))
    }

    func testBuildsRecoveryContextFromStructuredFailureError() throws {
        let rootURL = try makeTemporaryDirectory()
        let targetURL = rootURL.appendingPathComponent("Paper/Recovered.md")
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "new content".write(to: targetURL, atomically: true, encoding: .utf8)
        let actionPlan = makeActionPlan(
            payload: [:],
            error: [
                "code": "file_changed_since_preview",
                "message": "Target file changed since preview.",
                "target_path": targetURL.path,
                "expected_base_file_hash": "expected-old"
            ]
        )

        let context = ActionPlanRecoveryContextBuilder().build(
            from: actionPlan,
            configuration: WorkspaceConfiguration(),
            recoveredAt: baseDate
        )

        XCTAssertEqual(context.targetPath, targetURL.path)
        XCTAssertEqual(context.previousBaseFileHash, "expected-old")
        XCTAssertEqual(context.observedFileHash, LocalFilePatchExecutor.contentHash(for: "new content"))
        XCTAssertEqual(context.errorMessage, "Target file changed since preview.")
    }

    func testRecoveryTargetValidatorRejectsTargetChanges() {
        let context = ActionPlanRecoveryContext(
            recoveringFromActionPlanId: "failed-action",
            targetPath: "/tmp/old.md",
            observedFileHash: "observed"
        )

        XCTAssertThrowsError(
            try ActionPlanRecoveryTargetValidator().validate(
                context: context,
                currentTargetPath: "/tmp/new.md",
                currentBaseFileHash: "observed"
            )
        ) { error in
            XCTAssertEqual(
                error as? ActionPlanRecoveryValidationError,
                .targetChanged(previous: "/tmp/old.md", current: "/tmp/new.md")
            )
        }
    }

    func testRecoveryTargetValidatorRejectsHashRace() {
        let context = ActionPlanRecoveryContext(
            recoveringFromActionPlanId: "failed-action",
            targetPath: "/tmp/current.md",
            observedFileHash: "observed"
        )

        XCTAssertThrowsError(
            try ActionPlanRecoveryTargetValidator().validate(
                context: context,
                currentTargetPath: "/tmp/current.md",
                currentBaseFileHash: "changed-again"
            )
        ) { error in
            XCTAssertEqual(
                error as? ActionPlanRecoveryValidationError,
                .observedHashMismatch(targetPath: "/tmp/current.md", observed: "observed", current: "changed-again")
            )
        }
    }

    private func makeActionPlan(
        payload: [String: String],
        error: [String: String]? = nil,
        errorMessage: String? = nil
    ) -> AgentActionPlan {
        AgentActionPlan(
            id: "failed-action",
            kind: .writeObsidian,
            status: .failed,
            title: "Failed write",
            summary: "Failed write",
            requestedPermissions: [.writeObsidian],
            payloadHash: "payload",
            payload: payload,
            preview: ["patch": "> Patch"],
            createdAt: baseDate,
            updatedAt: baseDate,
            error: error,
            errorMessage: errorMessage
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActionPlanRecoveryContextBuilderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return rootURL
    }
}
