import XCTest
@testable import BilinRenderKit

final class RatexSVGCLIAdapterTests: XCTestCase {
    func testRendersSVGThroughExecutable() throws {
        let executableURL = try makeFakeRenderSVGExecutable(
            body: """
            while read line; do
              test -n "$line" && break
            done
            printf '<svg xmlns="http://www.w3.org/2000/svg" data-latex="%s"></svg>' "$line"
            """
        )
        let adapter = RatexSVGCLIAdapter(executableURL: executableURL, environment: ["PATH": "/usr/bin:/bin"])

        let svg = try adapter.renderSVG(
            latex: #"E = mc^2"#,
            mode: .display,
            options: RatexRenderOptions(foregroundColor: "#1565C0", timeoutSeconds: 2)
        )

        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertTrue(svg.contains(#"data-latex="E = mc^2""#))
    }

    func testExtractsSVGWhenExecutablePrintsStatusLines() throws {
        let executableURL = try makeFakeRenderSVGExecutable(
            body: """
            while IFS= read -r line; do
              test -n "$line" && break
            done
            printf 'OK     1 %s\\n\\nWrote 1 SVG(s) to stdout\\n' "$line"
            printf '<svg xmlns="http://www.w3.org/2000/svg" data-latex="%s"></svg>\\n' "$line"
            """
        )
        let adapter = RatexSVGCLIAdapter(executableURL: executableURL, environment: ["PATH": "/usr/bin:/bin"])

        let svg = try adapter.renderSVG(
            latex: #"f(\theta)"#,
            mode: .inline,
            options: RatexRenderOptions(timeoutSeconds: 2)
        )

        XCTAssertEqual(svg, #"<svg xmlns="http://www.w3.org/2000/svg" data-latex="f(\theta)"></svg>"#)
    }

    func testThrowsWhenExecutableIsMissing() {
        let adapter = RatexSVGCLIAdapter(
            environment: [
                "PATH": temporaryDirectory().path,
                "RATEX_DISABLE_COMMON_PATH_DISCOVERY": "1"
            ]
        )

        XCTAssertThrowsError(
            try adapter.renderSVG(
                latex: "x",
                mode: .display,
                options: RatexRenderOptions(timeoutSeconds: 1)
            )
        ) { error in
            XCTAssertEqual(error as? RatexSVGCLIAdapterError, .missingExecutable)
        }
    }

    func testPassesSupportedRenderSVGArguments() throws {
        let argumentLogDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: argumentLogDirectory, withIntermediateDirectories: true)
        let argumentLogURL = argumentLogDirectory.appendingPathComponent("arguments.txt")
        let executableURL = try makeFakeRenderSVGExecutable(
            body: """
            printf '%s\\n' "$@" > "$ARGUMENT_LOG_PATH"
            printf '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
            """
        )
        let adapter = RatexSVGCLIAdapter(
            executableURL: executableURL,
            environment: [
                "ARGUMENT_LOG_PATH": argumentLogURL.path,
                "PATH": "/usr/bin:/bin"
            ]
        )

        _ = try adapter.renderSVG(
            latex: "x",
            mode: .inline,
            options: RatexRenderOptions(fontSize: 20, foregroundColor: "#1565C0", timeoutSeconds: 2)
        )

        let arguments = try String(contentsOf: argumentLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments, ["--stdout", "--font-size", "20.0", "--color", "#1565C0", "--inline"])
    }

    func testSerializesMultilineEquationAsSingleCLIFormula() throws {
        let inputLogDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: inputLogDirectory, withIntermediateDirectories: true)
        let inputLogURL = inputLogDirectory.appendingPathComponent("input.txt")
        let executableURL = try makeFakeRenderSVGExecutable(
            body: """
            cat > "$INPUT_LOG_PATH"
            printf '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
            """
        )
        let adapter = RatexSVGCLIAdapter(
            executableURL: executableURL,
            environment: [
                "INPUT_LOG_PATH": inputLogURL.path,
                "PATH": "/usr/bin:/bin"
            ]
        )

        _ = try adapter.renderSVG(
            latex: """
            \\begin{aligned}
            a &= b + c \\\\
            d &= e
            \\end{aligned}
            """,
            mode: .display,
            options: RatexRenderOptions(timeoutSeconds: 2)
        )

        let input = try String(contentsOf: inputLogURL, encoding: .utf8)
        XCTAssertEqual(input, #"\begin{aligned} a &= b + c \\ d &= e \end{aligned}"# + "\n")
    }

    func testDrainsLargeSVGOutputWhileProcessIsRunning() throws {
        let executableURL = try makeFakeRenderSVGExecutable(
            body: """
            printf '<svg xmlns="http://www.w3.org/2000/svg">'
            i=0
            while [ "$i" -lt 20000 ]; do
              printf '<text>0123456789abcdef0123456789abcdef</text>'
              i=$((i + 1))
            done
            printf '</svg>'
            """
        )
        let adapter = RatexSVGCLIAdapter(executableURL: executableURL, environment: ["PATH": "/usr/bin:/bin"])

        let svg = try adapter.renderSVG(
            latex: "x",
            mode: .display,
            options: RatexRenderOptions(timeoutSeconds: 2)
        )

        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertGreaterThan(svg.utf8.count, 900_000)
    }

    func testRendererReportsUnavailableWhenCLIIsMissing() {
        let renderer = RatexMathRenderer(
            adapter: RatexSVGCLIAdapter(
                environment: [
                    "PATH": temporaryDirectory().path,
                    "RATEX_DISABLE_COMMON_PATH_DISCOVERY": "1"
                ]
            )
        )

        let result = renderer.renderDisplay(latex: "x")

        guard case .unavailable(let reason) = result.payload else {
            return XCTFail("Expected unavailable payload")
        }
        XCTAssertTrue(reason.contains("not found"))
    }

    private func makeFakeRenderSVGExecutable(body: String) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("render-svg")
        let script = "#!/bin/sh\n\(body)\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bilin-ratex-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
