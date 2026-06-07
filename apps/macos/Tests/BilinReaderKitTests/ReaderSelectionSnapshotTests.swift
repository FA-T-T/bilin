import XCTest
@testable import BilinReaderKit

final class ReaderSelectionSnapshotTests: XCTestCase {
    private let captureDate = Date(timeIntervalSince1970: 1_800_010_000)
    private let modelDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testParagraphSelectionCreatesStableSourceBlockProvenance() {
        let block = makeParagraphBlock()
        let snapshot = ReaderSelectionSnapshot(
            block: block,
            article: makeArticle(),
            revision: makeRevision(),
            library: makeLibrary(),
            capturedAt: captureDate
        )
        let provenance = snapshot.makeSourceBlockProvenance()

        XCTAssertEqual(snapshot.libraryId, "library-1")
        XCTAssertEqual(snapshot.articleId, "article-1")
        XCTAssertEqual(snapshot.articleRevisionId, "revision-1")
        XCTAssertEqual(snapshot.blockUid, "p-0001")
        XCTAssertEqual(snapshot.structuralPath, "section.introduction.paragraph.1")
        XCTAssertEqual(snapshot.contentHash, "hash-p1")
        XCTAssertEqual(snapshot.contextHash, "context-p1")
        XCTAssertEqual(snapshot.sourceLanguage, "en")
        XCTAssertEqual(snapshot.capturedAt, captureDate)
        XCTAssertEqual(provenance.stableBlockAnchor, "revision-1#p-0001#hash-p1")
        XCTAssertEqual(provenance.structuralPath, "section.introduction.paragraph.1")
    }

    func testEquationSelectionHashesSourceLatexAsSelectedText() {
        let latex = #"E = mc^2"#
        let block = makeEquationBlock(sourceLatex: latex)
        let snapshot = ReaderSelectionSnapshot(
            block: block,
            article: makeArticle(),
            revision: makeRevision(),
            library: makeLibrary(),
            capturedAt: captureDate
        )
        let provenance = snapshot.sourceBlockProvenance

        XCTAssertEqual(snapshot.blockUid, "eq-0001")
        XCTAssertEqual(snapshot.contentHash, "hash-eq1")
        XCTAssertEqual(snapshot.structuralPath, "section.method.equation.1")
        XCTAssertEqual(snapshot.selectedTextHash, ReaderSelectionSnapshot.sha256TextHash(for: latex))
        XCTAssertEqual(provenance.selectedTextHash, ReaderSelectionSnapshot.sha256TextHash(for: latex))
        XCTAssertEqual(provenance.stableBlockAnchor, "revision-1#eq-0001#hash-eq1")
    }

    func testExplicitTextSelectionOverridesWholeBlockHash() {
        let selectedText = "gradient variance decays"
        let snapshot = ReaderSelectionSnapshot(
            block: makeParagraphBlock(),
            article: makeArticle(),
            revision: makeRevision(),
            library: makeLibrary(),
            selectedText: selectedText,
            capturedAt: captureDate
        )

        XCTAssertEqual(snapshot.selectedTextHash, ReaderSelectionSnapshot.sha256TextHash(for: selectedText))
        XCTAssertEqual(snapshot.sourceBlockProvenance.selectedTextHash, ReaderSelectionSnapshot.sha256TextHash(for: selectedText))
    }


    func testMissingTranslationLeavesTranslationProvenanceEmpty() {
        let snapshot = ReaderSelectionSnapshot(
            block: makeParagraphBlock(),
            article: makeArticle(),
            revision: makeRevision(),
            library: makeLibrary(),
            capturedAt: captureDate
        )
        let provenance = snapshot.sourceBlockProvenance

        XCTAssertNil(snapshot.translationId)
        XCTAssertNil(snapshot.translationLanguage)
        XCTAssertNil(snapshot.translationHash)
        XCTAssertNil(provenance.translationId)
        XCTAssertNil(provenance.translationLanguage)
        XCTAssertNil(provenance.translationHash)
    }

    func testTranslatedBlockCarriesTranslationIdentityLanguageAndHash() {
        let translation = Translation(
            id: "translation-1",
            blockId: "block-p1",
            targetLanguage: "zh-CN",
            rawMarkdown: "当梯度方差衰减时，会出现贫瘠高原。",
            isDefault: true
        )
        let snapshot = ReaderSelectionSnapshot(
            block: makeParagraphBlock(),
            translation: translation,
            article: makeArticle(),
            revision: makeRevision(),
            library: makeLibrary(),
            sourceLanguage: "en-US",
            capturedAt: captureDate
        )
        let provenance = snapshot.sourceBlockProvenance

        XCTAssertEqual(snapshot.sourceLanguage, "en-US")
        XCTAssertEqual(snapshot.translationId, "translation-1")
        XCTAssertEqual(snapshot.translationLanguage, "zh-CN")
        XCTAssertEqual(snapshot.translationHash, ReaderSelectionSnapshot.sha256TextHash(for: translation.rawMarkdown))
        XCTAssertEqual(provenance.translationId, "translation-1")
        XCTAssertEqual(provenance.translationLanguage, "zh-CN")
        XCTAssertEqual(provenance.translationHash, ReaderSelectionSnapshot.sha256TextHash(for: translation.rawMarkdown))
        XCTAssertEqual(provenance.capturedAt, captureDate)
    }

    private func makeLibrary() -> Library {
        Library(
            id: "library-1",
            name: "Reading List",
            path: "/Users/researcher/Bilin/Reading List",
            createdAt: modelDate,
            updatedAt: modelDate
        )
    }

    private func makeArticle() -> Article {
        Article(
            id: "article-1",
            libraryId: "library-1",
            source: "arxiv",
            externalId: "2401.00001",
            title: "Optimization Landscapes",
            activeRevisionId: "revision-1"
        )
    }

    private func makeRevision() -> ArticleRevision {
        ArticleRevision(
            id: "revision-1",
            articleId: "article-1",
            version: "v1",
            bundlePath: "papers/2401.00001",
            status: "ready",
            createdAt: modelDate,
            updatedAt: modelDate
        )
    }

    private func makeParagraphBlock() -> DocumentBlock {
        DocumentBlock(
            id: "block-p1",
            articleRevisionId: "revision-1",
            blockUid: "p-0001",
            structuralPath: "section.introduction.paragraph.1",
            blockType: .paragraph,
            contentHash: "hash-p1",
            contextHash: "context-p1",
            sourceMarkdown: "A barren plateau appears when gradients vanish.",
            metadata: ["source_language": "en"],
            createdAt: modelDate,
            updatedAt: modelDate
        )
    }

    private func makeEquationBlock(sourceLatex: String) -> DocumentBlock {
        DocumentBlock(
            id: "block-eq1",
            articleRevisionId: "revision-1",
            blockUid: "eq-0001",
            structuralPath: "section.method.equation.1",
            blockType: .equation,
            contentHash: "hash-eq1",
            contextHash: "context-eq1",
            sourceMarkdown: "Rendered equation fallback",
            sourceLatex: sourceLatex,
            metadata: ["equation_number": "1", "source_language": "en"],
            createdAt: modelDate,
            updatedAt: modelDate
        )
    }
}
