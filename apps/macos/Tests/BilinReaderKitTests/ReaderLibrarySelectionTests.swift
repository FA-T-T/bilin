import XCTest
@testable import BilinReaderKit

final class ReaderLibrarySelectionTests: XCTestCase {
    func testArticleSelectionExposesOnlyArticleId() {
        let selection = ReaderLibrarySelection.article(id: "article-1")

        XCTAssertEqual(selection.articleId, "article-1")
        XCTAssertNil(selection.zoteroItemId)
    }

    func testZoteroSelectionExposesOnlyZoteroItemId() {
        let selection = ReaderLibrarySelection.zoteroItem(id: 42)

        XCTAssertNil(selection.articleId)
        XCTAssertEqual(selection.zoteroItemId, 42)
    }

    func testCodableRoundTripPreservesSelectionKind() throws {
        let selections: [ReaderLibrarySelection] = [
            .article(id: "article-1"),
            .zoteroItem(id: 42)
        ]

        let data = try JSONEncoder().encode(selections)
        let decoded = try JSONDecoder().decode([ReaderLibrarySelection].self, from: data)

        XCTAssertEqual(decoded, selections)
    }

    func testArticleAndZoteroSelectionsRemainDistinctForListTags() {
        let selections: Set<ReaderLibrarySelection> = [
            .article(id: "42"),
            .zoteroItem(id: 42)
        ]

        XCTAssertTrue(selections.contains(.article(id: "42")))
        XCTAssertTrue(selections.contains(.zoteroItem(id: 42)))
        XCTAssertEqual(selections.count, 2)
    }
}
