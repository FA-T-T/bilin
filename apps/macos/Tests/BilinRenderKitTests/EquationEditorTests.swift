import XCTest
@testable import BilinRenderKit

final class EquationEditorTests: XCTestCase {
    func testExportsRawLatexByDefault() {
        let export = EquationEditorExportBuilder.exportString(
            latex: " E = mc^2 ",
            options: EquationEditorOptions()
        )

        XCTAssertEqual(export, "E = mc^2")
    }

    func testExportsRatexHTMLContainer() {
        var options = EquationEditorOptions()
        options.exportTarget = .html
        options.layoutMode = .inline

        let export = EquationEditorExportBuilder.exportString(
            latex: #"x < y & y > z"#,
            options: options
        )

        XCTAssertEqual(
            export,
            #"<span class="bilin-math" data-renderer="ratex" data-mode="inline">x &lt; y &amp; y &gt; z</span>"#
        )
    }

    func testExportsRatexURLWithOptions() {
        var options = EquationEditorOptions()
        options.exportTarget = .url
        options.imageFormat = .png
        options.displaySize = .pt18
        options.dpi = .dpi300
        options.color = .blue

        let export = EquationEditorExportBuilder.exportString(
            latex: #"\frac{a}{b}"#,
            options: options
        )

        XCTAssertTrue(export.hasPrefix("ratex://render?format=png&size=18&dpi=300&color=blue&mode=block&latex="))
        XCTAssertTrue(export.contains("%5Cfrac%7Ba%7D%7Bb%7D"))
    }

    func testDetectsBraceMismatch() {
        let diagnostics = EquationSyntaxInspector.diagnostics(for: #"\frac{a}{b"#)

        XCTAssertEqual(diagnostics, ["Brace mismatch: 2 open, 1 close"])
    }

    func testSuggestsCommandsFromPrefix() {
        let suggestions = EquationSyntaxInspector.suggestions(for: #"\alp"#)

        XCTAssertEqual(suggestions.first?.latex, #"\alpha"#)
    }

    func testTemplateInsertionTargetsFirstEmptyPlaceholder() throws {
        let fraction = try XCTUnwrap(
            EquationTemplateCatalog.groups
                .first { $0.id == "structure" }?
                .templates
                .first { $0.id == "frac" }
        )
        let result = EquationTemplateInsertionPlanner.insert(
            fraction,
            into: "E = ",
            selection: EquationTextSelection(location: 4, length: 0)
        )

        XCTAssertEqual(result.latex, #"E = \frac{}{}"#)
        XCTAssertEqual(
            result.selection,
            EquationTextSelection(location: #"E = \frac{"#.utf16.count, length: 0)
        )
    }

    func testTemplateInsertionWrapsSelectedTextAndTargetsNextPlaceholder() throws {
        let fraction = try XCTUnwrap(
            EquationTemplateCatalog.groups
                .first { $0.id == "structure" }?
                .templates
                .first { $0.id == "frac" }
        )
        let result = EquationTemplateInsertionPlanner.insert(
            fraction,
            into: "x",
            selection: EquationTextSelection(location: 0, length: 1)
        )

        XCTAssertEqual(result.latex, #"\frac{x}{}"#)
        XCTAssertEqual(
            result.selection,
            EquationTextSelection(location: #"\frac{x}{"#.utf16.count, length: 0)
        )
    }

    func testTemplateInsertionUsesCurrentCursorInsteadOfAppending() throws {
        let alpha = try XCTUnwrap(
            EquationTemplateCatalog.groups
                .first { $0.id == "greek" }?
                .templates
                .first { $0.id == "alpha" }
        )
        let result = EquationTemplateInsertionPlanner.insert(
            alpha,
            into: "a + c",
            selection: EquationTextSelection(location: 4, length: 0)
        )

        XCTAssertEqual(result.latex, #"a + \alpha c"#)
        XCTAssertEqual(
            result.selection,
            EquationTextSelection(location: #"a + \alpha"#.utf16.count, length: 0)
        )
    }

    func testStructureTemplatesUseReadablePreviewLatex() {
        let structureTemplates = EquationTemplateCatalog.groups
            .first { $0.id == "structure" }?
            .templates ?? []
        let fraction = structureTemplates.first { $0.id == "frac" }
        let power = structureTemplates.first { $0.id == "sup" }

        XCTAssertEqual(fraction?.latex, #"\frac{}{}"#)
        XCTAssertEqual(fraction?.renderedPreviewLatex, #"\frac{a}{b}"#)
        XCTAssertEqual(power?.latex, #"^{}"#)
        XCTAssertEqual(power?.renderedPreviewLatex, #"x^{2}"#)
    }

    func testLiteralTemplatesPreviewTheirInsertionLatex() {
        let greekTemplates = EquationTemplateCatalog.groups
            .first { $0.id == "greek" }?
            .templates ?? []
        let alpha = greekTemplates.first { $0.id == "alpha" }

        XCTAssertEqual(alpha?.latex, #"\alpha"#)
        XCTAssertEqual(alpha?.renderedPreviewLatex, alpha?.latex)
    }

    func testSymbolTemplatesProvideTypographicFallbackPreviews() {
        let greekTemplates = EquationTemplateCatalog.groups
            .first { $0.id == "greek" }?
            .templates ?? []
        let operatorTemplates = EquationTemplateCatalog.groups
            .first { $0.id == "operators" }?
            .templates ?? []

        XCTAssertEqual(greekTemplates.first { $0.id == "alpha" }?.renderedFallbackPreviewText, "α")
        XCTAssertEqual(operatorTemplates.first { $0.id == "times" }?.renderedFallbackPreviewText, "×")
        XCTAssertEqual(operatorTemplates.first { $0.id == "leq" }?.renderedFallbackPreviewText, "≤")
    }

    func testMatrixTemplatesProvideReadableFallbackPreviews() {
        let matrixTemplates = EquationTemplateCatalog.groups
            .first { $0.id == "matrices" }?
            .templates ?? []

        XCTAssertEqual(
            matrixTemplates.first { $0.id == "pmatrix2" }?.renderedFallbackPreviewText,
            "( a  b\n  c  d )"
        )
        XCTAssertEqual(
            matrixTemplates.first { $0.id == "aligned" }?.renderedFallbackPreviewText,
            "a = b + c\nd = e + f"
        )
    }

    func testMapsEditorOptionsToRatexRenderOptions() {
        var options = EquationEditorOptions()
        options.displaySize = .pt20
        options.color = .blue

        let renderOptions = options.ratexRenderOptions

        XCTAssertEqual(renderOptions.fontSize, 20)
        XCTAssertEqual(renderOptions.foregroundColor, "#1565C0")
    }
}
