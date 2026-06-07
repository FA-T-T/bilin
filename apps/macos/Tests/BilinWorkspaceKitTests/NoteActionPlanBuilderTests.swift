import XCTest
@testable import BilinWorkspaceKit

final class NoteActionPlanBuilderTests: XCTestCase {
    private let builder = NoteActionPlanBuilder()

    func testBuildsVaultBackedPatchPayloadAndStableIdempotencyKey() {
        let first = builder.build(
            articleTitle: "A/B: Paper\nTitle",
            articleRevisionId: "rev-1",
            blockUid: "block-7",
            sourceMarkdown: "A source claim.",
            translationMarkdown: "A translated claim.",
            vaultPath: "/tmp/Obsidian",
            baseFileHash: "sha256-base"
        )
        let second = builder.build(
            articleTitle: "A/B: Paper\nTitle",
            articleRevisionId: "rev-1",
            blockUid: "block-7",
            sourceMarkdown: "A source claim.",
            translationMarkdown: "A translated claim.",
            vaultPath: "/tmp/Obsidian",
            baseFileHash: "sha256-base"
        )

        XCTAssertEqual(first.targetNotePath, "Papers/A-B- Paper Title.md")
        XCTAssertEqual(first.blockAnchor, "^ilios-rev-1-block-7")
        XCTAssertEqual(first.targetPath, "/tmp/Obsidian/Papers/A-B- Paper Title.md")
        XCTAssertEqual(first.baseFileHash, "sha256-base")
        XCTAssertEqual(first.actionPlanPayload["target_vault_path"], "/tmp/Obsidian")
        XCTAssertEqual(first.actionPlanPayload["target_path"], first.targetPath)
        XCTAssertEqual(first.actionPlanPayload["base_file_hash"], "sha256-base")
        XCTAssertEqual(first.actionPlanPayload["translation_markdown"], "A translated claim.")
        XCTAssertEqual(first.actionPlanPreview["patch"], first.patchText)
        XCTAssertEqual(first.actionPlanDraft.idempotencyKey, second.actionPlanDraft.idempotencyKey)
        XCTAssertEqual(first.actionPlanDraft.steps.first?.kind, "render_patch")
        XCTAssertEqual(first.actionPlanDraft.steps.first?.payload["target_note"], first.targetNotePath)
        XCTAssertTrue(first.patchText.contains("> [!note] Source block ^ilios-rev-1-block-7"))
        XCTAssertTrue(first.patchText.contains("> A source claim."))
        XCTAssertTrue(first.patchText.contains("> A translated claim."))
    }

    func testOmitsVaultFieldsAndEmptyTranslationWhenNoVaultIsConfigured() {
        let result = builder.build(
            articleTitle: " \n ",
            articleRevisionId: "rev-2",
            blockUid: "block-8",
            sourceMarkdown: "A second claim.",
            translationMarkdown: "",
            vaultPath: nil,
            baseFileHash: "sha256-ignored"
        )

        XCTAssertEqual(result.targetNotePath, "Papers/Untitled Paper.md")
        XCTAssertNil(result.targetPath)
        XCTAssertEqual(result.actionPlanPayload["target_note"], "Papers/Untitled Paper.md")
        XCTAssertNil(result.actionPlanPayload["target_path"])
        XCTAssertNil(result.actionPlanPayload["target_vault_path"])
        XCTAssertNil(result.actionPlanPayload["base_file_hash"])
        XCTAssertNil(result.actionPlanPayload["translation_markdown"])
        XCTAssertEqual(result.actionPlanDraft.requiredPermissions, [.writeObsidian])
        XCTAssertEqual(
            result.actionPlanDraft.idempotencyKey?.hasPrefix("note-bridge-rev-2-block-8-"),
            true
        )
    }

    func testPatchTextKeepsMultilineSourceAndTranslationInsideObsidianCallout() {
        let result = builder.build(
            articleTitle: "Multiline Paper",
            articleRevisionId: "rev-multiline",
            blockUid: "block-multiline",
            sourceMarkdown: "First line.\n\nSecond line with `code`.",
            translationMarkdown: "第一行。\n第二行。",
            vaultPath: "/tmp/Obsidian",
            baseFileHash: "sha256-base"
        )

        let expectedPatch = [
            "> [!note] Source block ^ilios-rev-multiline-block-multiline",
            "> First line.",
            "> ",
            "> Second line with `code`.",
            "> 第一行。",
            "> 第二行。",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(
            result.patchText,
            expectedPatch
        )
        XCTAssertEqual(result.actionPlanPreview["patch"], result.patchText)
    }

    func testRecoveryContextIsAddedToPayloadPreviewAndIdempotencyKey() {
        let fresh = builder.build(
            articleTitle: "Recovered Paper",
            articleRevisionId: "rev-3",
            blockUid: "block-9",
            sourceMarkdown: "Recovered claim.",
            vaultPath: "/tmp/Obsidian",
            baseFileHash: "new-base"
        )
        let recovered = builder.build(
            articleTitle: "Recovered Paper",
            articleRevisionId: "rev-3",
            blockUid: "block-9",
            sourceMarkdown: "Recovered claim.",
            vaultPath: "/tmp/Obsidian",
            baseFileHash: "new-base",
            recoveryContext: ActionPlanRecoveryContext(
                recoveringFromActionPlanId: "failed-action",
                targetPath: "/tmp/Obsidian/Papers/Recovered Paper.md",
                targetNote: "Papers/Recovered Paper.md",
                previousBaseFileHash: "old-base",
                observedFileHash: "new-base",
                errorMessage: "Target file changed.",
                recoveredAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        XCTAssertEqual(recovered.actionPlanPayload["recovery_kind"], "regenerate_patch")
        XCTAssertEqual(recovered.actionPlanPayload["recovering_from_action_plan_id"], "failed-action")
        XCTAssertEqual(recovered.actionPlanPayload["previous_base_file_hash"], "old-base")
        XCTAssertEqual(recovered.actionPlanPayload["observed_file_hash"], "new-base")
        XCTAssertEqual(recovered.actionPlanPayload["base_file_hash"], "new-base")
        XCTAssertTrue(recovered.actionPlanPreview["recovery_summary"]?.contains("failed-action") ?? false)
        XCTAssertNotEqual(fresh.actionPlanDraft.idempotencyKey, recovered.actionPlanDraft.idempotencyKey)
    }

    func testSelectedTextHashIsAuditedAndChangesIdempotencyKey() {
        let firstSelection = builder.build(
            articleTitle: "Selection Paper",
            articleRevisionId: "rev-selection",
            blockUid: "block-1",
            sourceMarkdown: "first selected claim",
            selectedTextHash: "sha256:first",
            vaultPath: "/tmp/Obsidian",
            baseFileHash: "base"
        )
        let secondSelection = builder.build(
            articleTitle: "Selection Paper",
            articleRevisionId: "rev-selection",
            blockUid: "block-1",
            sourceMarkdown: "second selected claim",
            selectedTextHash: "sha256:second",
            vaultPath: "/tmp/Obsidian",
            baseFileHash: "base"
        )

        XCTAssertEqual(firstSelection.actionPlanPayload["selected_text_hash"], "sha256:first")
        XCTAssertEqual(secondSelection.actionPlanPayload["selected_text_hash"], "sha256:second")
        XCTAssertNotEqual(firstSelection.actionPlanDraft.idempotencyKey, secondSelection.actionPlanDraft.idempotencyKey)
    }
}
