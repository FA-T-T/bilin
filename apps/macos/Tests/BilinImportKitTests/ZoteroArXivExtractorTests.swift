import XCTest
@testable import BilinImportKit

final class ZoteroArXivExtractorTests: XCTestCase {
    func testExtractsArXivFromExtraField() {
        let metadata = ZoteroArXivExtractor.extract(
            from: [
                ("extra", "arXiv:1905.10876v2 [quant-ph]"),
                ("url", nil)
            ]
        )

        XCTAssertEqual(metadata?.identifier, "1905.10876")
        XCTAssertEqual(metadata?.version, "v2")
        XCTAssertEqual(metadata?.sourceField, "extra")
    }

    func testExtractsArXivFromURL() {
        let metadata = ZoteroArXivExtractor.extract(
            from: [
                ("extra", nil),
                ("url", "https://arxiv.org/pdf/2401.01234v3.pdf")
            ]
        )

        XCTAssertEqual(metadata?.concreteIdentifier, "2401.01234v3")
        XCTAssertEqual(metadata?.sourceField, "url")
    }
}
