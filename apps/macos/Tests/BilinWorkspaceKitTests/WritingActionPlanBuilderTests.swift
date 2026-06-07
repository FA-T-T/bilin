import XCTest
@testable import BilinWorkspaceKit

final class WritingActionPlanBuilderTests: XCTestCase {
    private let builder = WritingActionPlanBuilder()
    private let baseHash = "sha256-base"

    func testTypstSectionHitBuildsAnchorAwareActionPlanPayload() {
        let mainFileText = """
        = Introduction
        Intro section.

        = Related Work
        Background section.

        = Method
        Approach description.
        """

        let result = builder.build(
            mainFileText: mainFileText,
            targetPath: "/tmp/paper.typ",
            sourceBlock: "A short typst block",
            articleRevisionId: "rev-123",
            blockUid: "b-001",
            baseFileHash: baseHash,
            targetSectionPreference: "Method",
            patchId: "patch-typ-1"
        )

        XCTAssertTrue(result.writingPatchDraft.anchorFound)
        XCTAssertEqual(result.writingPatchDraft.insertionMode, .sectionEnd)
        XCTAssertEqual(result.writingPatchDraft.pendingPatch.targetAnchor, "method")
        XCTAssertFalse(decodeStringList(result.actionPlanPayload["target_section_path"] ?? "[]").isEmpty)
        XCTAssertEqual(result.actionPlanPayload["target_path"], "/tmp/paper.typ")
        XCTAssertEqual(result.actionPlanPayload["base_file_hash"], baseHash)
        XCTAssertEqual(result.actionPlanPayload["source_markdown"], "A short typst block")
        XCTAssertEqual(result.actionPlanPayload["block_uid"], "b-001")
        XCTAssertEqual(result.actionPlanPayload["article_revision_id"], "rev-123")
        XCTAssertEqual(result.actionPlanPayload["insertion_mode"], WritingPatchInsertionMode.sectionEnd.rawValue)
        XCTAssertFalse(result.actionPlanPayload["insertion_line"]?.isEmpty ?? true)
        XCTAssertEqual(result.actionPlanPayload["patch"], result.writingPatchDraft.pendingPatch.patchText)
        XCTAssertEqual(result.actionPlanDraft.idempotencyKey, "writing-dock-rev-123-b-001-/tmp/paper.typ-\(baseHash)")
        XCTAssertFalse(result.actionPlanDraft.steps.isEmpty)
        XCTAssertEqual(result.actionPlanDraft.steps.first?.payload, result.actionPlanStepPayload)

        for requiredKey in requiredActionPlanKeys {
            XCTAssertNotNil(result.actionPlanPreview[requiredKey])
        }
    }

    func testTeXBibliographyPayloadKeepsListEncoding() {
        let mainFileText = """
        \\documentclass{article}
        \\addbibresource{refs/repo}
        Some text.
        \\bibliography{refs/paper,refs/appendix}
        """
        let result = builder.build(
            mainFileText: mainFileText,
            targetPath: "/tmp/paper.tex",
            sourceBlock: "A short latex block",
            articleRevisionId: "rev-124",
            blockUid: "b-002",
            baseFileHash: "sha256-tex",
            targetSectionPreference: "Discussion",
            patchId: "patch-tex-1"
        )

        XCTAssertEqual(
            decodeStringList(result.actionPlanPayload["bibliography_paths"] ?? "[]"),
            ["refs/repo.bib", "refs/paper.bib", "refs/appendix.bib"]
        )
        XCTAssertEqual(result.writingPatchDraft.pendingPatch.format, .tex)
        XCTAssertTrue(result.writingPatchDraft.pendingPatch.patchText.contains("begin{quote}"))
        XCTAssertEqual(result.actionPlanPayload["insertion_mode"], WritingPatchInsertionMode.appendToEnd.rawValue)
    }

