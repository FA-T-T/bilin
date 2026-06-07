import XCTest
@testable import BilinWorkspaceKit

final class ZoteroImportActionPlanBuilderTests: XCTestCase {
    func testBuildsArXivDownloadAndImportActionPlanFromZoteroMetadata() {
        let candidate = ZoteroImportCandidate(
            itemID: "42",
            key: "ABCD1234",
            itemType: "journalArticle",
            title: "A Zotero Paper",
            abstract: "A short abstract.",
            doi: "10.1234/example",
            url: "https://arxiv.org/abs/2401.00001",
            arxivIdentifier: "2401.00001",
            arxivVersion: "v2",
            creators: ["Ada Lovelace", "Grace Hopper"],
            collections: ["Reading Queue"],
            tags: ["ratex", "reader"],
            attachments: [
                ZoteroImportAttachmentCandidate(
                    key: "ATTACH1",
                    contentType: "application/pdf",
                    path: "storage:paper.pdf",
                    resolvedFilePath: "/tmp/Zotero/storage/ATTACH1/paper.pdf"
                )
            ]
        )

        let result = ZoteroImportActionPlanBuilder().build(
            candidate: candidate,
            localLibraryId: "local-library",
            localLibraryPath: "/tmp/bilin-library",
            zoteroLibraryPath: "/tmp/Zotero"
        )

        XCTAssertEqual(result.actionPlanDraft.kind, .downloadPaper)
        XCTAssertEqual(
            result.actionPlanDraft.requiredPermissions,
            [.network, .downloadPaper, .importLibrary, .writeLibraryBundle]
        )
        XCTAssertEqual(result.actionPlanPayload["source"], "zotero")
        XCTAssertEqual(result.actionPlanPayload["zotero_item_id"], "42")
        XCTAssertEqual(result.actionPlanPayload["zotero_key"], "ABCD1234")
        XCTAssertEqual(result.actionPlanPayload["arxiv_id"], "2401.00001")
        XCTAssertEqual(result.actionPlanPayload["arxiv_version"], "v2")
        XCTAssertEqual(result.actionPlanPayload["attachment_paths"], "storage:paper.pdf")
        XCTAssertEqual(result.actionPlanPayload["attachment_file_paths"], "/tmp/Zotero/storage/ATTACH1/paper.pdf")
        XCTAssertTrue(result.actionPlanPreview["candidate_summary"]?.contains("A Zotero Paper") ?? false)
        XCTAssertEqual(result.stepDrafts.map(\.kind), ["download", "import_item"])
        XCTAssertEqual(result.stepDrafts.first?.requiredPermissions, [.network, .downloadPaper])
        XCTAssertEqual(result.stepDrafts.last?.requiredPermissions, [.importLibrary, .writeLibraryBundle])
        XCTAssertTrue(result.actionPlanDraft.idempotencyKey?.contains("zotero-import-local-library-42-ABCD1234-2401.00001") ?? false)
    }

    func testBuildsMetadataOnlyImportPlanWithoutNetworkPermission() {
        let candidate = ZoteroImportCandidate(
            itemID: "99",
            key: "META99",
            itemType: "book",
            title: "Metadata Only"
        )

        let result = ZoteroImportActionPlanBuilder().build(
            candidate: candidate,
            localLibraryId: "local-library",
            localLibraryPath: nil,
            zoteroLibraryPath: nil
        )

        XCTAssertEqual(result.actionPlanDraft.kind, .importLibrary)
        XCTAssertEqual(result.actionPlanDraft.requiredPermissions, [.importLibrary, .writeLibraryBundle])
        XCTAssertEqual(result.stepDrafts.map(\.kind), ["import_item"])
        XCTAssertNil(result.actionPlanPayload["arxiv_id"])
        XCTAssertFalse(result.actionPlanPreview["import_summary"]?.contains("Download") ?? true)
    }
}
