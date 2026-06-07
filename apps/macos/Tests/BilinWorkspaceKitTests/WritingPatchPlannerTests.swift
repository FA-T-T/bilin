import XCTest
@testable import BilinWorkspaceKit

final class WritingPatchPlannerTests: XCTestCase {
    private let planner = WritingPatchPlanner()
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testTypstSectionAnchorsAreDetectedAndUsedForInsertion() {
        let text = """
        = Introduction
        Some intro content.

        = Related Work
        Prior work and background.

        = Method
        Core approach.

        = Discussion
        Closing points.
        """

        let sections = planner.scanSections(in: text, fileExtension: ".typ")
        XCTAssertEqual(sections.count, 4)
        XCTAssertEqual(sections.map(\.title), [
            "Introduction",
            "Related Work",
            "Method",
            "Discussion"
        ])
        let draft = planner.planInsertion(
            sourceBlock: "this is a short patch text",
            targetSectionPreference: "Method",
            mainFileText: text,
            fileExtension: ".typ",
            targetPath: "/tmp/paper.typ",
            patchId: "patch-typ",
            now: baseDate
        )
        XCTAssertTrue(draft.anchorFound)
        XCTAssertEqual(draft.insertionMode, .sectionEnd)
        XCTAssertEqual(draft.sectionAnchor?.title, "Method")
        XCTAssertEqual(draft.sectionAnchor?.kind, "typst")
        XCTAssertEqual(draft.pendingPatch.targetSectionPath, ["Method"])
        XCTAssertEqual(draft.pendingPatch.targetAnchor, "method")
        XCTAssertNotNil(draft.insertionLine)
        XCTAssertEqual(draft.pendingPatch.previewMarkdown, draft.pendingPatch.patchText)
        XCTAssertEqual(draft.pendingPatch.format, .typst)
    }

    func testWritingPatchConvertsMarkdownCitationsForTypstAndTeX() {
        let typstDraft = planner.planInsertion(
            sourceBlock: "Prior work [@smith2024; @mcclean2018] studies $x_i$.",
            targetSectionPreference: "Method",
            mainFileText: """
            = Method
            Method body.
            """,
            fileExtension: "typ",
            targetPath: "/tmp/paper.typ",
            patchId: "patch-cite-typ",
            now: baseDate
        )
        let texDraft = planner.planInsertion(
            sourceBlock: "Prior work [@smith2024; @mcclean2018] studies $x_i$.",
            targetSectionPreference: "Method",
            mainFileText: """
            \\section{Method}
            Method body.
            """,
            fileExtension: "tex",
            targetPath: "/tmp/paper.tex",
            patchId: "patch-cite-tex",
            now: baseDate
        )

        XCTAssertTrue(typstDraft.pendingPatch.patchText.contains("Prior work @smith2024, @mcclean2018 studies $x_i$."))
        XCTAssertFalse(typstDraft.pendingPatch.patchText.contains("[@smith2024"))
        XCTAssertTrue(texDraft.pendingPatch.patchText.contains(#"Prior work \cite{smith2024,mcclean2018} studies $x_i$."#))
        XCTAssertFalse(texDraft.pendingPatch.patchText.contains("[@smith2024"))
    }

    func testTeXSectionAnchorsAreDetectedAndMethodPreferred() {
        let text = """
        \\section{Background}
        ...
        \\subsection{Background Methods}
        ...
        \\section{Method}
        ...
        \\section{Conclusion}
        """

        let sections = planner.scanSections(in: text, fileExtension: "tex")
        XCTAssertEqual(sections.count, 4)
        XCTAssertEqual(sections[2].title, "Method")
        XCTAssertEqual(sections[2].level, 2)

        let draft = planner.planInsertion(
            sourceBlock: "we propose a baseline",
            targetSectionPreference: "Method",
            mainFileText: text,
            fileExtension: "tex",
            targetPath: "/tmp/paper.tex",
            patchId: "patch-tex",
            now: baseDate
        )
        XCTAssertTrue(draft.anchorFound)
        XCTAssertEqual(draft.pendingPatch.kind, .texInsertion)
        XCTAssertEqual(draft.pendingPatch.format, .tex)
        XCTAssertEqual(draft.pendingPatch.targetSectionPath, ["Method"])
        XCTAssertTrue(draft.pendingPatch.patchText.contains("begin{quote}"))
    }

    func testBibliographyDetectionSupportsTypstAndTeX() {
        let typstMain = """
        = Method
        #bibliography("refs/main.bib", style: "apa")
        #bibliography("./assets/appendix.bib")
        """
        let typstBibs = planner.detectBibliography(in: typstMain, fileExtension: "typ")
        XCTAssertEqual(typstBibs, ["refs/main.bib", "./assets/appendix.bib"])

        let texMain = """
        \\documentclass{article}
        \\addbibresource{refs/repo}
        Text...
        \\bibliography{refs/paper,refs/appendix.bib}
        """
        let texBibs = planner.detectBibliography(in: texMain, fileExtension: "tex")
        XCTAssertEqual(texBibs, ["refs/repo.bib", "refs/paper.bib", "refs/appendix.bib"])
    }

    func testPlanInsertionFallsBackWhenPreferredAnchorMissing() {
        let text = """
        = Introduction
        = Background
        """
        let draft = planner.planInsertion(
            sourceBlock: "fallback patch",
            targetSectionPreference: "Discussion",
            mainFileText: text,
            fileExtension: "typ",
            targetPath: "/tmp/paper.typ",
            patchId: "patch-missing",
            now: baseDate
        )
        XCTAssertFalse(draft.anchorFound)
        XCTAssertEqual(draft.insertionMode, .appendToEnd)
        XCTAssertNil(draft.sectionAnchor)
        XCTAssertNil(draft.insertionLine)
        XCTAssertNil(draft.pendingPatch.targetAnchor)
        XCTAssertEqual(draft.pendingPatch.targetSectionPath, [])
    }
}