    func testMissingAnchorFallsBackToAppendToEnd() {
        let mainFileText = """
        = Introduction
        Intro section.
        """

        let result = builder.build(
            mainFileText: mainFileText,
            targetPath: "/tmp/paper.typ",
            sourceBlock: "fallback block",
            articleRevisionId: "rev-125",
            blockUid: "b-003",
            baseFileHash: "sha256-fallback",
            targetSectionPreference: "Discussion",
            patchId: "patch-fallback-1"
        )

        XCTAssertFalse(result.writingPatchDraft.anchorFound)
        XCTAssertEqual(result.writingPatchDraft.insertionMode, .appendToEnd)
        XCTAssertNil(result.writingPatchDraft.sectionAnchor)
        XCTAssertEqual(result.writingPatchDraft.pendingPatch.targetAnchor, nil)
        XCTAssertEqual(result.actionPlanPayload["target_section_path"], "[]")
        XCTAssertEqual(result.actionPlanPayload["insertion_mode"], WritingPatchInsertionMode.appendToEnd.rawValue)
        XCTAssertEqual(result.actionPlanPayload["insertion_line"], "")
        XCTAssertEqual(result.actionPlanPayload["target_anchor"], "")
    }

    func testRecoveryContextIsAddedToWritingPayloadPreviewAndIdempotencyKey() {
        let mainFileText = """
        = Related Work
        Prior art.
        """
        let fresh = builder.build(
            mainFileText: mainFileText,
            targetPath: "/tmp/paper.typ",
            sourceBlock: "recovered block",
            articleRevisionId: "rev-126",
            blockUid: "b-004",
            baseFileHash: "new-base",
            targetSectionPreference: "Related Work",
            patchId: "patch-recovery-1"
        )
        let recovered = builder.build(
            mainFileText: mainFileText,
            targetPath: "/tmp/paper.typ",
            sourceBlock: "recovered block",
            articleRevisionId: "rev-126",
            blockUid: "b-004",
            baseFileHash: "new-base",
            targetSectionPreference: "Related Work",
            patchId: "patch-recovery-1",
            recoveryContext: ActionPlanRecoveryContext(
                recoveringFromActionPlanId: "failed-writing",
                targetPath: "/tmp/paper.typ",
                previousBaseFileHash: "old-base",
                observedFileHash: "new-base",
                errorMessage: "Target file changed.",
                recoveredAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        XCTAssertEqual(recovered.actionPlanPayload["recovery_kind"], "regenerate_patch")
        XCTAssertEqual(recovered.actionPlanPayload["recovering_from_action_plan_id"], "failed-writing")
        XCTAssertEqual(recovered.actionPlanPayload["previous_base_file_hash"], "old-base")
        XCTAssertEqual(recovered.actionPlanPayload["observed_file_hash"], "new-base")
        XCTAssertEqual(recovered.actionPlanPayload["base_file_hash"], "new-base")
        XCTAssertTrue(recovered.actionPlanPreview["recovery_summary"]?.contains("failed-writing") ?? false)
        XCTAssertNotEqual(fresh.actionPlanDraft.idempotencyKey, recovered.actionPlanDraft.idempotencyKey)
    }

    func testSelectedTextHashIsAuditedAndKeepsWholeBlockKeyStableWhenAbsent() {
        let mainFileText = """
        = Related Work
        Prior art.
        """
        let wholeBlock = builder.build(
            mainFileText: mainFileText,
            targetPath: "/tmp/paper.typ",
            sourceBlock: "whole block",
            articleRevisionId: "rev-127",
            blockUid: "b-005",
            baseFileHash: "base-selected",
            targetSectionPreference: "Related Work",
            patchId: "patch-selection-1"
        )
        let selectedBlock = builder.build(
            mainFileText: mainFileText,
            targetPath: "/tmp/paper.typ",
            sourceBlock: "selected claim",
            articleRevisionId: "rev-127",
            blockUid: "b-005",
            baseFileHash: "base-selected",
            targetSectionPreference: "Related Work",
            selectedTextHash: "sha256:selected",
            patchId: "patch-selection-1"
        )

        XCTAssertEqual(wholeBlock.actionPlanDraft.idempotencyKey, "writing-dock-rev-127-b-005-/tmp/paper.typ-base-selected")
        XCTAssertEqual(selectedBlock.actionPlanPayload["selected_text_hash"], "sha256:selected")
        XCTAssertEqual(selectedBlock.actionPlanStepPayload["selected_text_hash"], "sha256:selected")
        XCTAssertNotEqual(wholeBlock.actionPlanDraft.idempotencyKey, selectedBlock.actionPlanDraft.idempotencyKey)
    }

    private var requiredActionPlanKeys: [String] {
        [
            "target_path",
            "base_file_hash",
            "source_markdown",
            "block_uid",
            "article_revision_id",
            "target_anchor",
            "target_section_path",
            "insertion_mode",
            "insertion_line",
            "bibliography_paths",
            "patch"
        ]
    }

    private func decodeStringList(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return decoded
    }
}
