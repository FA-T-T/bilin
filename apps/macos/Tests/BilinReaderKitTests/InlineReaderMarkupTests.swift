import XCTest
@testable import BilinReaderKit

final class InlineReaderMarkupTests: XCTestCase {
    func testParsesDollarInlineMath() {
        let runs = ReaderInlineMarkupParser.runs(in: "The loss is $L(\\theta)$ after training.")

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, #"L(\theta)"#)
    }

    func testParsesSpacedDollarInlineMath() {
        let runs = ReaderInlineMarkupParser.runs(in: "We update $ \\theta_i $ with $ g $.")

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, #"\theta_i"#)
        XCTAssertEqual(runs[3].payload, "g")
    }

    func testDecodesHTMLEntitiesInDollarInlineMath() {
        let runs = ReaderInlineMarkupParser.runs(in: "Use $x &lt; y &amp; y &gt; z$ before the bound.")

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].text, "x < y & y > z")
        XCTAssertEqual(runs[1].payload, "x < y & y > z")
    }

    func testDecodesNamedAndNumericHTMLEntitiesInInlineMath() {
        let runs = ReaderInlineMarkupParser.runs(in: "Use $&#x03B1;&nbsp;&ndash;&nbsp;&#946;$ before the bound.")

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].text, "α – β")
        XCTAssertEqual(runs[1].payload, "α – β")
    }

    func testParsesNumericDollarInlineMathConstants() {
        let runs = ReaderInlineMarkupParser.runs(in: "Dropout uses probability $0.5$ during training.")

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, "0.5")
    }

    func testParsesEscapedParenthesizedMath() {
        let runs = ReaderInlineMarkupParser.runs(in: #"We use \(\alpha + \beta\) here."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, #"\alpha + \beta"#)
    }

    func testDecodesHTMLEntitiesInEscapedParenthesizedMath() {
        let runs = ReaderInlineMarkupParser.runs(in: #"Use \(x &lt; y\) before the bound."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, "x < y")
    }

    func testParsesLatexmlInlineMathTags() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"The encoder maps <math display="inline" alttext="\mathbf{z}=(z_1,\ldots,z_n)"><mi>z</mi></math> forward."#
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, #"\mathbf{z}=(z_1,\ldots,z_n)"#)
    }

    func testParsesLatexmlInlineMathHTMLAttributes() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"<math display="inline" alttext="d^{\prime}&lt;d"></math> is constrained."#
        )

        XCTAssertEqual(runs.map(\.kind), [.inlineMath, .text])
        XCTAssertEqual(runs[0].payload, #"d^{\prime}<d"#)
    }

    func testParsesLatexmlClassedSpanMath() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"The ratio <span class="ltx_Math" alttext="R_{\max}"><span>Rmax</span></span> controls the bound."#
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, #"R_{\max}"#)
        XCTAssertEqual(runs.map(\.text).joined(), #"The ratio R_{\max} controls the bound."#)
    }

    func testParsesPandocInlineMathSpan() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"The estimator <span class="math inline" data-latex="\hat{x}_i">x̂</span> is unbiased."#
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, #"\hat{x}_i"#)
        XCTAssertEqual(runs.map(\.text).joined(), #"The estimator \hat{x}_i is unbiased."#)
    }

    func testParsesKatexAnnotationMath() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"The state <span class="katex"><span class="katex-mathml"><math><semantics><annotation encoding="application/x-tex">\psi_\theta</annotation></semantics></math></span><span class="katex-html">ψ</span></span> is normalized."#
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, #"\psi_\theta"#)
    }

    func testParsesMathJaxScriptInlineMath() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"Let <script type="math/tex">z_i = f_\theta(x_i)</script> be the embedding."#
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .inlineMath, .text])
        XCTAssertEqual(runs[1].payload, #"z_i = f_\theta(x_i)"#)
    }

    func testIgnoresDisplayMathJaxScriptInInlineParser() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"Before <script type="math/tex; mode=display">\sum_i x_i</script> after."#
        )

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.kind, .text)
    }

    func testDoesNotTreatCurrencyAsMath() {
        let runs = ReaderInlineMarkupParser.runs(in: "The fee is $ 10 and the gain is $5 without close.")

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.kind, .text)
    }

    func testParsesMarkdownCitations() {
        let runs = ReaderInlineMarkupParser.runs(in: "Prior work [@ba2016; @mcclean2018] observed this.")

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[ba2016; mcclean2018]")
        XCTAssertEqual(runs[1].payload, "ba2016,mcclean2018")
    }

    func testParsesCiteCommands() {
        let runs = ReaderInlineMarkupParser.runs(in: #"See \citep{ba2016,mcclean2018}."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].payload, "ba2016,mcclean2018")
    }

    func testParsesCiteCommandsWithOptionalArguments() {
        let runs = ReaderInlineMarkupParser.runs(in: #"See \citep[section 2][eq. 4]{ba2016}."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].payload, "ba2016")
    }

    func testParsesStarredAndBiblatexCiteCommands() {
        let starred = ReaderInlineMarkupParser.runs(in: #"See \citep*{ba2016} and \autocite{mcclean2018}."#)

        XCTAssertEqual(starred.map(\.kind), [.text, .citation, .text, .citation, .text])
        XCTAssertEqual(starred[1].payload, "ba2016")
        XCTAssertEqual(starred[3].payload, "mcclean2018")
    }

    func testParsesCapitalizedAndPluralBiblatexCiteCommands() {
        let runs = ReaderInlineMarkupParser.runs(in: #"See \Citep{ba2016}, \parencites{mcclean2018}{schuld2019}, and \fullcite{lloyd2020}."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text, .citation, .text, .citation, .text])
        XCTAssertEqual(runs[1].payload, "ba2016")
        XCTAssertEqual(runs[3].payload, "mcclean2018,schuld2019")
        XCTAssertEqual(runs[5].payload, "lloyd2020")
    }

    func testParsesPluralBiblatexCiteCommandsWithPerGroupOptionalNotes() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"See \parencites[chapter 2][eq. 4]{ba2016}[appendix][table 1]{mcclean2018}."#
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[ba2016; mcclean2018]")
        XCTAssertEqual(runs[1].payload, "ba2016,mcclean2018")
    }

    func testParsesBibliographyMarkdownLink() {
        let runs = ReaderInlineMarkupParser.runs(in: "This follows [12](#bib.ba2016).")

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[12]")
        XCTAssertEqual(runs[1].payload, "#bib.ba2016")
    }

    func testParsesBibDashBibliographyMarkdownLink() {
        let runs = ReaderInlineMarkupParser.runs(in: "This follows [1](#bib-layernorm).")

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[1]")
        XCTAssertEqual(runs[1].payload, "#bib-layernorm")
    }

    func testNormalizesPathQualifiedBibliographyMarkdownLink() {
        let runs = ReaderInlineMarkupParser.runs(in: "This follows [12](paper.html#bib.ba2016).")

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[12]")
        XCTAssertEqual(runs[1].payload, "#bib.ba2016")
    }

    func testParsesLatexmlCiteLinks() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"Most models cite <cite class="ltx_cite">[<a href="#bib:vaswani2017">5</a>, <a href="#bib.bib2">2</a>]</cite>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[5, 2]")
        XCTAssertEqual(runs[1].payload, "#bib:vaswani2017,#bib.bib2")
    }

    func testNormalizesPathQualifiedLatexmlCiteLinks() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"Most models cite <cite class="ltx_cite">[<a href="paper.html#bib:vaswani2017">5</a>, <a href="../refs.html#bib.bib2">2</a>]</cite>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[5, 2]")
        XCTAssertEqual(runs[1].payload, "#bib:vaswani2017,#bib.bib2")
    }

    func testNormalizesPathQualifiedLatexmlAnchorCitation() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"The method follows <a href="paper.html#bib.bib7" class="ltx_ref">7</a>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[7]")
        XCTAssertEqual(runs[1].payload, "#bib.bib7")
    }

    func testParsesLatexmlMissingCitationSpans() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"VQE <cite class="ltx_cite">[<span class="ltx_ref ltx_missing_citation">peruzzo2014</span>, <span class="ltx_ref ltx_missing_citation">mcclean2016</span>]</cite>."#
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[peruzzo2014, mcclean2016]")
        XCTAssertEqual(runs[1].payload, "peruzzo2014,mcclean2016")
    }

    func testParsesLatexmlBibrefCitations() {
        let runs = ReaderInlineMarkupParser.runs(
            in: #"See <cite class="ltx_citemacro_cite">[<bibref bibrefs="church-turing,feynman" separator=","/>]</cite> for background."#
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[church-turing; feynman]")
        XCTAssertEqual(runs[1].payload, "church-turing,feynman")
    }

    func testParsesLatexmlCitemacroSpanCitations() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"See <span class="ltx_citemacro_citep">[<a href="#bib:vaswani2017">5</a>, <a href="#bib.bib2">2</a>]</span>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[5, 2]")
        XCTAssertEqual(runs[1].payload, "#bib:vaswani2017,#bib.bib2")
    }

    func testParsesCiteTagsWithDataCites() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"This follows <cite data-cites="smith2024 mcclean2018">(Smith 2024; McClean 2018)</cite>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "(Smith 2024; McClean 2018)")
        XCTAssertEqual(runs[1].payload, "smith2024,mcclean2018")
    }

    func testParsesPandocCSLCitationSpan() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"This follows <span class="citation" data-cites="smith2024 mcclean2018">(<a href="#ref-smith2024">Smith 2024</a>; <a href="#ref-mcclean2018">McClean 2018</a>)</span>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "(Smith 2024; McClean 2018)")
        XCTAssertEqual(runs[1].payload, "smith2024,mcclean2018")
    }

    func testParsesSingularDataCiteCitationSpan() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"This follows <span class="citation" data-cite="smith2024">Smith 2024</span>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "Smith 2024")
        XCTAssertEqual(runs[1].payload, "smith2024")
    }

    func testParsesLatexmlSpanCiteLinks() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"Most models cite <span class="ltx_cite">[<a href="#bib:vaswani2017">5</a>, <a href="#bib.bib2">2</a>]</span>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[5, 2]")
        XCTAssertEqual(runs[1].payload, "#bib:vaswani2017,#bib.bib2")
    }

    func testDecodesNamedAndNumericHTMLEntitiesInCitationText() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"This follows <span class="citation" data-cites="smith2024">Smith&nbsp;&#x2013;&nbsp;2024</span>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "Smith – 2024")
        XCTAssertEqual(runs[1].payload, "smith2024")
    }

    func testEscapedHTMLCitationTagStaysLiteralText() {
        let markdown = #"This keeps \<span class="citation" data-cites="smith2024">Smith 2024</span> as text."#
        let runs = ReaderInlineMarkupParser.runs(in: markdown)

        XCTAssertEqual(runs.map(\.kind), [.text])
        XCTAssertEqual(runs[0].text, markdown)
    }

    func testParsesPandocCitationSpanWithoutDataCitesFromRefLinks() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"This follows <span class="citation">(<a href="#ref-smith2024">Smith 2024</a>)</span>."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "(Smith 2024)")
        XCTAssertEqual(runs[1].payload, "#ref-smith2024")
    }

    func testParsesBibliographyMarkdownLinkWithTitle() {
        let runs = ReaderInlineMarkupParser.runs(in: #"This follows [1](#bib.bib1 "Reference title")."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[1]")
        XCTAssertEqual(runs[1].payload, "#bib.bib1")
    }

    func testParsesAdjacentBibliographyMarkdownLink() {
        let runs = ReaderInlineMarkupParser.runs(in: #"Sorted Insertion (SI)[14](#bib.bib14 "") is efficient."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[14]")
        XCTAssertEqual(runs[1].payload, "#bib.bib14")
    }

    func testParsesBibitemMarkdownLinkAsCitation() {
        let runs = ReaderInlineMarkupParser.runs(in: #"This follows [14](#bibitem.ba2016 "Reference")."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[14]")
        XCTAssertEqual(runs[1].payload, "#bibitem.ba2016")
    }

    func testParsesEscapedBracketBibliographyMarkdownLinkAsCitation() {
        let runs = ReaderInlineMarkupParser.runs(in: #"This follows [\[1\]](#bib.bib1) in the proof."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[1]")
        XCTAssertEqual(runs[1].payload, "#bib.bib1")
        XCTAssertEqual(runs.map(\.text).joined(), "This follows [1] in the proof.")
    }

    func testParsesLocalEquationReferenceAsCrossReferenceNotCitation() {
        let runs = ReaderInlineMarkupParser.runs(in: #"See ([6](#S2.E6 "In 2.2.2 Finite Differences")) for the estimator."#)

        XCTAssertEqual(runs.map(\.kind), [.text, .crossReference, .text])
        XCTAssertEqual(runs[1].text, "6")
        XCTAssertEqual(runs[1].payload, "#S2.E6")
        XCTAssertEqual(runs.map(\.text).joined(), "See (6) for the estimator.")
    }

    func testParsesLatexmlAnchorAsCrossReference() {
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"See (<a href="#Ch7.E14" class="ltx_ref"><span>7.14</span></a>) for the constraint."##
        )

        XCTAssertEqual(runs.map(\.kind), [.text, .crossReference, .text])
        XCTAssertEqual(runs[1].text, "7.14")
        XCTAssertEqual(runs[1].payload, "#Ch7.E14")
    }

    func testParsesNonBibliographyMarkdownLinkAsCrossReference() {
        let runs = ReaderInlineMarkupParser.runs(in: "Open [arXiv](https://arxiv.org/abs/1234.5678).")

        XCTAssertEqual(runs.map(\.kind), [.text, .crossReference, .text])
        XCTAssertEqual(runs[1].text, "arXiv")
        XCTAssertEqual(runs[1].payload, "https://arxiv.org/abs/1234.5678")
    }

    func testParsesNumericBracketCitations() {
        let runs = ReaderInlineMarkupParser.runs(in: "Prior work [12, 14-16] observed this.")

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[12, 14-16]")
        XCTAssertEqual(runs[1].payload, "12, 14-16")
    }

    func testParsesNumericBracketCitationsWithEnDash() {
        let runs = ReaderInlineMarkupParser.runs(in: "Prior work [12, 14–16] observed this.")

        XCTAssertEqual(runs.map(\.kind), [.text, .citation, .text])
        XCTAssertEqual(runs[1].text, "[12, 14–16]")
        XCTAssertEqual(runs[1].payload, "12, 14–16")
    }
}
