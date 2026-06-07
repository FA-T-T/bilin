import XCTest
@testable import BilinWorkspaceKit

final class ZoteroImportBundleWriterTests: XCTestCase {
    func testWritesMetadataAndCopiesAvailableAttachmentsInsideLibraryImportDirectory() throws {
        let libraryURL = temporaryDirectory()
        let sourceURL = temporaryDirectory().appendingPathComponent("paper.pdf")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("PDF".utf8).write(to: sourceURL)
        let actionPlan = makeActionPlan(
            status: .approved,
            payload: [
                "zotero_item_id": "42",
                "zotero_key": "ZOT42",
                "title": "Zotero Paper",
                "attachment_file_paths": sourceURL.path + "\n/tmp/missing.pdf",
                "local_library_path": libraryURL.path
            ]
        )

        let result = try ZoteroImportBundleWriter().write(
            actionPlan: actionPlan,
            libraryPath: libraryURL.path
        )

        XCTAssertEqual(result.bundlePath, libraryURL.appendingPathComponent("imports/zotero/ZOT42").path)
        XCTAssertEqual(result.copiedAttachmentCount, 1)
        XCTAssertEqual(result.missingAttachmentCount, 1)
        XCTAssertFalse(result.alreadyPresent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.metadataPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.bundlePath + "/attachments/paper.pdf"))
        let metadata = try String(contentsOfFile: result.metadataPath, encoding: .utf8)
        XCTAssertTrue(metadata.contains(#""zotero_item_id" : "42""#))
        XCTAssertTrue(metadata.contains(#""copied_attachment_paths""#))
        XCTAssertEqual(result.actionResultPayload["bundle_path"], result.bundlePath)
        XCTAssertEqual(result.actionResultPayload["copied_attachment_count"], "1")
    }

    func testWritingSameBundleAgainReportsAlreadyPresentMetadata() throws {
        let libraryURL = temporaryDirectory()
        let actionPlan = makeActionPlan(
            status: .approved,
            payload: [
                "zotero_item_id": "42",
                "zotero_key": "ZOT42",
                "title": "Zotero Paper",
                "local_library_path": libraryURL.path
            ]
        )
        let writer = ZoteroImportBundleWriter()

        _ = try writer.write(actionPlan: actionPlan, libraryPath: libraryURL.path)
        let second = try writer.write(actionPlan: actionPlan, libraryPath: libraryURL.path)

        XCTAssertTrue(second.alreadyPresent)
    }

    func testRequiresApprovedOrRunningActionPlan() throws {
        let libraryURL = temporaryDirectory()
        let actionPlan = makeActionPlan(
            status: .pendingApproval,
            payload: [
                "zotero_item_id": "42",
                "zotero_key": "ZOT42",
                "local_library_path": libraryURL.path
            ]
        )

        XCTAssertThrowsError(try ZoteroImportBundleWriter().write(actionPlan: actionPlan, libraryPath: libraryURL.path)) { error in
            XCTAssertEqual(error as? ZoteroImportBundleWriterError, .approvalRequired)
        }
    }

    private func makeActionPlan(
        status: AgentActionStatus,
        payload: [String: String]
    ) -> AgentActionPlan {
        AgentActionPlan(
            id: "zotero-import-action",
            kind: .downloadPaper,
            status: status,
            title: "Prepare Zotero import",
            summary: "Confirm import.",
            requestedPermissions: [.network, .downloadPaper, .importLibrary, .writeLibraryBundle],
            steps: [],
            payloadHash: "payload-zotero-import",
            payload: payload,
            preview: ["candidate_summary": "Zotero Paper"],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("bilin-zotero-bundle-writer-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
