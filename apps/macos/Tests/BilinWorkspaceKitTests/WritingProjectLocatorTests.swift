import XCTest
@testable import BilinWorkspaceKit

final class WritingProjectLocatorTests: XCTestCase {
    private let locator = WritingProjectLocator()

    func testLocatesPreferredTypstMainAndBibliographyReferences() throws {
        let rootURL = try makeTemporaryDirectory()
        let mainURL = rootURL.appendingPathComponent("main.typ")
        let paperURL = rootURL.appendingPathComponent("paper.typ")
        let directBibURL = rootURL.appendingPathComponent("refs.bib")
        try """
        = Related Work
        Prior art.
        #bibliography("refs/local.bib")
        """.write(to: mainURL, atomically: true, encoding: .utf8)
        try "= Paper".write(to: paperURL, atomically: true, encoding: .utf8)
        try "@article{seed}".write(to: directBibURL, atomically: true, encoding: .utf8)

        let location = locator.locate(rootPath: rootURL.path)

        XCTAssertEqual(location.kind, .typst)
        XCTAssertEqual(location.status, .linked)
        XCTAssertEqual(canonicalOptionalPath(location.mainFilePath), canonicalPath(mainURL.path))
        XCTAssertTrue(canonicalPaths(location.detectedFilePaths).contains(canonicalPath(mainURL.path)))
        XCTAssertTrue(canonicalPaths(location.detectedFilePaths).contains(canonicalPath(paperURL.path)))
        XCTAssertTrue(canonicalPaths(location.bibliographyFilePaths).contains(canonicalPath(directBibURL.path)))
        XCTAssertTrue(canonicalPaths(location.bibliographyFilePaths).contains(canonicalPath(rootURL.appendingPathComponent("refs/local.bib").path)))
        XCTAssertEqual(location.sectionAnchors.map(\.title), ["Related Work"])
        XCTAssertEqual(locator.mainFileText(for: location), try String(contentsOf: mainURL, encoding: .utf8))
    }

    func testLocatesPreferredTexMainBeforeFallbackFiles() throws {
        let rootURL = try makeTemporaryDirectory()
        let fallbackURL = rootURL.appendingPathComponent("draft.typ")
        let mainURL = rootURL.appendingPathComponent("main.tex")
        try "fallback".write(to: fallbackURL, atomically: true, encoding: .utf8)
        try """
        \\section{Related Work}
        Text.
        \\bibliography{refs/paper,refs/appendix}
        """.write(to: mainURL, atomically: true, encoding: .utf8)

        let location = locator.locate(rootPath: rootURL.path)

        XCTAssertEqual(location.kind, .tex)
        XCTAssertEqual(location.status, .linked)
        XCTAssertEqual(canonicalOptionalPath(location.mainFilePath), canonicalPath(mainURL.path))
        XCTAssertEqual(location.sectionAnchors.map(\.title), ["Related Work"])
        XCTAssertTrue(canonicalPaths(location.bibliographyFilePaths).contains(canonicalPath(rootURL.appendingPathComponent("refs/paper.bib").path)))
        XCTAssertTrue(canonicalPaths(location.bibliographyFilePaths).contains(canonicalPath(rootURL.appendingPathComponent("refs/appendix.bib").path)))
    }

    func testReportsMissingAndNeedsMainFileStates() throws {
        let missing = locator.locate(rootPath: "/tmp/bilin-missing-\(UUID().uuidString)")
        XCTAssertEqual(missing.status, .missing)
        XCTAssertEqual(missing.kind, .unknown)
        XCTAssertNil(missing.mainFilePath)

        let rootURL = try makeTemporaryDirectory()
        try "notes".write(to: rootURL.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let location = locator.locate(rootPath: rootURL.path)
        XCTAssertEqual(location.status, .needsMainFile)
        XCTAssertEqual(location.kind, .unknown)
        XCTAssertNil(location.mainFilePath)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WritingProjectLocatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return rootURL
    }

    private func canonicalOptionalPath(_ path: String?) -> String? {
        path?.replacingOccurrences(of: "/private/var/", with: "/var/")
    }

    private func canonicalPath(_ path: String) -> String {
        path.replacingOccurrences(of: "/private/var/", with: "/var/")
    }

    private func canonicalPaths(_ paths: [String]) -> [String] {
        paths.map(canonicalPath)
    }
}
