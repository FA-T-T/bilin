import XCTest
@testable import BilinReaderKit

final class ReaderFixtureLoaderTests: XCTestCase {
    func testLoadsPrototypeFixture() throws {
        let fixture = try ReaderFixtureLoader().loadFixture(named: "prototype-article", bundle: .module)

        XCTAssertEqual(fixture.library.id, "library-1")
        XCTAssertEqual(fixture.article.activeRevisionId, "revision-1")
        XCTAssertEqual(fixture.blocks.first?.blockType, .title)
        XCTAssertEqual(fixture.blocks.count, 2)
    }
}
