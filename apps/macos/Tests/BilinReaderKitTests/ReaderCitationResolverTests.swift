import XCTest
@testable import BilinReaderKit

final class ReaderCitationResolverTests: XCTestCase {
    func testDerivesBibliographyEntriesFromListBlocksAndResolvesAliases() {
        let blocks = [
            makeParagraphBlock(),
            makeBibliographyBlock()
        ]

        let resolver = ReaderCitationResolver(blocks: blocks)

        let entry = resolver.resolve("#bib.bib1")
        XCTAssertEqual(entry?.id, "bib.bib1")
        XCTAssertEqual(entry?.label, "1")
        XCTAssertEqual(entry?.displayLabel, "[1]")
        XCTAssertEqual(entry?.sourceBlockUid, "lst-bib")
        XCTAssertEqual(entry?.rawText, "Smith J. Layer normalization for quantum circuits. Journal of Tests.")
        XCTAssertEqual(entry?.hasBibliographyEntry, true)
        XCTAssertEqual(resolver.resolve("bib.bib1"), entry)
        XCTAssertEqual(resolver.resolve("#bib:bib1"), entry)
        XCTAssertEqual(resolver.resolve("bib:bib1"), entry)
        XCTAssertEqual(resolver.resolve("paper.html#bib.bib1"), entry)
        XCTAssertEqual(resolver.resolve("https://example.test/paper.html#bib:bib1"), entry)
    }

