import XCTest
@testable import BilinReaderKit

final class ReaderMarkdownBlockSegmenterTests: XCTestCase {
    override func tearDown() {
        ReaderMarkdownBlockSegmenter.removeAllForTesting()
        super.tearDown()
    }

    func testSegmentsAreCachedByExactMarkdownInput() {
        let markdown = """
        The update is

        $$
        x = y
        $$
        """

        XCTAssertFalse(ReaderMarkdownBlockSegmenter.hasCachedSegments(for: markdown))
        let first = ReaderMarkdownBlockSegmenter.segments(in: markdown)
        XCTAssertTrue(ReaderMarkdownBlockSegmenter.hasCachedSegments(for: markdown))
        let second = ReaderMarkdownBlockSegmenter.segments(in: markdown)

        XCTAssertEqual(first, second)
        XCTAssertEqual(second.map(\.kind), [.markdown, .displayMath])
    }

    func testReturnsSingleMarkdownSegmentWhenNoDisplayMathIsPresent() {
        let segments = ReaderMarkdownBlockSegmenter.segments(in: "The proof uses $x_i$ inline.")

        XCTAssertEqual(segments.map(\.kind), [.markdown])
        XCTAssertEqual(segments.first?.text, "The proof uses $x_i$ inline.")
    }

    func testSplitsDollarDisplayMathFromSurroundingMarkdown() {
        let segments = ReaderMarkdownBlockSegmenter.segments(
            in: """
            The update is

            $$
            \\Delta w^t = p^t\\Delta w^{t-1}
            $$

            before normalization.
            """
        )

        XCTAssertEqual(segments.map(\.kind), [.markdown, .displayMath, .markdown])
        XCTAssertEqual(segments[0].text, "The update is")
        XCTAssertEqual(segments[1].text, #"\Delta w^t = p^t\Delta w^{t-1}"#)
        XCTAssertEqual(segments[2].text, "before normalization.")
    }

    func testDecodesHTMLEntitiesInDollarDisplayMath() {
        let segments = ReaderMarkdownBlockSegmenter.segments(in: "$$x &lt; y &amp; y &gt; z$$")

        XCTAssertEqual(segments.map(\.kind), [.displayMath])
        XCTAssertEqual(segments.first?.text, "x < y & y > z")
    }

    func testSplitsBracketDisplayMath() {
        let segments = ReaderMarkdownBlockSegmenter.segments(in: #"Then \[\nabla_\theta L = 0\] at stationarity."#)

        XCTAssertEqual(segments.map(\.kind), [.markdown, .displayMath, .markdown])
        XCTAssertEqual(segments[1].text, #"\nabla_\theta L = 0"#)
    }

    func testSplitsEquationEnvironmentAsDisplayMathBody() {
        let segments = ReaderMarkdownBlockSegmenter.segments(
            in: #"""
            The closed form is
            \begin{equation}
            E = mc^2
            \end{equation}
            after normalization.
            """#
        )

        XCTAssertEqual(segments.map(\.kind), [.markdown, .displayMath, .markdown])
        XCTAssertEqual(segments[0].text, "The closed form is")
        XCTAssertEqual(segments[1].text, "E = mc^2")
        XCTAssertEqual(segments[2].text, "after normalization.")
    }

    func testSplitsAlignEnvironmentAndPreservesEnvironment() {
        let segments = ReaderMarkdownBlockSegmenter.segments(
            in: #"""
            We solve
            \begin{align}
            x &= y \\
            z &= w
            \end{align}
            before the proof.
            """#
        )

        XCTAssertEqual(segments.map(\.kind), [.markdown, .displayMath, .markdown])
        XCTAssertTrue(segments[1].text.hasPrefix(#"\begin{align}"#))
        XCTAssertTrue(segments[1].text.hasSuffix(#"\end{align}"#))
        XCTAssertTrue(segments[1].text.contains(#"x &= y \\"#))
    }

    func testSplitsLatexmlDisplayMathTag() {
        let segments = ReaderMarkdownBlockSegmenter.segments(
            in: ##"Before <math display="block" alttext="\nabla_\theta L = 0"><mi>L</mi></math> after."##
        )

        XCTAssertEqual(segments.map(\.kind), [.markdown, .displayMath, .markdown])
        XCTAssertEqual(segments[0].text, "Before")
        XCTAssertEqual(segments[1].text, #"\nabla_\theta L = 0"#)
        XCTAssertEqual(segments[2].text, "after.")
    }

    func testSplitsPandocDisplayMathSpan() {
        let segments = ReaderMarkdownBlockSegmenter.segments(
            in: ##"Before <span class="math display" data-latex="\sum_i x_i">∑</span> after."##
        )

        XCTAssertEqual(segments.map(\.kind), [.markdown, .displayMath, .markdown])
        XCTAssertEqual(segments[1].text, #"\sum_i x_i"#)
    }

    func testSplitsMathJaxDisplayScript() {
        let segments = ReaderMarkdownBlockSegmenter.segments(
            in: ##"Before <script type="math/tex; mode=display">\int_a^b f(x)\,dx</script> after."##
        )

        XCTAssertEqual(segments.map(\.kind), [.markdown, .displayMath, .markdown])
        XCTAssertEqual(segments[1].text, #"\int_a^b f(x)\,dx"#)
    }

    func testSplitsKatexDisplayAnnotation() {
        let segments = ReaderMarkdownBlockSegmenter.segments(
            in: ##"Before <span class="katex-display"><span class="katex"><span class="katex-mathml"><math><semantics><annotation encoding="application/x-tex">E = mc^2</annotation></semantics></math></span><span class="katex-html">rendered</span></span></span> after."##
        )

        XCTAssertEqual(segments.map(\.kind), [.markdown, .displayMath, .markdown])
        XCTAssertEqual(segments[1].text, "E = mc^2")
    }

    func testLeavesInlineHTMLMathAsMarkdown() {
        let segments = ReaderMarkdownBlockSegmenter.segments(
            in: ##"Before <math display="inline" alttext="x_i"><mi>x</mi></math> after."##
        )

        XCTAssertEqual(segments.map(\.kind), [.markdown])
        XCTAssertEqual(segments.first?.text, ##"Before <math display="inline" alttext="x_i"><mi>x</mi></math> after."##)
    }

    func testLeavesUnclosedDisplayMathAsMarkdown() {
        let segments = ReaderMarkdownBlockSegmenter.segments(in: "This is not closed $$x + y.")

        XCTAssertEqual(segments.map(\.kind), [.markdown])
        XCTAssertEqual(segments.first?.text, "This is not closed $$x + y.")
    }

    func testLeavesUnclosedDisplayEnvironmentAsMarkdown() {
        let segments = ReaderMarkdownBlockSegmenter.segments(in: #"This is not closed \begin{equation}x + y."#)

        XCTAssertEqual(segments.map(\.kind), [.markdown])
        XCTAssertEqual(segments.first?.text, #"This is not closed \begin{equation}x + y."#)
    }
}
