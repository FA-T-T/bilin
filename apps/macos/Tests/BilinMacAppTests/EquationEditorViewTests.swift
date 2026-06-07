import XCTest
@testable import BilinMacApp
import BilinRenderKit

final class EquationEditorViewTests: XCTestCase {
    func testTemplateRenderQueueCommitsOnlyFullOrFinalBatches() {
        XCTAssertFalse(
            EquationTemplateRenderQueue.shouldCommitRenderedBatch(
                count: EquationTemplateRenderQueue.stateCommitBatchSize - 1,
                remainingCount: 3
            )
        )
        XCTAssertTrue(
            EquationTemplateRenderQueue.shouldCommitRenderedBatch(
                count: EquationTemplateRenderQueue.stateCommitBatchSize,
                remainingCount: 3
            )
        )
        XCTAssertTrue(
            EquationTemplateRenderQueue.shouldCommitRenderedBatch(
                count: 1,
                remainingCount: 0
            )
        )
        XCTAssertFalse(
            EquationTemplateRenderQueue.shouldCommitRenderedBatch(
                count: 0,
                remainingCount: 0
            )
        )
    }

    func testPreviewPublicationPolicySkipsEquivalentStateWrites() {
        let result = MathRenderResult(
            latex: "x",
            mode: .display,
            accessibilityLabel: "x",
            payload: .plainText("x")
        )
        let changedPayload = MathRenderResult(
            latex: "x",
            mode: .display,
            accessibilityLabel: "x",
            payload: .svg("<svg/>")
        )

        XCTAssertFalse(
            EquationPreviewPublicationPolicy.shouldPublishResult(
                current: result,
                next: result
            )
        )
        XCTAssertTrue(
            EquationPreviewPublicationPolicy.shouldPublishResult(
                current: result,
                next: changedPayload
            )
        )
        XCTAssertFalse(
            EquationPreviewPublicationPolicy.shouldPublishRenderingFlag(
                current: true,
                next: true
            )
        )
        XCTAssertTrue(
            EquationPreviewPublicationPolicy.shouldPublishRenderingFlag(
                current: true,
                next: false
            )
        )
    }

    func testLatexEditorUpdatePolicySkipsDuplicateTextAndSelectionPublishes() {
        let selection = EquationTextSelection(location: 3, length: 2)
        let changedSelection = EquationTextSelection(location: 4, length: 0)

        XCTAssertFalse(
            EquationLatexEditorUpdatePolicy.shouldPublishText(
                current: "\\alpha",
                next: "\\alpha"
            )
        )
        XCTAssertTrue(
            EquationLatexEditorUpdatePolicy.shouldPublishText(
                current: "\\alpha",
                next: "\\beta"
            )
        )
        XCTAssertFalse(
            EquationLatexEditorUpdatePolicy.shouldPublishSelection(
                current: selection,
                next: selection
            )
        )
        XCTAssertTrue(
            EquationLatexEditorUpdatePolicy.shouldPublishSelection(
                current: selection,
                next: changedSelection
            )
        )
    }
}