    func testResolveCitationRunUsesPayloadHref() {
        let resolver = ReaderCitationResolver(blocks: [makeBibliographyBlock()])
        let runs = ReaderInlineMarkupParser.runs(in: #"See [1](#bib.bib1 "")."#)

        XCTAssertEqual(resolver.resolve(runs[1])?.rawText, "Smith J. Layer normalization for quantum circuits. Journal of Tests.")
    }

    func testResolveLatexmlMultiCitationRunUsesFirstResolvableReference() {
        let bibliography = DocumentBlock(
            id: "block-bib",
            articleRevisionId: "revision-1",
            blockUid: "lst-bib",
            structuralPath: "99999",
            blockType: .list,
            contentHash: "hash-bib",
            sourceMarkdown: """
            - [5](#bib.vaswani2017) Vaswani A. Attention is all you need. NeurIPS.
            - [2](#bib.bib2) Devlin J. BERT. NAACL.
            """,
            metadata: ["list_kind": "bibliography"],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let resolver = ReaderCitationResolver(blocks: [bibliography])
        let runs = ReaderInlineMarkupParser.runs(
            in: ##"Most models cite <cite class="ltx_cite">[<a href="#bib:vaswani2017">5</a>, <a href="#bib.bib2">2</a>]</cite>."##
        )

        let entry = resolver.resolve(runs[1])

        XCTAssertEqual(runs[1].payload, "#bib:vaswani2017,#bib.bib2")
        XCTAssertEqual(entry?.id, "bib.vaswani2017")
        XCTAssertEqual(entry?.displayLabel, "[5]")
        XCTAssertEqual(entry?.rawText, "Vaswani A. Attention is all you need. NeurIPS.")
    }

    func testFallbackEntriesSplitLatexmlMultiCitationReferences() {
        let paragraph = DocumentBlock(
            id: "block-p",
            articleRevisionId: "revision-1",
            blockUid: "p-1",
            structuralPath: "00001",
            blockType: .paragraph,
            contentHash: "hash-p",
            sourceMarkdown: ##"Most models cite <cite class="ltx_cite">[<a href="#bib:vaswani2017">5</a>, <a href="#bib.bib2">2</a>]</cite>."##,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let resolver = ReaderCitationResolver(blocks: [paragraph])

        XCTAssertEqual(resolver.resolve("#bib:vaswani2017")?.id, "bib:vaswani2017")
        XCTAssertEqual(resolver.resolve("#bib.bib2")?.id, "bib.bib2")
        XCTAssertEqual(resolver.resolve("#bib:vaswani2017")?.sourceBlockUid, "p-1")
        XCTAssertEqual(resolver.resolve("#bib.bib2")?.sourceBlockUid, "p-1")
    }

    func testDerivesEntriesFromBibliographyAnchorsWhenMetadataIsMissing() {
        let resolver = ReaderCitationResolver(blocks: [makeBibliographyBlock(metadata: [:])])

        XCTAssertEqual(resolver.resolve("#bib.bib1")?.displayLabel, "[1]")
    }

    func testBibDashAnchorsResolveAcrossBibAliases() {
        let block = DocumentBlock(
            id: "block-bibdash",
            articleRevisionId: "revision-1",
            blockUid: "lst-bib",
            structuralPath: "99999",
            blockType: .list,
            contentHash: "hash-bibdash",
            sourceMarkdown: #"- [1](#bib-layernorm) Ba J. Layer normalization. Journal of Tests."#,
            metadata: ["list_kind": "bibliography"],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let resolver = ReaderCitationResolver(blocks: [block])

        XCTAssertEqual(resolver.resolve("#bib-layernorm")?.displayLabel, "[1]")
        XCTAssertEqual(resolver.resolve("#bib.layernorm")?.rawText, "Ba J. Layer normalization. Journal of Tests.")
        XCTAssertEqual(resolver.resolve("#bib:layernorm")?.sourceBlockUid, "lst-bib")
        XCTAssertEqual(resolver.resolve("@layernorm")?.id, "bib-layernorm")
    }

    func testBibitemAnchorsResolveAcrossBibAliases() {
        let block = DocumentBlock(
            id: "block-bibitem",
            articleRevisionId: "revision-1",
            blockUid: "lst-bib",
            structuralPath: "99999",
            blockType: .list,
            contentHash: "hash-bibitem",
            sourceMarkdown: #"- [\[4\]](#bibitem.ba2016) Ba J. Layer normalization. Journal of Tests."#,
            metadata: ["list_kind": "bibliography"],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let resolver = ReaderCitationResolver(blocks: [block])

        XCTAssertEqual(resolver.resolve("#bibitem.ba2016")?.displayLabel, "[4]")
        XCTAssertEqual(resolver.resolve("#bib.ba2016")?.rawText, "Ba J. Layer normalization. Journal of Tests.")
        XCTAssertEqual(resolver.resolve("#bib:ba2016")?.sourceBlockUid, "lst-bib")
    }

    func testFallsBackToInlineCitationAnchorsWhenBibliographyEntriesAreMissing() {
        let resolver = ReaderCitationResolver(blocks: [makeParagraphBlock()])

        let entry = resolver.resolve("#bib.bib1")
        XCTAssertEqual(entry?.id, "bib.bib1")
        XCTAssertEqual(entry?.displayLabel, "[1]")
        XCTAssertEqual(entry?.sourceBlockUid, "p-1")
        XCTAssertEqual(entry?.rawText, "")
        XCTAssertEqual(entry?.hasBibliographyEntry, false)
    }

    func testDerivesFallbackEntriesFromReferenceMetadata() {
        let block = DocumentBlock(
            id: "block-p",
            articleRevisionId: "revision-1",
            blockUid: "p-1",
            structuralPath: "00001",
            blockType: .paragraph,
            contentHash: "hash-p",
            sourceMarkdown: "Metadata references can come from the web parser.",
            metadata: [
                "references": ##"[{"href":"#bib.bib7","text":"7","title":"Reference title"}]"##
            ],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let resolver = ReaderCitationResolver(blocks: [block])
        let entry = resolver.resolve("#bib.bib7")

        XCTAssertEqual(entry?.id, "bib.bib7")
        XCTAssertEqual(entry?.displayLabel, "[7]")
        XCTAssertEqual(entry?.title, "Reference title")
        XCTAssertEqual(entry?.sourceBlockUid, "p-1")
    }

    func testNumericCitationRunResolvesMetadataBibliographyEntryByLabel() {
        let paragraph = DocumentBlock(
            id: "block-p",
            articleRevisionId: "revision-1",
            blockUid: "p-1",
            structuralPath: "00001",
            blockType: .paragraph,
            contentHash: "hash-p",
            sourceMarkdown: "The estimator follows [7].",
            metadata: [
                "references": ##"[{"href":"#bib.bib7","text":"7","title":"Reference title"}]"##
            ],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let bibliography = DocumentBlock(
            id: "block-bib",
            articleRevisionId: "revision-1",
            blockUid: "lst-bib",
            structuralPath: "99999",
            blockType: .list,
            contentHash: "hash-bib",
            sourceMarkdown: #"- [\[7\]](#bib.bib7) Ada L. Reference title. Journal of Tests."#,
            metadata: ["list_kind": "bibliography"],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let resolver = ReaderCitationResolver(blocks: [paragraph, bibliography])
        let runs = ReaderInlineMarkupParser.runs(in: paragraph.sourceMarkdown)
        let citationRun = runs.first { $0.kind == .citation }

        let entry = citationRun.flatMap { resolver.resolve($0) }
        XCTAssertEqual(entry?.id, "bib.bib7")
        XCTAssertEqual(entry?.displayLabel, "[7]")
        XCTAssertEqual(entry?.rawText, "Ada L. Reference title. Journal of Tests.")
    }

    func testBibliographyLinesExposeEntriesAndStableFallbackLineIDs() {
        let block = DocumentBlock(
            id: "block-bib",
            articleRevisionId: "revision-1",
            blockUid: "lst-bib",
            structuralPath: "99999",
            blockType: .list,
            contentHash: "hash-bib",
            sourceMarkdown: """
            - [\\[1\\]](#bib.bib1) Smith J. Layer normalization for quantum circuits. Journal of Tests.

            - Unparsed bibliography note without an anchor.
            - [\\[2\\]](#bib.bib2) Ada L. Reference title. Journal of Tests.
            """,
            metadata: ["list_kind": "bibliography"],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let lines = ReaderCitationResolver.bibliographyLines(in: block)

        XCTAssertEqual(lines.map(\.id), ["bib.bib1", "lst-bib-line-2", "bib.bib2"])
        XCTAssertEqual(lines[0].entry?.displayLabel, "[1]")
        XCTAssertNil(lines[1].entry)
        XCTAssertEqual(lines[2].entry?.rawText, "Ada L. Reference title. Journal of Tests.")
    }

    func testBibliographyLinesParseBareMarkdownCitationLinks() {
        let block = DocumentBlock(
            id: "block-bib",
            articleRevisionId: "revision-1",
            blockUid: "bib-block",
            structuralPath: "99999",
            blockType: .bibliography,
            contentHash: "hash-bib",
            sourceMarkdown: #"[3](#bib.bib3) Turing A. Computing machinery. Journal of Tests."#,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let lines = ReaderCitationResolver.bibliographyLines(in: block)

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].entry?.displayLabel, "[3]")
        XCTAssertEqual(lines[0].entry?.rawText, "Turing A. Computing machinery. Journal of Tests.")
    }

    func testBibliographyLinesParseCompactLatexmlHTMLItems() {
        let block = DocumentBlock(
            id: "block-html-bib",
            articleRevisionId: "revision-1",
            blockUid: "html-bib",
            structuralPath: "99999",
            blockType: .bibliography,
            contentHash: "hash-html-bib",
            sourceMarkdown: ##"""
            <ul class="ltx_biblist"><li class="ltx_bibitem" id="bib.vaswani2017"><span class="ltx_tag ltx_tag_bibitem">[5]</span> Vaswani A. Attention is all you need. NeurIPS.</li><li class="ltx_bibitem" id="bib.bib2"><span class="ltx_tag ltx_tag_bibitem">[2]</span> Devlin J. BERT. NAACL.</li></ul>
            """##,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let lines = ReaderCitationResolver.bibliographyLines(in: block)
        let resolver = ReaderCitationResolver(blocks: [block])

        XCTAssertEqual(lines.map(\.id), ["bib.vaswani2017", "bib.bib2"])
        XCTAssertEqual(lines[0].entry?.displayLabel, "[5]")
        XCTAssertEqual(lines[0].entry?.rawText, "Vaswani A. Attention is all you need. NeurIPS.")
        XCTAssertEqual(resolver.resolve("#bib:vaswani2017")?.rawText, "Vaswani A. Attention is all you need. NeurIPS.")
        XCTAssertEqual(resolver.resolve("#bib.bib2")?.displayLabel, "[2]")
    }

    func testBibliographyLinesParsePandocCSLEntries() {
        let block = DocumentBlock(
            id: "block-csl-bib",
            articleRevisionId: "revision-1",
            blockUid: "csl-bib",
            structuralPath: "99999",
            blockType: .bibliography,
            contentHash: "hash-csl-bib",
            sourceMarkdown: ##"""
            <div id="ref-smith2024" class="csl-entry">Smith J. Agentic reading tools. Journal of Tests.</div>
            <div id="ref-mcclean2018" class="csl-entry">McClean J. Quantum machine learning. Nature.</div>
            """##,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let lines = ReaderCitationResolver.bibliographyLines(in: block)
        let resolver = ReaderCitationResolver(blocks: [block])

        XCTAssertEqual(lines.map(\.id), ["ref-smith2024", "ref-mcclean2018"])
        XCTAssertEqual(lines[0].entry?.id, "ref-smith2024")
        XCTAssertEqual(lines[0].entry?.displayLabel, "[smith2024]")
        XCTAssertEqual(lines[0].entry?.rawText, "Smith J. Agentic reading tools. Journal of Tests.")
        XCTAssertEqual(resolver.resolve("#ref-smith2024")?.rawText, "Smith J. Agentic reading tools. Journal of Tests.")
        XCTAssertEqual(resolver.resolve("smith2024")?.sourceBlockUid, "csl-bib")
        XCTAssertEqual(resolver.resolve("@mcclean2018")?.displayLabel, "[mcclean2018]")
    }

    func testPandocCitationRunResolvesCSLBibliographyEntry() {
        let paragraph = DocumentBlock(
            id: "block-p",
            articleRevisionId: "revision-1",
            blockUid: "p-1",
            structuralPath: "00001",
            blockType: .paragraph,
            contentHash: "hash-p",
            sourceMarkdown: ##"This follows <span class="citation" data-cites="smith2024">(<a href="#ref-smith2024">Smith 2024</a>)</span>."##,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let bibliography = DocumentBlock(
            id: "block-csl-bib",
            articleRevisionId: "revision-1",
            blockUid: "csl-bib",
            structuralPath: "99999",
            blockType: .bibliography,
            contentHash: "hash-csl-bib",
            sourceMarkdown: ##"<div id="ref-smith2024" class="csl-entry">Smith J. Agentic reading tools. Journal of Tests.</div>"##,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let resolver = ReaderCitationResolver(blocks: [paragraph, bibliography])
        let citationRun = ReaderInlineMarkupParser.runs(in: paragraph.sourceMarkdown)
            .first { $0.kind == .citation }

        XCTAssertEqual(citationRun?.payload, "smith2024")
        XCTAssertEqual(citationRun.flatMap { resolver.resolve($0) }?.sourceBlockUid, "csl-bib")
        XCTAssertEqual(citationRun.flatMap { resolver.resolve($0) }?.rawText, "Smith J. Agentic reading tools. Journal of Tests.")
    }

    func testHTMLBibliographyEntryDecodesNamedAndNumericEntities() {
        let paragraph = DocumentBlock(
            id: "block-p",
            articleRevisionId: "revision-1",
            blockUid: "p-1",
            structuralPath: "00001",
            blockType: .paragraph,
            contentHash: "hash-p",
            sourceMarkdown: ##"This follows <span class="citation" data-cites="smith2024">(<a href="#ref-smith2024">Smith 2024</a>)</span>."##,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let bibliography = DocumentBlock(
            id: "block-csl-bib",
            articleRevisionId: "revision-1",
            blockUid: "csl-bib",
            structuralPath: "99999",
            blockType: .bibliography,
            contentHash: "hash-csl-bib",
            sourceMarkdown: ##"<div id="ref-smith2024" class="csl-entry">Smith&nbsp;J. Agentic reading &#x2013; &#945; tools.</div>"##,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let resolver = ReaderCitationResolver(blocks: [paragraph, bibliography])
        let citationRun = ReaderInlineMarkupParser.runs(in: paragraph.sourceMarkdown)
            .first { $0.kind == .citation }

        XCTAssertEqual(citationRun.flatMap { resolver.resolve($0) }?.rawText, "Smith J. Agentic reading – α tools.")
    }

    func testLatexmlCitationRunResolvesHTMLBibliographyEntry() {
        let paragraph = DocumentBlock(
            id: "block-p",
            articleRevisionId: "revision-1",
            blockUid: "p-1",
            structuralPath: "00001",
            blockType: .paragraph,
            contentHash: "hash-p",
            sourceMarkdown: ##"Most models cite <cite class="ltx_cite">[<a href="#bib:vaswani2017">5</a>]</cite>."##,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let bibliography = DocumentBlock(
            id: "block-html-bib",
            articleRevisionId: "revision-1",
            blockUid: "html-bib",
            structuralPath: "99999",
            blockType: .bibliography,
            contentHash: "hash-html-bib",
            sourceMarkdown: ##"<li class="ltx_bibitem" id="bib.vaswani2017"><span class="ltx_tag ltx_tag_bibitem">[5]</span> Vaswani A. Attention is all you need. NeurIPS.</li>"##,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let resolver = ReaderCitationResolver(blocks: [paragraph, bibliography])
        let citationRun = ReaderInlineMarkupParser.runs(in: paragraph.sourceMarkdown)
            .first { $0.kind == .citation }

        XCTAssertEqual(citationRun.flatMap { resolver.resolve($0) }?.sourceBlockUid, "html-bib")
        XCTAssertEqual(citationRun.flatMap { resolver.resolve($0) }?.rawText, "Vaswani A. Attention is all you need. NeurIPS.")
    }

    func testBibliographyLinesAndEntriesFromBlocksStayConsistent() {
        let block = makeBibliographyBlock()

        let lineEntries = ReaderCitationResolver.bibliographyLines(in: block).compactMap(\.entry)
        let resolverEntries = ReaderCitationResolver.entries(from: [block])

        XCTAssertEqual(lineEntries, resolverEntries)
    }

    func testSignatureIsStableAcrossEntryOrderAndChangesWithEntryContent() {
        let first = ReaderCitationEntry(
            id: "smith2024",
            label: "Smith 2024",
            title: "First title",
            rawText: "Smith J. First title. Journal of Tests.",
            sourceBlockUid: "bib",
            sourceStructuralPath: "99999"
        )
        let second = ReaderCitationEntry(
            id: "mcclean2018",
            label: "McClean 2018",
            title: "Second title",
            rawText: "McClean J. Second title. Journal of Tests.",
            sourceBlockUid: "bib",
            sourceStructuralPath: "99999"
        )
        let changedSecond = ReaderCitationEntry(
            id: "mcclean2018",
            label: "McClean 2018",
            title: "Second title",
            rawText: "McClean J. Revised title. Journal of Tests.",
            sourceBlockUid: "bib",
            sourceStructuralPath: "99999"
        )

        let ordered = ReaderCitationResolver(entries: [first, second])
        let reversed = ReaderCitationResolver(entries: [second, first])
        let changed = ReaderCitationResolver(entries: [first, changedSecond])

        XCTAssertEqual(ordered.signature, reversed.signature)
        XCTAssertNotEqual(ordered.signature, changed.signature)
    }

    func testCodableRoundTripRebuildsSignature() throws {
        let resolver = ReaderCitationResolver(entries: [
            ReaderCitationEntry(
                id: "smith2024",
                label: "Smith 2024",
                title: "First title",
                rawText: "Smith J. First title. Journal of Tests.",
                sourceBlockUid: "bib",
                sourceStructuralPath: "99999"
            )
        ])

        let data = try JSONEncoder().encode(resolver)
        let decoded = try JSONDecoder().decode(ReaderCitationResolver.self, from: data)

        XCTAssertEqual(decoded.entriesByAlias, resolver.entriesByAlias)
        XCTAssertEqual(decoded.signature, resolver.signature)
        XCTAssertEqual(decoded.resolve("smith2024")?.rawText, "Smith J. First title. Journal of Tests.")
    }

    private func makeParagraphBlock() -> DocumentBlock {
        DocumentBlock(
            id: "block-p",
            articleRevisionId: "revision-1",
            blockUid: "p-1",
            structuralPath: "00001",
            blockType: .paragraph,
            contentHash: "hash-p",
            sourceMarkdown: #"See [1](#bib.bib1 "")."#,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeBibliographyBlock(metadata: [String: String] = ["list_kind": "bibliography"]) -> DocumentBlock {
        DocumentBlock(
            id: "block-bib",
            articleRevisionId: "revision-1",
            blockUid: "lst-bib",
            structuralPath: "99999",
            blockType: .list,
            contentHash: "hash-bib",
            sourceMarkdown: #"- [\[1\]](#bib.bib1) Smith J. Layer normalization for quantum circuits. Journal of Tests."#,
            metadata: metadata,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
