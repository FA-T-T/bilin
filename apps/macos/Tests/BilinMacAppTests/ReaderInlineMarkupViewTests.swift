import AppKit
import SwiftUI
import XCTest
import BilinReaderKit
import BilinRenderKit
@testable import BilinMacApp

@MainActor
final class ReaderInlineMarkupViewTests: XCTestCase {
    override func tearDown() {
        ReaderSemanticCopyFormatter.removeAllForTesting()
        super.tearDown()
    }

    func testInlineRunCacheStoresParsedRunsByMarkdown() {
        let markdown = "Readable $x_i$ with [12](#bib.bib12)."
        ReaderInlineRunCache.removeAllForTesting()

        XCTAssertFalse(ReaderInlineRunCache.hasCachedRuns(for: markdown))
        let first = ReaderInlineRunCache.runs(in: markdown)
        let second = ReaderInlineRunCache.runs(in: markdown)

        XCTAssertTrue(ReaderInlineRunCache.hasCachedRuns(for: markdown))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.kind), [.text, .inlineMath, .text, .citation, .text])
    }

    func testSemanticCopyFormatterCachesInlineMarkdownByExactInput() {
        let markdown = #"Readable $x_i$ with \citep{smith2024}."#
        ReaderSemanticCopyFormatter.removeAllForTesting()

        XCTAssertFalse(ReaderSemanticCopyFormatter.hasCachedInlineMarkdown(for: markdown))
        let first = ReaderSemanticCopyFormatter.inlineMarkdown(markdown: markdown)
        let second = ReaderSemanticCopyFormatter.inlineMarkdown(markdown: markdown)

        XCTAssertEqual(first, "Readable $x_i$ with [@smith2024].")
        XCTAssertEqual(second, first)
        XCTAssertTrue(ReaderSemanticCopyFormatter.hasCachedInlineMarkdown(for: markdown))
    }

    func testSemanticCopyFormatterCachesBlockMarkdownWithDisplayMathSegments() {
        let markdown = """
        Before \\citep{smith2024}

        $$
        x = y
        $$
        """
        ReaderSemanticCopyFormatter.removeAllForTesting()

        XCTAssertFalse(ReaderSemanticCopyFormatter.hasCachedBlockMarkdown(for: markdown))
        let first = ReaderSemanticCopyFormatter.blockMarkdown(markdown: markdown)
        let second = ReaderSemanticCopyFormatter.blockMarkdown(markdown: markdown)

        XCTAssertEqual(first, "Before [@smith2024]\n\n$$\nx = y\n$$")
        XCTAssertEqual(second, first)
        XCTAssertTrue(ReaderSemanticCopyFormatter.hasCachedBlockMarkdown(for: markdown))
    }

    func testAttributedStringCacheReusesStableReaderBlockRendering() {
        let markdown = "Readable $x_i$ with [12](#bib.bib12)."
        let signature = ReaderAttributedTextSignature.make(
            markdown: markdown,
            font: .body,
            citationResolver: .empty,
            bibliographyLines: [],
            selectedCitationEntryId: nil,
            mathResults: [:]
        )
        let view = SelectableInlineMarkupView(markdown: markdown, font: .body)
        ReaderAttributedStringCache.removeAllForTesting()

        XCTAssertFalse(ReaderAttributedStringCache.hasCachedAttributedString(for: signature))
        let first = view.attributedStringForTesting()
        let second = view.attributedStringForTesting()

        XCTAssertTrue(ReaderAttributedStringCache.hasCachedAttributedString(for: signature))
        XCTAssertTrue(first === second)
        XCTAssertEqual(second.string, "Readable $x_i$ with [12].")
        XCTAssertEqual(
            second.attribute(.bilinInlineMathLatex, at: "Readable ".count, effectiveRange: nil) as? String,
            "x_i"
        )
        XCTAssertNil(
            second.attribute(.bilinInlineMathUnavailableReason, at: "Readable ".count, effectiveRange: nil)
        )
    }

    func testAttributedStringCacheSeparatesCitationResolverState() {
        let markdown = #"Prior work \citep{smith2024}."#
        let firstResolver = ReaderCitationResolver(entries: [
            ReaderCitationEntry(
                id: "smith2024",
                label: "Smith 2024",
                title: "First title",
                rawText: "Smith. First title.",
                sourceBlockUid: "bib",
                sourceStructuralPath: "99999"
            )
        ])
        let secondResolver = ReaderCitationResolver(entries: [
            ReaderCitationEntry(
                id: "smith2024",
                label: "Smith 2024",
                title: "Second title",
                rawText: "Smith. Second title.",
                sourceBlockUid: "bib",
                sourceStructuralPath: "99999"
            )
        ])
        let firstView = SelectableInlineMarkupView(
            markdown: markdown,
            font: .body,
            citationResolver: firstResolver
        )
        let secondView = SelectableInlineMarkupView(
            markdown: markdown,
            font: .body,
            citationResolver: secondResolver
        )
        ReaderAttributedStringCache.removeAllForTesting()

        let first = firstView.attributedStringForTesting()
        let second = secondView.attributedStringForTesting()

        XCTAssertFalse(first === second)
        XCTAssertNotEqual(
            first.attribute(NSAttributedString.Key("NSToolTip"), at: 11, effectiveRange: nil) as? String,
            second.attribute(NSAttributedString.Key("NSToolTip"), at: 11, effectiveRange: nil) as? String
        )
    }

    func testSelectableRichTextDefersMathOnlyVisualUpdatesWhileSelectionIsActive() {
        XCTAssertTrue(
            SelectableRichTextUpdatePolicy.shouldDeferUpdate(
                selectedText: "selected reader text",
                currentSelectionStabilitySignature: "same-reader-semantics",
                nextSelectionStabilitySignature: "same-reader-semantics"
            )
        )
        XCTAssertFalse(
            SelectableRichTextUpdatePolicy.shouldDeferUpdate(
                selectedText: "",
                currentSelectionStabilitySignature: "same-reader-semantics",
                nextSelectionStabilitySignature: "same-reader-semantics"
            )
        )
    }

    func testSelectableRichTextDoesNotDeferSemanticReaderUpdates() {
        XCTAssertFalse(
            SelectableRichTextUpdatePolicy.shouldDeferUpdate(
                selectedText: "selected reader text",
                currentSelectionStabilitySignature: "old-reader-semantics",
                nextSelectionStabilitySignature: "new-reader-semantics"
            )
        )
    }

    func testTextViewDoesNotActivateBlockWhenTextIsSelected() {
        let textView = IntrinsicTextView(frame: .zero)
        textView.setAttributedStringForTesting(NSAttributedString(string: "Readable paragraph text."))
        textView.setSelectedRange(NSRange(location: 0, length: 8))

        XCTAssertEqual(textView.copyableSelectedText(), "Readable")
        XCTAssertFalse(textView.shouldActivateAfterMouseDown())
    }

    func testTextViewActivatesBlockOnlyForPlainClick() {
        let textView = IntrinsicTextView(frame: .zero)
        textView.setAttributedStringForTesting(NSAttributedString(string: "Readable paragraph text."))
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(textView.copyableSelectedText().isEmpty)
        XCTAssertTrue(textView.shouldActivateAfterMouseDown())
    }

    func testCitationClickSuppressesBlockActivationForCurrentMouseDown() {
        let textView = IntrinsicTextView(frame: .zero)
        textView.setAttributedStringForTesting(NSAttributedString(string: "[12]"))
        textView.suppressActivationForCurrentMouseDown()

        XCTAssertFalse(textView.shouldActivateAfterMouseDown())
    }

    func testTextViewSelectionProvidesLocalCopyMenu() throws {
        let textView = IntrinsicTextView(frame: .zero)
        textView.setAttributedStringForTesting(NSAttributedString(string: "Readable paragraph text."))
        textView.setSelectedRange(NSRange(location: 0, length: 8))

        let menu = textView.readerSelectionContextMenu()

        XCTAssertEqual(menu?.items.map(\.title), ["Copy"])
        let copyItem = try XCTUnwrap(menu?.items.first)
        XCTAssertTrue(copyItem.target === textView)
    }

    func testCitationCopyFormatterPreservesSemanticMarkdownReferences() {
        XCTAssertEqual(
            ReaderSemanticCopyFormatter.citationMarkdown(
                reference: "smith2024,mcclean2018",
                displayText: "[smith2024; mcclean2018]"
            ),
            "[@smith2024; @mcclean2018]"
        )
        XCTAssertEqual(
            ReaderSemanticCopyFormatter.citationMarkdown(
                reference: "paper.html#bib.bib7",
                displayText: "[7]"
            ),
            "[@bib7]"
        )
        XCTAssertEqual(
            ReaderSemanticCopyFormatter.citationMarkdown(
                reference: "12,14-16",
                displayText: "[12, 14-16]"
            ),
            "[12, 14-16]"
        )
    }

    func testCitationCopyFormatterUsesWritingKeysForInternalBibliographyAnchors() {
        XCTAssertEqual(
            ReaderSemanticCopyFormatter.citationMarkdown(
                reference: "#bib.vaswani2017,#bibitem.ba2016,#ref-smith2024,#bib-layernorm",
                displayText: "[5, 4, Smith]"
            ),
            "[@vaswani2017; @ba2016; @smith2024; @layernorm]"
        )
    }

    func testSelectedTextCopiesInlineMathAndCitationsAsMarkdown() {
        let attributed = NSMutableAttributedString(string: "Prior work [7] uses x.")
        attributed.addAttribute(
            .bilinCitationReference,
            value: "paper.html#bib.bib7",
            range: NSRange(location: 11, length: 3)
        )
        attributed.addAttribute(
            .bilinInlineMathLatex,
            value: "x_i",
            range: NSRange(location: 20, length: 1)
        )

        let textView = IntrinsicTextView(frame: .zero)
        textView.setAttributedStringForTesting(attributed)
        textView.setSelectedRange(NSRange(location: 0, length: attributed.length))

        XCTAssertEqual(textView.copyableSelectedText(), "Prior work [@bib7] uses $x_i$.")
    }

    func testCopySelectionWritesSemanticMarkdownToPasteboard() {
        let attributed = NSMutableAttributedString(string: "Prior work [7] uses x.")
        attributed.addAttribute(
            .bilinCitationReference,
            value: "paper.html#bib.bib7",
            range: NSRange(location: 11, length: 3)
        )
        attributed.addAttribute(
            .bilinInlineMathLatex,
            value: "x_i",
            range: NSRange(location: 20, length: 1)
        )
        let textView = IntrinsicTextView(frame: .zero)
        textView.setAttributedStringForTesting(attributed)
        textView.setSelectedRange(NSRange(location: 0, length: attributed.length))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("bilin-reader-copy-test-\(UUID().uuidString)"))
        pasteboard.clearContents()

        XCTAssertTrue(textView.copySelection(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "Prior work [@bib7] uses $x_i$.")
    }

    func testSelectedTextPreservesUserSelectedWhitespaceWhileCopyingSemanticMarkdown() {
        let attributed = NSMutableAttributedString(string: "  Prior work [7] uses x.  ")
        attributed.addAttribute(
            .bilinCitationReference,
            value: "paper.html#bib.bib7",
            range: NSRange(location: 13, length: 3)
        )
        attributed.addAttribute(
            .bilinInlineMathLatex,
            value: "x_i",
            range: NSRange(location: 22, length: 1)
        )

        let textView = IntrinsicTextView(frame: .zero)
        textView.setAttributedStringForTesting(attributed)
        textView.setSelectedRange(NSRange(location: 0, length: attributed.length))

        XCTAssertEqual(textView.copyableSelectedText(), "  Prior work [@bib7] uses $x_i$.  ")
    }

    func testCompoundCitationTargetsEachVisibleReferenceAndCopiesOnce() {
        let resolver = ReaderCitationResolver(entries: [
            ReaderCitationEntry(
                id: "bib.vaswani2017",
                label: "5",
                title: "Attention is all you need",
                rawText: "Vaswani A. Attention is all you need. NeurIPS.",
                sourceBlockUid: "bib",
                sourceStructuralPath: "99999"
            ),
            ReaderCitationEntry(
                id: "bib.bib2",
                label: "2",
                title: "BERT",
                rawText: "Devlin J. BERT. NAACL.",
                sourceBlockUid: "bib",
                sourceStructuralPath: "99999"
            )
        ])
        let view = SelectableInlineMarkupView(
            markdown: ##"Most models cite <cite class="ltx_cite">[<a href="#bib:vaswani2017">5</a>, <a href="#bib.bib2">2</a>]</cite>."##,
            font: .body,
            citationResolver: resolver
        )
        let attributed = view.attributedStringForTesting()
        let text = attributed.string as NSString
        let firstCitationRange = text.range(of: "5")
        let secondCitationRange = text.range(of: "2")
        let fullCitationRange = text.range(of: "[5, 2]")

        XCTAssertEqual(
            attributed.attribute(.link, at: firstCitationRange.location, effectiveRange: nil) as? String,
            ReaderCitationLink.urlString(for: "bib.vaswani2017")
        )
        XCTAssertEqual(
            attributed.attribute(.link, at: secondCitationRange.location, effectiveRange: nil) as? String,
            ReaderCitationLink.urlString(for: "bib.bib2")
        )

        let textView = IntrinsicTextView(frame: .zero)
        textView.setAttributedStringForTesting(attributed)
        textView.setSelectedRange(fullCitationRange)

        XCTAssertEqual(textView.copyableSelectedText(), "[@vaswani2017; @bib2]")
    }

    func testSemanticCopyFormatterConvertsHTMLMathAndCSLCitationsToMarkdown() {
        let markdown = ##"""
        Before <span class="math inline" data-latex="x_i">x</span> and <span class="citation" data-cites="smith2024">(Smith 2024)</span>.

        <span class="math display" data-latex="\sum_i x_i">rendered</span>

        After.
        """##

        XCTAssertEqual(
            ReaderSemanticCopyFormatter.blockMarkdown(markdown: markdown),
            ##"""
            Before $x_i$ and [@smith2024].

            $$
            \sum_i x_i
            $$

            After.
            """##
        )
    }

    func testSemanticCopyFormatterConvertsEscapedBracketBibliographyLinksToMarkdownCitations() {
        XCTAssertEqual(
            ReaderSemanticCopyFormatter.inlineMarkdown(
                markdown: #"This follows [\[1\]](#bib.bib1) in the proof."#
            ),
            "This follows [@bib1] in the proof."
        )
    }

    func testAttributedTextSignatureIgnoresSelectedCitationForRegularInlineText() {
        let first = ReaderAttributedTextSignature.make(
            markdown: "Readable [1](#bib.layernorm)",
            font: .body,
            citationResolver: .empty,
            bibliographyLines: [],
            selectedCitationEntryId: nil,
            mathResults: [:]
        )
        let second = ReaderAttributedTextSignature.make(
            markdown: "Readable [1](#bib.layernorm)",
            font: .body,
            citationResolver: .empty,
            bibliographyLines: [],
            selectedCitationEntryId: "bib.layernorm",
            mathResults: [:]
        )

        XCTAssertEqual(first, second)
    }

    func testAttributedTextSignatureTracksSelectedCitationForBibliographyLines() {
        let line = ReaderBibliographyLine(
            id: "bib.layernorm",
            sourceLine: "[1] Layer normalization.",
            entry: ReaderCitationEntry(
                id: "bib.layernorm",
                label: "1",
                title: "Layer normalization",
                rawText: "Layer normalization.",
                sourceBlockUid: "bib-block",
                sourceStructuralPath: "999"
            )
        )
        let first = ReaderAttributedTextSignature.make(
            markdown: "",
            font: .body,
            citationResolver: .empty,
            bibliographyLines: [line],
            selectedCitationEntryId: nil,
            mathResults: [:]
        )
        let second = ReaderAttributedTextSignature.make(
            markdown: "",
            font: .body,
            citationResolver: .empty,
            bibliographyLines: [line],
            selectedCitationEntryId: "bib.layernorm",
            mathResults: [:]
        )

        XCTAssertNotEqual(first, second)
    }

    func testAttributedTextSignatureTracksMathRenderPayloadChanges() {
        let plain = MathRenderResult(
            latex: "x_i",
            mode: .inline,
            accessibilityLabel: "x_i",
            payload: .plainText("x_i")
        )
        let svg = MathRenderResult(
            latex: "x_i",
            mode: .inline,
            accessibilityLabel: "x_i",
            payload: .svg("<svg>x_i</svg>")
        )
        let unavailable = MathRenderResult(
            latex: "x_i",
            mode: .inline,
            accessibilityLabel: "x_i",
            payload: .unavailable(reason: "missing render-svg")
        )

        let fallbackSignature = ReaderAttributedTextSignature.make(
            markdown: "Readable $x_i$.",
            font: .body,
            citationResolver: .empty,
            bibliographyLines: [],
            selectedCitationEntryId: nil,
            mathResults: ["x_i": plain]
        )
        let svgSignature = ReaderAttributedTextSignature.make(
            markdown: "Readable $x_i$.",
            font: .body,
            citationResolver: .empty,
            bibliographyLines: [],
            selectedCitationEntryId: nil,
            mathResults: ["x_i": svg]
        )
        let unavailableSignature = ReaderAttributedTextSignature.make(
            markdown: "Readable $x_i$.",
            font: .body,
            citationResolver: .empty,
            bibliographyLines: [],
            selectedCitationEntryId: nil,
            mathResults: ["x_i": unavailable]
        )

        XCTAssertNotEqual(fallbackSignature, svgSignature)
        XCTAssertNotEqual(fallbackSignature, unavailableSignature)
        XCTAssertNotEqual(svgSignature, unavailableSignature)
    }

    func testAttributedTextSignatureTracksFullSVGPayloadChangesBeyondSharedPrefix() {
        let sharedPrefix = String(repeating: "p", count: 128)
        let firstSVG = "<svg>\(sharedPrefix)a</svg>"
        let secondSVG = "<svg>\(sharedPrefix)b</svg>"

        XCTAssertEqual(firstSVG.count, secondSVG.count)
        XCTAssertEqual(firstSVG.prefix(96), secondSVG.prefix(96))
        XCTAssertNotEqual(
            ReaderAttributedTextSignature.make(
                markdown: "Readable $x_i$.",
                font: .body,
                citationResolver: .empty,
                bibliographyLines: [],
                selectedCitationEntryId: nil,
                mathResults: [
                    "x_i": MathRenderResult(
                        latex: "x_i",
                        mode: .inline,
                        accessibilityLabel: "x_i",
                        payload: .svg(firstSVG)
                    )
                ]
            ),
            ReaderAttributedTextSignature.make(
                markdown: "Readable $x_i$.",
                font: .body,
                citationResolver: .empty,
                bibliographyLines: [],
                selectedCitationEntryId: nil,
                mathResults: [
                    "x_i": MathRenderResult(
                        latex: "x_i",
                        mode: .inline,
                        accessibilityLabel: "x_i",
                        payload: .svg(secondSVG)
                    )
                ]
            )
        )
    }

    func testAttributedTextSignatureStaysBoundedForDenseReaderInput() {
        let longMarkdown = (0..<500)
            .map { "Paragraph \($0) uses $x_{\($0)}$ and cites \\citep{smith\($0)}." }
            .joined(separator: "\n")
        let mathResults = Dictionary(
            uniqueKeysWithValues: (0..<500).map { index in
                (
                    "x_\(index)",
                    MathRenderResult(
                        latex: "x_\(index)",
                        mode: .inline,
                        accessibilityLabel: "x_\(index)",
                        payload: .svg("<svg>\(String(repeating: "x", count: 2_048))\(index)</svg>")
                    )
                )
            }
        )

        let signature = ReaderAttributedTextSignature.make(
            markdown: longMarkdown,
            font: .body,
            citationResolver: .empty,
            bibliographyLines: [],
            selectedCitationEntryId: nil,
            mathResults: mathResults
        )

        XCTAssertTrue(signature.hasPrefix("reader-attributed:v2:"))
        XCTAssertLessThanOrEqual(signature.count, 86)
        XCTAssertFalse(signature.contains("Paragraph 499"))
        XCTAssertFalse(signature.contains("<svg>"))
    }

    func testInlineMathUsesResidentRatexCacheForInitialAttributedString() async {
        let latex = "x_{resident}"
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="31" height="11"><rect width="31" height="11"/></svg>"#
        let options = ReaderMathRenderOptions.options(
            fontSize: 16,
            colorScheme: .light,
            timeoutSeconds: 4
        )
        let key = RatexRenderCacheKey(
            latex: latex,
            layoutMode: .inline,
            options: options
        )
        let result = MathRenderResult(
            latex: latex,
            mode: .inline,
            accessibilityLabel: latex,
            payload: .svg(svg)
        )
        ReaderAttributedStringCache.removeAllForTesting()
        RatexSVGImageCache.removeAllImagesForTesting()
        InlineMathAttachmentFactory.removeAllImagesForTesting()
        defer {
            ReaderAttributedStringCache.removeAllForTesting()
            RatexSVGImageCache.removeAllImagesForTesting()
            InlineMathAttachmentFactory.removeAllImagesForTesting()
        }

        RatexRenderCacheStore.shared.store(result, for: key)
        _ = await InlineMathAttachmentFactory.preheat(
            svg: svg,
            baseFont: NSFont.systemFont(ofSize: 16, weight: .regular)
        )
        let attributed = SelectableInlineMarkupView(
            markdown: "Readable $\(latex)$ now.",
            font: .body
        )
        .attributedStringForTesting()

        XCTAssertFalse(attributed.string.contains("$\(latex)$"))
        XCTAssertEqual(
            attributed.attribute(.bilinInlineMathLatex, at: "Readable ".count, effectiveRange: nil) as? String,
            latex
        )
    }

    func testInlineMathUnavailableFallbackKeepsLatexSemanticAttributeAndWarningState() {
        let latex = "x_{\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))}"
        let reason = "render-svg not found"
        let options = ReaderMathRenderOptions.options(
            fontSize: 16,
            colorScheme: .light,
            timeoutSeconds: 4
        )
        let key = RatexRenderCacheKey(
            latex: latex,
            layoutMode: .inline,
            options: options
        )
        let result = MathRenderResult(
            latex: latex,
            mode: .inline,
            accessibilityLabel: latex,
            payload: .unavailable(reason: reason)
        )
        ReaderAttributedStringCache.removeAllForTesting()
        RatexSVGImageCache.removeAllImagesForTesting()
        InlineMathAttachmentFactory.removeAllImagesForTesting()
        defer {
            ReaderAttributedStringCache.removeAllForTesting()
            RatexSVGImageCache.removeAllImagesForTesting()
            InlineMathAttachmentFactory.removeAllImagesForTesting()
        }

        RatexRenderCacheStore.shared.store(result, for: key)
        let attributed = SelectableInlineMarkupView(
            markdown: "Readable $\(latex)$ now.",
            font: .body
        )
        .attributedStringForTesting()
        let formulaRange = (attributed.string as NSString).range(of: "$\(latex)$")

        XCTAssertNotEqual(formulaRange.location, NSNotFound)
        XCTAssertEqual(attributed.string, "Readable $\(latex)$ now.")
        XCTAssertNil(attributed.attribute(.attachment, at: formulaRange.location, effectiveRange: nil))
        XCTAssertEqual(
            attributed.attribute(.bilinInlineMathLatex, at: formulaRange.location, effectiveRange: nil) as? String,
            latex
        )
        XCTAssertEqual(
            attributed.attribute(.bilinInlineMathUnavailableReason, at: formulaRange.location, effectiveRange: nil) as? String,
            reason
        )
        XCTAssertTrue(
            (attributed.attribute(NSAttributedString.Key("NSToolTip"), at: formulaRange.location, effectiveRange: nil) as? String)?
                .contains(reason) == true
        )
    }

    func testAttributedTextSignatureTracksCitationResolverChanges() {
        let firstResolver = ReaderCitationResolver(entries: [
            ReaderCitationEntry(
                id: "smith2024",
                label: "Smith 2024",
                title: "First title",
                rawText: "Smith. First title.",
                sourceBlockUid: "bib",
                sourceStructuralPath: "99999"
            )
        ])
        let secondResolver = ReaderCitationResolver(entries: [
            ReaderCitationEntry(
                id: "smith2024",
                label: "Smith 2024",
                title: "Second title",
                rawText: "Smith. Second title.",
                sourceBlockUid: "bib",
                sourceStructuralPath: "99999"
            )
        ])

        XCTAssertNotEqual(
            ReaderAttributedTextSignature.make(
                markdown: "Prior work \\citep{smith2024}.",
                font: .body,
                citationResolver: firstResolver,
                bibliographyLines: [],
                selectedCitationEntryId: nil,
                mathResults: [:]
            ),
            ReaderAttributedTextSignature.make(
                markdown: "Prior work \\citep{smith2024}.",
                font: .body,
                citationResolver: secondResolver,
                bibliographyLines: [],
                selectedCitationEntryId: nil,
                mathResults: [:]
            )
        )
    }

    func testReaderMathRenderOptionsUseReadableForegroundForColorScheme() {
        XCTAssertEqual(
            ReaderMathRenderOptions.options(
                fontSize: 16,
                colorScheme: .light,
                timeoutSeconds: 4
            ).foregroundColor,
            "#111111"
        )
        XCTAssertEqual(
            ReaderMathRenderOptions.options(
                fontSize: 16,
                colorScheme: .dark,
                timeoutSeconds: 4
            ).foregroundColor,
            "#f2f2f2"
        )
    }

    func testReaderMathRenderCacheKeySeparatesLightAndDarkForeground() {
        let lightOptions = ReaderMathRenderOptions.options(
            fontSize: 16,
            colorScheme: .light,
            timeoutSeconds: 4
        )
        let darkOptions = ReaderMathRenderOptions.options(
            fontSize: 16,
            colorScheme: .dark,
            timeoutSeconds: 4
        )

        XCTAssertNotEqual(
            RatexRenderCacheKey(
                latex: "x_i",
                layoutMode: .inline,
                options: lightOptions,
                rendererIdentifier: "test-renderer"
            ),
            RatexRenderCacheKey(
                latex: "x_i",
                layoutMode: .inline,
                options: darkOptions,
                rendererIdentifier: "test-renderer"
            )
        )
    }

    func testEquationBlockRenderStateTracksFullRenderKeyNotOnlyLatex() {
        let lightKey = RatexRenderCacheKey(
            latex: "x_i",
            layoutMode: .block,
            options: ReaderMathRenderOptions.options(
                fontSize: 18,
                colorScheme: .light,
                timeoutSeconds: 5
            ),
            rendererIdentifier: "test-renderer"
        )
        let darkKey = RatexRenderCacheKey(
            latex: "x_i",
            layoutMode: .block,
            options: ReaderMathRenderOptions.options(
                fontSize: 18,
                colorScheme: .dark,
                timeoutSeconds: 5
            ),
            rendererIdentifier: "test-renderer"
        )
        let result = MathRenderResult(
            latex: "x_i",
            mode: .display,
            accessibilityLabel: "x_i",
            payload: .svg("<svg>x_i</svg>")
        )
        var state = EquationBlockRenderState()

        state.store(result, for: lightKey)

        XCTAssertEqual(state.result(for: lightKey), result)
        XCTAssertNil(state.result(for: darkKey))
        state.prepareForLoad(key: darkKey)
        XCTAssertNil(state.result(for: lightKey))
    }

    func testInlineMathRenderQueueDeduplicatesAndSkipsRenderedLatex() {
        let runs = ReaderInlineRunCache.runs(in: "Readable $x_i$ plus $x_i$ and $y_j$.")

        XCTAssertEqual(
            ReaderInlineMathRenderQueue.latexValues(in: runs),
            ["x_i", "y_j"]
        )
        XCTAssertEqual(
            ReaderInlineMathRenderQueue.pendingLatexValues(
                in: runs,
                renderedLatex: ["x_i"]
            ),
            ["y_j"]
        )
    }

    func testInlineMathRenderTaskSignatureIgnoresNonMathMarkdownChanges() {
        let firstRuns = ReaderInlineRunCache.runs(in: "Readable $x_i$ text.")
        let secondRuns = ReaderInlineRunCache.runs(in: "Different prose $x_i$ text.")
        let changedMathRuns = ReaderInlineRunCache.runs(in: "Readable $y_i$ text.")
        let options = ReaderMathRenderOptions.options(
            fontSize: 16,
            colorScheme: .light,
            timeoutSeconds: 4
        )

        XCTAssertEqual(
            ReaderInlineMathRenderQueue.taskSignature(
                latexValues: ReaderInlineMathRenderQueue.latexValues(in: firstRuns),
                renderOptions: options
            ),
            ReaderInlineMathRenderQueue.taskSignature(
                latexValues: ReaderInlineMathRenderQueue.latexValues(in: secondRuns),
                renderOptions: options
            )
        )
        XCTAssertNotEqual(
            ReaderInlineMathRenderQueue.taskSignature(
                latexValues: ReaderInlineMathRenderQueue.latexValues(in: firstRuns),
                renderOptions: options
            ),
            ReaderInlineMathRenderQueue.taskSignature(
                latexValues: ReaderInlineMathRenderQueue.latexValues(in: changedMathRuns),
                renderOptions: options
            )
        )
    }

    func testInlineMathRenderQueueDropsStaleMathResultsOutsideCurrentMarkdown() {
        let current = MathRenderResult(
            latex: "x_i",
            mode: .inline,
            accessibilityLabel: "x_i",
            payload: .svg(#"<svg xmlns="http://www.w3.org/2000/svg"></svg>"#)
        )
        let stale = MathRenderResult(
            latex: "z_i",
            mode: .inline,
            accessibilityLabel: "z_i",
            payload: .svg(#"<svg xmlns="http://www.w3.org/2000/svg"></svg>"#)
        )

        let results = ReaderInlineMathRenderQueue.currentMathResults(
            [
                "x_i": current,
                "z_i": stale
            ],
            latexValues: ["x_i", "y_i"]
        )

        XCTAssertEqual(Set(results.keys), Set(["x_i"]))
        XCTAssertEqual(results["x_i"]?.latex, "x_i")
    }

    func testInlineMathRenderQueueCommitsOnlyFullOrFinalBatches() {
        XCTAssertFalse(
            ReaderInlineMathRenderQueue.shouldCommitRenderedBatch(
                count: ReaderInlineMathRenderQueue.stateCommitBatchSize - 1,
                isLast: false
            )
        )
        XCTAssertTrue(
            ReaderInlineMathRenderQueue.shouldCommitRenderedBatch(
                count: ReaderInlineMathRenderQueue.stateCommitBatchSize,
                isLast: false
            )
        )
        XCTAssertTrue(
            ReaderInlineMathRenderQueue.shouldCommitRenderedBatch(
                count: 1,
                isLast: true
            )
        )
        XCTAssertFalse(
            ReaderInlineMathRenderQueue.shouldCommitRenderedBatch(
                count: 0,
                isLast: true
            )
        )
    }

    func testInlineMathPreheatDecodesSourceOffMainAndRasterizesOnMainThread() async {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="31" height="11"><rect width="31" height="11"/></svg>"#
        let decodedOnMainThread = LockedOptionalBool()
        var rasterizedOnMainThread: Bool?
        RatexSVGImageCache.removeAllImagesForTesting()
        InlineMathAttachmentFactory.removeAllImagesForTesting()
        RatexSVGImageCache.setDecodeThreadCheckForTesting {
            decodedOnMainThread.store(Thread.isMainThread)
        }
        InlineMathAttachmentFactory.rasterizationThreadCheckForTesting = {
            rasterizedOnMainThread = Thread.isMainThread
        }
        defer {
            RatexSVGImageCache.setDecodeThreadCheckForTesting(nil)
            RatexSVGImageCache.removeAllImagesForTesting()
            InlineMathAttachmentFactory.rasterizationThreadCheckForTesting = nil
            InlineMathAttachmentFactory.removeAllImagesForTesting()
        }

        let didPreheat = await InlineMathAttachmentFactory.preheat(
            svg: svg,
            baseFont: NSFont.systemFont(ofSize: 16, weight: .regular)
        )

        XCTAssertTrue(didPreheat)
        XCTAssertEqual(decodedOnMainThread.value, false)
        XCTAssertEqual(rasterizedOnMainThread, true)
    }

    func testInlineMathAttachmentDecodesSVGOnCacheMiss() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="31" height="11"><rect width="31" height="11"/></svg>"#
        RatexSVGImageCache.removeAllImagesForTesting()
        InlineMathAttachmentFactory.removeAllImagesForTesting()
        defer {
            RatexSVGImageCache.removeAllImagesForTesting()
            InlineMathAttachmentFactory.removeAllImagesForTesting()
        }

        XCTAssertNil(RatexSVGImageCache.cachedImage(from: svg))
        let attachment = InlineMathAttachmentFactory.cachedAttachment(
            svg: svg,
            latex: "x_i",
            baseFont: NSFont.systemFont(ofSize: 16, weight: .regular)
        )

        XCTAssertNotNil(attachment)
        XCTAssertNotNil(RatexSVGImageCache.cachedImage(from: svg))
    }

    func testBlockClipboardPayloadCopiesSemanticMarkdownForTextBlock() {
        let block = makeBlock(
            kind: .paragraph,
            markdown: "A readable paragraph with $x_i$ and \\citep{smith2024}."
        )

        XCTAssertEqual(
            ReaderBlockClipboardPayload.sourceText(for: block),
            "A readable paragraph with $x_i$ and [@smith2024]."
        )
        XCTAssertNil(ReaderBlockClipboardPayload.equationLatex(for: block))
    }

    func testBlockClipboardPayloadCopiesDisplayEquationMarkdownAndKeepsTrimmedLatex() {
        let block = makeBlock(
            kind: .equation,
            markdown: "$$x = y$$",
            latex: "  x = y  "
        )

        XCTAssertEqual(ReaderBlockClipboardPayload.sourceText(for: block), "$$\nx = y\n$$")
        XCTAssertEqual(ReaderBlockClipboardPayload.equationLatex(for: block), "x = y")
    }

    func testBlockClipboardPayloadNormalizesDelimitedEquationMarkdownFallback() {
        let block = makeBlock(
            kind: .equation,
            markdown: "  $$\nE = mc^2\n$$  "
        )

        XCTAssertEqual(ReaderBlockClipboardPayload.sourceText(for: block), "$$\nE = mc^2\n$$")
        XCTAssertEqual(ReaderBlockClipboardPayload.equationLatex(for: block), "E = mc^2")
    }

    private func makeBlock(
        kind: DocumentBlockKind,
        markdown: String,
        latex: String? = nil
    ) -> DocumentBlock {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return DocumentBlock(
            id: UUID().uuidString,
            articleRevisionId: "revision-copy-test",
            blockUid: UUID().uuidString,
            structuralPath: "00001",
            blockType: kind,
            contentHash: "hash-copy-test",
            sourceMarkdown: markdown,
            sourceLatex: latex,
            createdAt: now,
            updatedAt: now
        )
    }
}

private final class LockedOptionalBool: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool?

    var value: Bool? {
        lock.withLock { storedValue }
    }

    func store(_ value: Bool) {
        lock.withLock {
            storedValue = value
        }
    }
}
