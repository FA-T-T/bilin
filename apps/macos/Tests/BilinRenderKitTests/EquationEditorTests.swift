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
}
