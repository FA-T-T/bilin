import XCTest
@testable import BilinRenderKit

final class FallbackMathRendererTests: XCTestCase {
    func testDisplayFallbackReturnsStablePlainTextResult() {
        let renderer = FallbackMathRenderer()

        let result = renderer.renderDisplay(latex: "E = mc^2")

        XCTAssertEqual(result.latex, "E = mc^2")
        XCTAssertEqual(result.mode, .display)
        XCTAssertEqual(result.accessibilityLabel, "E = mc^2")
        XCTAssertEqual(result.payload, .plainText("E = mc^2"))
    }

    func testInlineFallbackReturnsStablePlainTextResult() {
        let renderer = FallbackMathRenderer()

        let result = renderer.renderInline(
            latex: "\\alpha + \\beta",
            accessibilityLabel: "alpha plus beta"
        )

        XCTAssertEqual(result.latex, "\\alpha + \\beta")
        XCTAssertEqual(result.mode, .inline)
        XCTAssertEqual(result.accessibilityLabel, "alpha plus beta")
        XCTAssertEqual(result.payload, .plainText("\\alpha + \\beta"))
    }
}
