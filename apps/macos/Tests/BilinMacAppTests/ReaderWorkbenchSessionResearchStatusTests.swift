import Foundation
import XCTest
import BilinImportKit
import BilinReaderKit
import BilinWorkspaceKit
@testable import BilinMacApp

@MainActor
final class ReaderWorkbenchSessionResearchStatusTests: XCTestCase {
    override func tearDown() {
        ResearchStatusMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLibraryRegistrationFailureDoesNotMarkAPIUnavailable() async {
        let session = ReaderWorkbenchSession(researchAPIClient: makeClient { request in
            switch request.url?.path {
            case "/health":
                return Self.jsonResponse("""
                {
                  "status": "ok",
                  "app": "Ilios",
                  "version": "0.3.6"
                }
                """)
            case "/research-skills":
                return Self.jsonResponse("[]")
            case "/libraries":
                return Self.jsonResponse("[]")
            default:
                throw URLError(.unsupportedURL)
            }
        })
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/local-library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"

        await session.refreshResearchWorkbench()

        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertEqual(session.researchAPIHealth?.app, "Ilios")
        XCTAssertEqual(session.researchWorkbenchStatus, "Workbench unavailable")
        XCTAssertTrue(session.researchWorkbenchError?.contains("no registered library") ?? false)
    }

    func testHealthFailureIsTheOnlyRefreshPathThatMarksAPIUnavailable() async {
        let session = ReaderWorkbenchSession(researchAPIClient: makeClient { request in
            XCTAssertEqual(request.url?.path, "/health")
            throw URLError(.cannotConnectToHost)
        })

        await session.refreshResearchWorkbench()

        XCTAssertEqual(session.researchAPIStatus, "API unavailable")
        XCTAssertNil(session.researchAPIHealth)
        XCTAssertEqual(session.researchWorkbenchStatus, "Backend unavailable")
        XCTAssertNotNil(session.researchWorkbenchError)
    }

    func testNewerRefreshWinsWhenOlderHealthFailureReturnsLate() async {
        let healthRequestCounter = LockedCounter()
        let session = ReaderWorkbenchSession(researchAPIClient: makeClient { request in
            XCTAssertEqual(request.url?.path, "/health")
            let requestNumber = healthRequestCounter.increment()

            if requestNumber == 1 {
                Thread.sleep(forTimeInterval: 0.08)
                throw URLError(.cannotConnectToHost)
            }

            return Self.jsonResponse("""
            {
              "status": "ok",
              "app": "Ilios",
              "version": "0.3.6"
            }
            """)
        })

        let staleRefresh = Task { @MainActor in
            await session.refreshResearchWorkbench()
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await session.refreshResearchWorkbench()
        await staleRefresh.value

        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertEqual(session.researchAPIHealth?.app, "Ilios")
        XCTAssertNil(session.researchAPIError)
        XCTAssertEqual(session.researchWorkbenchStatus, "No library")
        XCTAssertNil(session.researchWorkbenchError)
    }

    func testRefreshResearchWorkbenchLoadsPersistedPaperReadingPlans() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(researchAPIClient: makeClient { request in
            switch request.url?.path {
            case "/health":
                return Self.jsonResponse("""
                {
                  "status": "ok",
                  "app": "Ilios",
                  "version": "0.3.6"
                }
                """)
            case "/research-skills":
                return Self.jsonResponse("[]")
            case "/libraries":
                return Self.jsonResponse("""
                [
                  {
                    "id": "backend-library",
                    "path": "/tmp/library"
                  }
                ]
                """)
            case "/libraries/backend-library/research-plans":
                XCTAssertEqual(request.httpMethod, "GET")
                let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                XCTAssertEqual(queryItems["article_revision_id"], "revision-session")
                XCTAssertEqual(queryItems["kind"], "paper_reading")
                return Self.jsonResponse("""
                [
                  {
                    "id": "plan-session",
                    "kind": "paper_reading",
                    "status": "completed",
                    "title": "Persisted reading outline",
                    "article_revision_id": "revision-session",
                    "payload_hash": "hash-plan",
                    "candidate_papers": [],
                    "reading_outline": {
                      "title": "Persisted reading outline",
                      "summary": "Master the objective before the results.",
                      "questions": ["What assumption carries the proof?"]
                    },
                    "payload": {},
                    "preview": null,
                    "result": null,
                    "error": null,
                    "created_at": "2027-01-15T08:00:00Z",
                    "updated_at": "2027-01-15T08:05:00Z"
                  }
                ]
                """)
            case "/libraries/backend-library/agent-action-plans":
                XCTAssertEqual(request.httpMethod, "GET")
                let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                XCTAssertEqual(queryItems["article_revision_id"], "revision-session")
                return Self.jsonResponse("[]")
            default:
                throw URLError(.unsupportedURL)
            }
        })
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")

        await session.refreshResearchWorkbench()

        XCTAssertEqual(session.researchWorkbenchStatus, "Workbench ready")
        XCTAssertNil(session.researchWorkbenchError)
        XCTAssertEqual(session.researchPlans.count, 1)
        XCTAssertEqual(session.researchPlans.first?.readingOutline?.summary, "Master the objective before the results.")
        XCTAssertTrue(session.researchActionPlans.isEmpty)
    }

    func testDetectWorkspacePathsDoesNotOverwriteAPIConnectionState() {
        let session = ReaderWorkbenchSession(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.researchAPIStatus = "API connected"
        session.researchAPIError = nil

        session.detectWorkspacePaths()

        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertNil(session.researchAPIError)
        XCTAssertTrue(
            session.researchWorkbenchStatus == "No local apps found"
                || session.researchWorkbenchStatus == "Local apps detected"
        )
    }

    func testMissingWritingMainFileDoesNotOverwriteAPIConnectionState() async {
        let session = ReaderWorkbenchSession(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let writingRoot = temporaryDirectory()
        try? FileManager.default.createDirectory(at: writingRoot, withIntermediateDirectories: true)
        session.workspaceDefaults.persistWorkspacePath(url: writingRoot, kind: .writingProjectRoot)
        session.selectedLibraryId = "library-1"
        let block = makeBlock()
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.researchAPIStatus = "API connected"
        session.researchAPIError = nil

        await session.prepareSelectedBlockWritingActionPlan()

        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertNil(session.researchAPIError)
        XCTAssertEqual(session.researchWorkbenchStatus, "Needs main file")
        XCTAssertNotNil(session.researchWorkbenchError)
    }

    func testPrepareSelectedBlockNoteActionPlanSendsCurrentObsidianBaseHash() async throws {
        let vaultURL = temporaryDirectory()
        let targetURL = vaultURL.appendingPathComponent("Papers/Session Paper.md")
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingNote = "# Session Paper\n\nExisting note.\n"
        try existingNote.write(to: targetURL, atomically: true, encoding: .utf8)
        let baseHash = LocalFilePatchExecutor.contentHash(for: existingNote)
        let rawSourceMarkdown = #"Selected <span class="math inline" data-latex="x_i">x</span> source <span class="citation" data-cites="smith2024">(Smith 2024)</span>."#
        let semanticSourceMarkdown = "Selected $x_i$ source [@smith2024]."
        let block = makeBlock(
            articleRevisionId: "revision-session",
            blockUid: "block-session",
            sourceMarkdown: rawSourceMarkdown
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/agent-action-plans":
                    XCTAssertEqual(request.httpMethod, "POST")
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    XCTAssertEqual(json["kind"] as? String, "write_obsidian")
                    XCTAssertEqual(json["article_revision_id"] as? String, "revision-session")
                    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                    let preview = try XCTUnwrap(json["preview"] as? [String: Any])
                    XCTAssertEqual(payload["block_uid"] as? String, "block-session")
                    XCTAssertEqual(payload["target_note"] as? String, "Papers/Session Paper.md")
                    XCTAssertEqual(payload["target_path"] as? String, targetURL.path)
                    XCTAssertEqual(payload["base_file_hash"] as? String, baseHash)
                    XCTAssertEqual(payload["target_vault_path"] as? String, vaultURL.path)
                    XCTAssertEqual(payload["source_markdown"] as? String, semanticSourceMarkdown)
                    XCTAssertTrue((preview["patch"] as? String)?.contains(semanticSourceMarkdown) ?? false)
                    return Self.jsonResponse("""
                    {
                      "id": "note-action-session",
                      "kind": "write_obsidian",
                      "status": "pending",
                      "title": "Write Obsidian note patch",
                      "description": "Preview Markdown note patch for block-session.",
                      "payload_hash": "payload-session",
                      "idempotency_key": "note-session-key",
                      "required_permissions": ["write_obsidian"],
                      "payload": {
                        "article_revision_id": "revision-session",
                        "block_uid": "block-session",
                        "block_anchor": "^ilios-revision-session-block-session",
                        "target_note": "Papers/Session Paper.md",
                        "target_path": "\(targetURL.path)",
                        "target_vault_path": "\(vaultURL.path)",
                        "base_file_hash": "\(baseHash)",
                        "source_markdown": "Selected $x_i$ source [@smith2024]."
                      },
                      "preview": {
                        "patch": "> [!note] Source block ^ilios-revision-session-block-session\\n> Selected $x_i$ source [@smith2024].\\n"
                      },
                      "result": null,
                      "steps": [],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.workspaceDefaults.workspaceConfiguration = WorkspaceConfiguration(
            selectedObsidianVault: WorkspacePathRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault,
                status: .available,
                createdAt: now,
                updatedAt: now
            )
        )
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid

        await session.prepareSelectedBlockNoteActionPlan()

        XCTAssertEqual(session.researchWorkbenchStatus, "Action plan prepared")
        XCTAssertNil(session.researchWorkbenchError)
        XCTAssertEqual(session.researchActionPlans.count, 1)
        let actionPlan = try XCTUnwrap(session.researchActionPlans.first)
        XCTAssertEqual(actionPlan.payload["base_file_hash"], baseHash)
        XCTAssertEqual(actionPlan.payload["target_path"], targetURL.path)
        XCTAssertEqual(actionPlan.preview?["patch"]?.contains(semanticSourceMarkdown), true)
    }

    func testRegenerateFailedNoteBridgePlanSendsRecoveryContextFromCurrentObsidianFile() async throws {
        let vaultURL = temporaryDirectory()
        let targetURL = vaultURL.appendingPathComponent("Papers/Session Paper.md")
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let previousText = "# Session Paper\n\nOriginal note.\n"
        let currentText = "# Session Paper\n\nExternal editor changed this note.\n"
        let previousHash = LocalFilePatchExecutor.contentHash(for: previousText)
        let currentHash = LocalFilePatchExecutor.contentHash(for: currentText)
        try currentText.write(to: targetURL, atomically: true, encoding: .utf8)
        let block = makeBlock(
            articleRevisionId: "revision-session",
            blockUid: "block-session",
            sourceMarkdown: "Recovered source claim."
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/agent-action-plans":
                    XCTAssertEqual(request.httpMethod, "POST")
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    XCTAssertEqual(json["kind"] as? String, "write_obsidian")
                    XCTAssertEqual(json["article_revision_id"] as? String, "revision-session")
                    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                    let preview = try XCTUnwrap(json["preview"] as? [String: Any])
                    XCTAssertEqual(payload["block_uid"] as? String, "block-session")
                    XCTAssertEqual(payload["target_note"] as? String, "Papers/Session Paper.md")
                    XCTAssertEqual(payload["target_path"] as? String, targetURL.path)
                    XCTAssertEqual(payload["base_file_hash"] as? String, currentHash)
                    XCTAssertEqual(payload["recovering_from_action_plan_id"] as? String, "failed-note")
                    XCTAssertEqual(payload["previous_base_file_hash"] as? String, previousHash)
                    XCTAssertEqual(payload["observed_file_hash"] as? String, currentHash)
                    XCTAssertEqual(payload["recovery_target_path"] as? String, targetURL.path)
                    XCTAssertEqual(payload["recovery_patch_strategy"] as? String, "rebase_on_current_target")
                    XCTAssertTrue((preview["recovery_summary"] as? String)?.contains("failed-note") ?? false)
                    XCTAssertTrue((preview["recovery_summary"] as? String)?.contains(currentHash) ?? false)
                    return Self.jsonResponse("""
                    {
                      "id": "note-recovery",
                      "kind": "write_obsidian",
                      "status": "pending",
                      "title": "Write Obsidian note patch",
                      "description": "Preview Markdown note patch for block-session.",
                      "payload_hash": "payload-note-recovery",
                      "idempotency_key": "note-recovery-key",
                      "required_permissions": ["write_obsidian"],
                      "payload": {
                        "article_revision_id": "revision-session",
                        "block_uid": "block-session",
                        "target_note": "Papers/Session Paper.md",
                        "target_path": "\(targetURL.path)",
                        "base_file_hash": "\(currentHash)",
                        "recovering_from_action_plan_id": "failed-note",
                        "previous_base_file_hash": "\(previousHash)",
                        "observed_file_hash": "\(currentHash)",
                        "recovery_target_path": "\(targetURL.path)",
                        "recovery_patch_strategy": "rebase_on_current_target"
                      },
                      "preview": {
                        "patch": "> Recovered source claim.",
                        "recovery_summary": "Regenerated from failed-note\\nPrevious base: \(previousHash)\\nObserved base: \(currentHash)"
                      },
                      "result": null,
                      "steps": [],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.workspaceDefaults.workspaceConfiguration = WorkspaceConfiguration(
            selectedObsidianVault: WorkspacePathRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault,
                status: .available,
                createdAt: now,
                updatedAt: now
            )
        )
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [block]
        session.selectedBlockUid = "block-session"
        let failedAction = AgentActionPlan(
            id: "failed-note",
            kind: .writeObsidian,
            status: .failed,
            title: "Write Obsidian note patch",
            summary: "Preview Markdown note patch for block-session.",
            requestedPermissions: [.writeObsidian],
            payloadHash: "payload-failed-note",
            payload: [
                "article_revision_id": "revision-session",
                "block_uid": "block-session",
                "target_note": "Papers/Session Paper.md",
                "target_path": targetURL.path,
                "base_file_hash": previousHash
            ],
            preview: [
                "patch": "> Old patch."
            ],
            createdAt: now,
            updatedAt: now,
            error: [
                "code": "file_changed_since_preview",
                "message": "Target file changed since preview.",
                "expected_base_file_hash": previousHash,
                "observed_file_hash": "stale-observed-hash"
            ],
            errorMessage: "Target file changed since preview."
        )

        await session.regenerateResearchActionPlan(failedAction)

        XCTAssertEqual(session.researchWorkbenchStatus, "Recovery patch prepared")
        XCTAssertNil(session.researchWorkbenchError)
        let recoveryPlan = try XCTUnwrap(session.researchActionPlans.first)
        XCTAssertEqual(recoveryPlan.id, "note-recovery")
        XCTAssertEqual(recoveryPlan.payload["base_file_hash"], currentHash)
        XCTAssertEqual(recoveryPlan.payload["observed_file_hash"], currentHash)
        XCTAssertEqual(recoveryPlan.payload["previous_base_file_hash"], previousHash)
        XCTAssertEqual(recoveryPlan.payload["recovering_from_action_plan_id"], "failed-note")
    }

    func testPrepareSelectedBlockNoteActionPlanFlushesPendingTextSelection() async throws {
        let vaultURL = temporaryDirectory()
        let selectedExcerpt = "Selected excerpt for Obsidian."
        let selectedExcerptHash = ReaderSelectionSnapshot.sha256TextHash(for: selectedExcerpt)
        let block = makeBlock(
            articleRevisionId: "revision-session",
            blockUid: "block-session",
            sourceMarkdown: "Whole block that should not be sent."
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/agent-action-plans":
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                    XCTAssertEqual(payload["source_markdown"] as? String, selectedExcerpt)
                    XCTAssertEqual(payload["selected_text_hash"] as? String, selectedExcerptHash)
                    return Self.jsonResponse("""
                    {
                      "id": "note-action-selection",
                      "kind": "write_obsidian",
                      "status": "pending",
                      "title": "Write Obsidian note patch",
                      "description": "Preview Markdown note patch for block-session.",
                      "payload_hash": "payload-selection",
                      "idempotency_key": "note-selection-key",
                      "required_permissions": ["write_obsidian"],
                      "payload": {
                        "article_revision_id": "revision-session",
                        "block_uid": "block-session",
                        "selected_text_hash": "\(selectedExcerptHash)",
                        "target_note": "Papers/Session Paper.md",
                        "source_markdown": "\(selectedExcerpt)"
                      },
                      "preview": {
                        "patch": "> \(selectedExcerpt)"
                      },
                      "result": null,
                      "steps": [],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.workspaceDefaults.workspaceConfiguration = WorkspaceConfiguration(
            selectedObsidianVault: WorkspacePathRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault,
                status: .available,
                createdAt: now,
                updatedAt: now
            )
        )
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid

        session.updateReaderTextSelection(blockUid: block.blockUid, selectedText: selectedExcerpt)
        await session.prepareSelectedBlockNoteActionPlan()

        XCTAssertEqual(session.readerTextSelection?.text, selectedExcerpt)
        XCTAssertEqual(session.researchWorkbenchStatus, "Action plan prepared")
        let actionPlan = try XCTUnwrap(session.researchActionPlans.first)
        XCTAssertEqual(actionPlan.payload["source_markdown"], selectedExcerpt)
        XCTAssertEqual(actionPlan.payload["selected_text_hash"], selectedExcerptHash)
    }

    func testPrepareSelectedBlockWritingActionPlanSendsSemanticMarkdownSource() async throws {
        let writingRoot = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: writingRoot,
            withIntermediateDirectories: true
        )
        let mainFileURL = writingRoot.appendingPathComponent("main.tex")
        let mainFileText = """
        \\documentclass{article}
        \\begin{document}
        \\section{Related Work}
        Existing related work.
        \\end{document}
        """
        try mainFileText.write(to: mainFileURL, atomically: true, encoding: .utf8)
        let targetPathSuffix = "/\(writingRoot.lastPathComponent)/main.tex"
        let baseHash = LocalFilePatchExecutor.contentHash(for: mainFileText)
        let rawSourceMarkdown = #"Writing <span class="math inline" data-latex="x_i">x</span> source <span class="citation" data-cites="smith2024">(Smith 2024)</span>."#
        let semanticSourceMarkdown = "Writing $x_i$ source [@smith2024]."
        let block = makeBlock(
            articleRevisionId: "revision-session",
            blockUid: "block-writing",
            sourceMarkdown: rawSourceMarkdown
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/agent-action-plans":
                    XCTAssertEqual(request.httpMethod, "POST")
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    XCTAssertEqual(json["kind"] as? String, "edit_manuscript")
                    XCTAssertEqual(json["article_revision_id"] as? String, "revision-session")
                    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                    let preview = try XCTUnwrap(json["preview"] as? [String: Any])
                    XCTAssertEqual(payload["block_uid"] as? String, "block-writing")
                    let targetPath = try XCTUnwrap(payload["target_path"] as? String)
                    XCTAssertTrue(targetPath.hasSuffix(targetPathSuffix))
                    XCTAssertEqual(payload["base_file_hash"] as? String, baseHash)
                    XCTAssertEqual(payload["source_markdown"] as? String, semanticSourceMarkdown)
                    XCTAssertTrue((payload["patch"] as? String)?.contains(#"Writing $x_i$ source \cite{smith2024}."#) ?? false)
                    XCTAssertTrue((preview["preview_markdown"] as? String)?.contains(#"Writing $x_i$ source \cite{smith2024}."#) ?? false)
                    return Self.jsonResponse("""
                    {
                      "id": "writing-action-session",
                      "kind": "edit_manuscript",
                      "status": "pending",
                      "title": "Prepare manuscript insertion",
                      "description": "Preview manuscript patch for block-writing.",
                      "payload_hash": "payload-writing",
                      "idempotency_key": "writing-session-key",
                      "required_permissions": ["edit_manuscript"],
                      "payload": {
                        "article_revision_id": "revision-session",
                        "block_uid": "block-writing",
                        "target_path": "\(targetPath)",
                        "base_file_hash": "\(baseHash)",
                        "source_markdown": "Writing $x_i$ source [@smith2024]."
                      },
                      "preview": {
                        "preview_markdown": "Writing $x_i$ source [@smith2024]."
                      },
                      "result": null,
                      "steps": [],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.workspaceDefaults.persistWorkspacePath(url: writingRoot, kind: .writingProjectRoot)
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid

        await session.prepareSelectedBlockWritingActionPlan()

        XCTAssertEqual(session.researchWorkbenchStatus, "Writing patch prepared")
        XCTAssertNil(session.researchWorkbenchError)
        XCTAssertEqual(session.researchActionPlans.count, 1)
        let actionPlan = try XCTUnwrap(session.researchActionPlans.first)
        XCTAssertEqual(actionPlan.payload["source_markdown"], semanticSourceMarkdown)
        XCTAssertTrue(actionPlan.payload["target_path"]?.hasSuffix(targetPathSuffix) ?? false)
    }

    func testPrepareSelectedBlockWritingActionPlanUsesSelectedTargetSection() async throws {
        let writingRoot = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: writingRoot,
            withIntermediateDirectories: true
        )
        let mainFileURL = writingRoot.appendingPathComponent("main.typ")
        let mainFileText = """
        #bibliography("refs.bib")

        = Introduction

        Context.

        = Method

        Approach.

        = Discussion

        Implications.
        """
        try mainFileText.write(to: mainFileURL, atomically: true, encoding: .utf8)
        let targetPathSuffix = "/\(writingRoot.lastPathComponent)/main.typ"
        let block = makeBlock(
            articleRevisionId: "revision-session",
            blockUid: "block-writing-target-section",
            sourceMarkdown: "Selected discussion note."
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/agent-action-plans":
                    XCTAssertEqual(request.httpMethod, "POST")
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    XCTAssertEqual(json["kind"] as? String, "edit_manuscript")
                    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                    let preview = try XCTUnwrap(json["preview"] as? [String: Any])
                    let targetPath = try XCTUnwrap(payload["target_path"] as? String)
                    XCTAssertTrue(targetPath.hasSuffix(targetPathSuffix))
                    XCTAssertEqual(payload["source_markdown"] as? String, "Selected discussion note.")
                    XCTAssertEqual(payload["target_anchor"] as? String, "discussion")
                    XCTAssertEqual(payload["target_section_path"] as? String, #"["Discussion"]"#)
                    XCTAssertEqual(payload["insertion_mode"] as? String, WritingPatchInsertionMode.sectionEnd.rawValue)
                    XCTAssertTrue((payload["patch"] as? String)?.contains("Selected discussion note.") ?? false)
                    XCTAssertTrue((preview["preview_markdown"] as? String)?.contains("Selected discussion note.") ?? false)
                    return Self.jsonResponse("""
                    {
                      "id": "writing-action-selected-section",
                      "kind": "edit_manuscript",
                      "status": "pending",
                      "title": "Prepare manuscript insertion",
                      "description": "Preview manuscript patch for block-writing-target-section.",
                      "payload_hash": "payload-writing-selected-section",
                      "idempotency_key": "writing-selected-section-key",
                      "required_permissions": ["edit_manuscript"],
                      "payload": {
                        "article_revision_id": "revision-session",
                        "block_uid": "block-writing-target-section",
                        "target_path": "\(targetPath)",
                        "source_markdown": "Selected discussion note.",
                        "target_anchor": "discussion",
                        "target_section_path": "[\\"Discussion\\"]",
                        "insertion_mode": "\(WritingPatchInsertionMode.sectionEnd.rawValue)"
                      },
                      "preview": {
                        "preview_markdown": "Selected discussion note."
                      },
                      "result": null,
                      "steps": [],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.workspaceDefaults.persistWorkspacePath(url: writingRoot, kind: .writingProjectRoot)
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.selectedWritingTargetSection = "Discussion"

        await session.prepareSelectedBlockWritingActionPlan()

        XCTAssertEqual(session.researchWorkbenchStatus, "Writing patch prepared")
        XCTAssertNil(session.researchWorkbenchError)
        let actionPlan = try XCTUnwrap(session.researchActionPlans.first)
        XCTAssertEqual(actionPlan.payload["target_anchor"], "discussion")
        XCTAssertEqual(actionPlan.payload["target_section_path"], #"["Discussion"]"#)
    }

    func testPrepareSelectedBlockWritingActionPlanFlushesPendingTextSelection() async throws {
        let writingRoot = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: writingRoot,
            withIntermediateDirectories: true
        )
        let mainFileURL = writingRoot.appendingPathComponent("main.typ")
        let mainFileText = """
        #bibliography("refs.bib")

        = Related Work

        Existing related work.
        """
        try mainFileText.write(to: mainFileURL, atomically: true, encoding: .utf8)
        let selectedExcerpt = "Immediate manuscript excerpt."
        let selectedExcerptHash = ReaderSelectionSnapshot.sha256TextHash(for: selectedExcerpt)
        let block = makeBlock(
            articleRevisionId: "revision-session",
            blockUid: "block-writing-selection",
            sourceMarkdown: "Whole writing block that should not be sent."
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/agent-action-plans":
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                    let preview = try XCTUnwrap(json["preview"] as? [String: Any])
                    let targetPath = try XCTUnwrap(payload["target_path"] as? String)
                    XCTAssertTrue(targetPath.hasSuffix("/\(writingRoot.lastPathComponent)/main.typ"))
                    XCTAssertEqual(payload["source_markdown"] as? String, selectedExcerpt)
                    XCTAssertEqual(payload["selected_text_hash"] as? String, selectedExcerptHash)
                    XCTAssertTrue((payload["patch"] as? String)?.contains(selectedExcerpt) ?? false)
                    XCTAssertTrue((preview["preview_markdown"] as? String)?.contains(selectedExcerpt) ?? false)
                    return Self.jsonResponse("""
                    {
                      "id": "writing-action-selection",
                      "kind": "edit_manuscript",
                      "status": "pending",
                      "title": "Prepare manuscript insertion",
                      "description": "Preview manuscript patch for block-writing-selection.",
                      "payload_hash": "payload-writing-selection",
                      "idempotency_key": "writing-selection-key",
                      "required_permissions": ["edit_manuscript"],
                      "payload": {
                        "article_revision_id": "revision-session",
                        "block_uid": "block-writing-selection",
                        "selected_text_hash": "\(selectedExcerptHash)",
                        "target_path": "\(targetPath)",
                        "source_markdown": "\(selectedExcerpt)"
                      },
                      "preview": {
                        "preview_markdown": "\(selectedExcerpt)"
                      },
                      "result": null,
                      "steps": [],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.workspaceDefaults.persistWorkspacePath(url: writingRoot, kind: .writingProjectRoot)
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid

        session.updateReaderTextSelection(blockUid: block.blockUid, selectedText: selectedExcerpt)
        await session.prepareSelectedBlockWritingActionPlan()

        XCTAssertEqual(session.readerTextSelection?.text, selectedExcerpt)
        XCTAssertEqual(session.researchWorkbenchStatus, "Writing patch prepared")
        let actionPlan = try XCTUnwrap(session.researchActionPlans.first)
        XCTAssertEqual(actionPlan.payload["source_markdown"], selectedExcerpt)
        XCTAssertEqual(actionPlan.payload["selected_text_hash"], selectedExcerptHash)
    }

    func testPrepareSelectedArticleReadingOutlineActionPlanSendsPaperMasteryRequest() async throws {
        let rawSourceMarkdown = #"Selected <span class="math inline" data-latex="x_i">x</span> source <span class="citation" data-cites="smith2024">(Smith 2024)</span>."#
        let semanticSourceMarkdown = "Selected $x_i$ source [@smith2024]."
        let block = makeBlock(
            articleRevisionId: "revision-session",
            blockUid: "block-session",
            sourceMarkdown: rawSourceMarkdown
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/research-plans/generate":
                    XCTAssertEqual(request.httpMethod, "POST")
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    XCTAssertEqual(json["title"] as? String, "Generate reading outline: Session Paper")
                    XCTAssertEqual(json["kind"] as? String, "paper_reading")
                    XCTAssertEqual(json["topic"] as? String, "Session Paper")
                    XCTAssertEqual(json["article_revision_id"] as? String, "revision-session")
                    XCTAssertEqual(json["skill_slug"] as? String, "paper-outline")
                    XCTAssertTrue((json["idempotency_key"] as? String)?.hasPrefix("reading-outline-") ?? false)
                    let candidatePapers = try XCTUnwrap(json["candidate_papers"] as? [[String: Any]])
                    XCTAssertEqual(candidatePapers.first?["title"] as? String, "Session Paper")
                    XCTAssertEqual(candidatePapers.first?["external_id"] as? String, "2401.00001")
                    XCTAssertEqual(candidatePapers.first?["article_revision_id"] as? String, "revision-session")
                    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                    XCTAssertEqual(payload["article_id"] as? String, "article-session")
                    XCTAssertEqual(payload["article_title"] as? String, "Session Paper")
                    XCTAssertEqual(payload["article_source"] as? String, "arxiv")
                    XCTAssertEqual(payload["article_external_id"] as? String, "2401.00001")
                    XCTAssertEqual(payload["article_revision_id"] as? String, "revision-session")
                    XCTAssertEqual(payload["selected_block_uid"] as? String, "block-session")
                    XCTAssertEqual(payload["selected_block_markdown"] as? String, semanticSourceMarkdown)
                    let visibleBlocks = try XCTUnwrap(payload["visible_blocks"] as? [[String: Any]])
                    XCTAssertEqual(visibleBlocks.first?["block_uid"] as? String, "block-session")
                    XCTAssertEqual(visibleBlocks.first?["source_markdown"] as? String, semanticSourceMarkdown)
                    return Self.jsonResponse("""
                    {
                      "id": "reading-outline-session",
                      "kind": "generate_research_outline",
                      "status": "pending",
                      "title": "Generate reading outline: Session Paper",
                      "description": "Prepare a paper-specific mastery outline.",
                      "payload_hash": "payload-outline",
                      "idempotency_key": "outline-key",
                      "required_permissions": ["provider_call"],
                      "payload": {
                        "article_revision_id": "revision-session",
                        "selected_block_uid": "block-session"
                      },
                      "preview": {
                        "outline_policy": "paper_mastery"
                      },
                      "result": null,
                      "steps": [],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.researchSkills = [makePaperOutlineSkill()]

        await session.prepareSelectedArticleReadingOutlineActionPlan()

        XCTAssertEqual(session.researchWorkbenchStatus, "Reading outline action prepared")
        XCTAssertNil(session.researchWorkbenchError)
        XCTAssertEqual(session.researchActionPlans.count, 1)
        let actionPlan = try XCTUnwrap(session.researchActionPlans.first)
        XCTAssertEqual(actionPlan.kind, .generateResearchOutline)
        XCTAssertEqual(actionPlan.payload["article_revision_id"], "revision-session")
    }

    func testPrepareSelectedArticleReadingOutlineActionPlanRequiresEnabledPaperOutlineSkill() async {
        let requestCounter = LockedCounter()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { _ in
                _ = requestCounter.increment()
                throw URLError(.unsupportedURL)
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")

        await session.prepareSelectedArticleReadingOutlineActionPlan()

        XCTAssertEqual(requestCounter.current(), 0)
        XCTAssertEqual(session.researchWorkbenchStatus, "Skill not indexed")
        XCTAssertEqual(
            session.researchWorkbenchError,
            "Index local research skills before preparing a paper-specific reading outline action."
        )

        session.researchSkills = [makePaperOutlineSkill(status: .disabled)]
        await session.prepareSelectedArticleReadingOutlineActionPlan()

        XCTAssertEqual(requestCounter.current(), 0)
        XCTAssertEqual(session.researchWorkbenchStatus, "Skill disabled")
        XCTAssertEqual(
            session.researchWorkbenchError,
            "Paper Outline is indexed but disabled. Enable it in the research backend before preparing outline actions."
        )

        session.researchSkills = [makePaperOutlineSkill(supportedTasks: [.writing])]
        await session.prepareSelectedArticleReadingOutlineActionPlan()

        XCTAssertEqual(requestCounter.current(), 0)
        XCTAssertEqual(session.researchWorkbenchStatus, "Skill task mismatch")
        XCTAssertEqual(
            session.researchWorkbenchError,
            "Paper Outline is indexed but does not declare paper reading support."
        )
    }

    func testPrepareSelectedZoteroImportActionPlanSendsConfirmableDownloadPlan() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let zoteroItem = ZoteroItem(
            id: 42,
            key: "ZOT42",
            itemType: "journalArticle",
            title: "Zotero ArXiv Paper",
            abstractNote: "A candidate paper from Zotero.",
            date: "2026",
            doi: "10.1234/zotero",
            url: "https://arxiv.org/abs/2401.00001",
            extra: "arXiv:2401.00001v2",
            libraryCatalog: "arXiv",
            collections: [
                ZoteroCollection(id: 7, key: "QUEUE", name: "Reading Queue", parentCollectionID: nil)
            ],
            tags: ["reader", "ratex"],
            creators: [
                ZoteroCreator(firstName: "Ada", lastName: "Lovelace", displayName: "Ada Lovelace", creatorType: "author")
            ],
            attachments: [
                ZoteroAttachment(
                    id: 9,
                    key: "ATTACH9",
                    parentItemID: 42,
                    contentType: "application/pdf",
                    path: "storage:paper.pdf",
                    resolvedFileURL: URL(fileURLWithPath: "/tmp/Zotero/storage/ATTACH9/paper.pdf")
                )
            ],
            arxiv: ZoteroArXivMetadata(identifier: "2401.00001", version: "v2", sourceField: "extra"),
            dateAdded: "2026-06-06 08:00:00",
            dateModified: "2026-06-06 08:10:00"
        )
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/agent-action-plans":
                    XCTAssertEqual(request.httpMethod, "POST")
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    XCTAssertEqual(json["kind"] as? String, "download_paper")
                    XCTAssertEqual(json["title"] as? String, "Prepare Zotero arXiv import")
                    XCTAssertEqual(json["required_permissions"] as? [String], [
                        "network",
                        "download_paper",
                        "import_library",
                        "write_library_bundle"
                    ])
                    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                    XCTAssertEqual(payload["source"] as? String, "zotero")
                    XCTAssertEqual(payload["zotero_item_id"] as? String, "42")
                    XCTAssertEqual(payload["zotero_key"] as? String, "ZOT42")
                    XCTAssertEqual(payload["arxiv_id"] as? String, "2401.00001")
                    XCTAssertEqual(payload["arxiv_version"] as? String, "v2")
                    XCTAssertEqual(payload["local_library_id"] as? String, "local-library")
                    XCTAssertEqual(payload["local_library_path"] as? String, "/tmp/library")
                    XCTAssertEqual(payload["zotero_library_path"] as? String, "/tmp/Zotero")
                    XCTAssertEqual(payload["attachment_paths"] as? String, "storage:paper.pdf")
                    XCTAssertEqual(payload["attachment_file_paths"] as? String, "/tmp/Zotero/storage/ATTACH9/paper.pdf")
                    let preview = try XCTUnwrap(json["preview"] as? [String: Any])
                    XCTAssertTrue((preview["candidate_summary"] as? String)?.contains("Zotero ArXiv Paper") ?? false)
                    let steps = try XCTUnwrap(json["steps"] as? [[String: Any]])
                    XCTAssertEqual(steps.compactMap { $0["kind"] as? String }, ["download", "import_item"])
                    return Self.jsonResponse("""
                    {
                      "id": "zotero-import-action",
                      "kind": "download_paper",
                      "status": "pending",
                      "title": "Prepare Zotero arXiv import",
                      "description": "Confirm arXiv download and Bilin library import for Zotero ArXiv Paper.",
                      "payload_hash": "payload-zotero-import",
                      "idempotency_key": "zotero-import-key",
                      "required_permissions": ["network", "download_paper", "import_library", "write_library_bundle"],
                      "payload": {
                        "source": "zotero",
                        "zotero_item_id": "42",
                        "zotero_key": "ZOT42",
                        "title": "Zotero ArXiv Paper",
                        "arxiv_id": "2401.00001",
                        "arxiv_version": "v2",
                        "local_library_id": "local-library",
                        "local_library_path": "/tmp/library",
                        "zotero_library_path": "/tmp/Zotero"
                      },
                      "preview": {
                        "candidate_summary": "Zotero ArXiv Paper\\narXiv: 2401.00001v2",
                        "import_summary": "Download the arXiv paper, then import the Zotero metadata into the selected Bilin library."
                      },
                      "result": null,
                      "steps": [
                        {
                          "id": "download-step",
                          "kind": "download",
                          "title": "Download arXiv paper",
                          "required_permissions": ["network", "download_paper"],
                          "payload": {
                            "arxiv_id": "2401.00001"
                          }
                        },
                        {
                          "id": "import-step",
                          "kind": "import_item",
                          "title": "Import Zotero item into Bilin",
                          "required_permissions": ["import_library", "write_library_bundle"],
                          "payload": {
                            "zotero_item_id": "42"
                          }
                        }
                      ],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")
        session.researchAPIError = nil
        session.workspaceDefaults.workspaceConfiguration = WorkspaceConfiguration(
            selectedZoteroLibrary: WorkspacePathRecord(
                id: "zotero",
                name: "Zotero",
                path: "/tmp/Zotero",
                kind: .zoteroLibrary,
                status: .available,
                createdAt: now,
                updatedAt: now
            )
        )
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.zoteroItems = [zoteroItem]
        session.selectedLibraryItem = .zoteroItem(id: zoteroItem.id)

        await session.prepareSelectedZoteroImportActionPlan()

        XCTAssertEqual(session.researchWorkbenchStatus, "Zotero download action prepared")
        XCTAssertNil(session.researchWorkbenchError)
        XCTAssertEqual(session.researchActionPlans.count, 1)
        let actionPlan = try XCTUnwrap(session.researchActionPlans.first)
        XCTAssertEqual(actionPlan.kind, .downloadPaper)
        XCTAssertEqual(actionPlan.payload["zotero_item_id"], "42")
        XCTAssertEqual(actionPlan.payload["arxiv_id"], "2401.00001")
    }

    func testPrepareSelectedZoteroImportActionPlanRequiresBilinLibrary() async {
        let session = ReaderWorkbenchSession()
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")
        session.zoteroItems = [
            ZoteroItem(
                id: 42,
                key: "ZOT42",
                itemType: "journalArticle",
                title: "Zotero Paper",
                abstractNote: nil,
                date: nil,
                doi: nil,
                url: nil,
                extra: nil,
                libraryCatalog: nil
            )
        ]
        session.selectedLibraryItem = .zoteroItem(id: 42)

        await session.prepareSelectedZoteroImportActionPlan()

        XCTAssertEqual(session.researchWorkbenchStatus, "Bilin library required")
        XCTAssertTrue(session.researchActionPlans.isEmpty)
    }

    func testApplyApprovedZoteroImportActionPlanWritesBundleAndMarksSucceeded() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let libraryURL = temporaryDirectory()
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let attachmentURL = temporaryDirectory().appendingPathComponent("paper.pdf")
        try FileManager.default.createDirectory(
            at: attachmentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("PDF".utf8).write(to: attachmentURL)
        let actionPlan = makeZoteroImportActionPlan(
            status: .approved,
            libraryPath: libraryURL.path,
            attachmentPath: attachmentURL.path
        )
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "\(libraryURL.path)"
                      }
                    ]
                    """)
                case "/libraries/backend-library/agent-action-plans/zotero-import-action/start":
                    XCTAssertEqual(request.httpMethod, "POST")
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                    XCTAssertEqual(payload["mode"] as? String, "zotero_import_bundle")
                    return Self.jsonResponse(Self.zoteroImportActionJSON(
                        status: "running",
                        libraryPath: libraryURL.path,
                        attachmentPath: attachmentURL.path
                    ))
                case "/libraries/backend-library/agent-action-plans/zotero-import-action/succeed":
                    XCTAssertEqual(request.httpMethod, "POST")
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    let result = try XCTUnwrap(json["result"] as? [String: Any])
                    XCTAssertEqual(result["copied_attachment_count"] as? String, "1")
                    XCTAssertEqual(result["missing_attachment_count"] as? String, "0")
                    XCTAssertTrue((result["bundle_path"] as? String)?.hasSuffix("imports/zotero/ZOT42") ?? false)
                    return Self.jsonResponse(Self.zoteroImportActionJSON(
                        status: "succeeded",
                        libraryPath: libraryURL.path,
                        attachmentPath: attachmentURL.path,
                        result: result
                    ))
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")
        session.researchAPIError = nil
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: libraryURL.path,
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.researchActionPlans = [actionPlan]

        await session.applyResearchActionPlan(actionPlan)

        XCTAssertEqual(session.researchWorkbenchStatus, "Import bundle written")
        XCTAssertNil(session.researchWorkbenchError)
        XCTAssertEqual(session.researchActionPlans.first?.status, .succeeded)
        let bundleURL = libraryURL.appendingPathComponent("imports/zotero/ZOT42")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("metadata.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("attachments/paper.pdf").path))
    }

    func testSelectingZoteroItemPreservesZoteroImportPlansButDropsReaderPlans() async throws {
        let session = ReaderWorkbenchSession()
        let zoteroPlan = makeZoteroImportActionPlan(
            status: .pendingApproval,
            libraryPath: "/tmp/library",
            attachmentPath: "/tmp/paper.pdf"
        )
        var untargetedImportPlan = zoteroPlan
        untargetedImportPlan.id = "untargeted-import"
        untargetedImportPlan.payload.removeValue(forKey: "zotero_item_id")
        let readerPlan = makeActionPlan(id: "reader-note", status: .pendingApproval)
        session.researchActionPlans = [readerPlan, untargetedImportPlan, zoteroPlan]

        await session.selectLibraryItem(.zoteroItem(id: 42))

        XCTAssertEqual(session.researchActionPlans.map(\.id), [zoteroPlan.id])
        XCTAssertEqual(session.researchActionPlans.first?.payload["zotero_item_id"], "42")
    }

    func testLateReaderActionPlanDoesNotPolluteSelectedZoteroItem() async throws {
        let vaultURL = temporaryDirectory()
        let targetURL = vaultURL.appendingPathComponent("Papers/Session Paper.md")
        let block = makeBlock(
            articleRevisionId: "revision-session",
            blockUid: "block-late",
            sourceMarkdown: "Late reader block."
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/agent-action-plans":
                    XCTAssertEqual(request.httpMethod, "POST")
                    Thread.sleep(forTimeInterval: 0.08)
                    return Self.jsonResponse("""
                    {
                      "id": "late-note-action",
                      "kind": "write_obsidian",
                      "status": "pending",
                      "title": "Write Obsidian note patch",
                      "description": "Preview Markdown note patch for block-late.",
                      "payload_hash": "payload-late-note",
                      "idempotency_key": "late-note-key",
                      "required_permissions": ["write_obsidian"],
                      "payload": {
                        "article_revision_id": "revision-session",
                        "block_uid": "block-late",
                        "target_note": "Papers/Session Paper.md",
                        "target_path": "\(targetURL.path)",
                        "target_vault_path": "\(vaultURL.path)",
                        "source_markdown": "Late reader block."
                      },
                      "preview": {
                        "patch": "> [!note] Source block ^ilios-revision-session-block-late\\\\n> Late reader block.\\\\n"
                      },
                      "result": null,
                      "steps": [],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.workspaceDefaults.workspaceConfiguration = WorkspaceConfiguration(
            selectedObsidianVault: WorkspacePathRecord(
                id: "vault",
                name: "Notes",
                path: vaultURL.path,
                kind: .obsidianVault,
                status: .available,
                createdAt: now,
                updatedAt: now
            )
        )
        session.researchAPIHealth = BilinAPIHealth(status: "ok", app: "Ilios")
        session.researchAPIError = nil
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.zoteroItems = [
            ZoteroItem(
                id: 42,
                key: "ZOT42",
                itemType: "journalArticle",
                title: "Zotero Paper",
                abstractNote: nil,
                date: nil,
                doi: nil,
                url: nil,
                extra: nil,
                libraryCatalog: nil
            )
        ]

        let noteTask = Task { @MainActor in
            await session.prepareSelectedBlockNoteActionPlan()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        await session.selectLibraryItem(.zoteroItem(id: 42))
        await noteTask.value

        XCTAssertEqual(session.selectedLibraryItem, .zoteroItem(id: 42))
        XCTAssertTrue(session.researchActionPlans.isEmpty)
        XCTAssertNotEqual(session.researchWorkbenchStatus, "Action plan prepared")
    }

    func testEnableResearchSkillSendsDigestPermissionsAndUpdatesLocalRegistry() async throws {
        let requestCounter = LockedCounter()
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                XCTAssertEqual(request.url?.path, "/research-skills/paper-outline/enable")
                XCTAssertEqual(request.httpMethod, "POST")
                _ = requestCounter.increment()
                let data = try XCTUnwrap(Self.requestBodyData(from: request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(json["expected_digest"] as? String, "sha256:paper-outline")
                XCTAssertEqual(json["granted_permissions"] as? [String], ["provider_call"])
                return Self.jsonResponse(Self.paperOutlineSkillJSON(enabled: true))
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.researchSkills = [makePaperOutlineSkill(status: .disabled)]

        await session.enableResearchSkill(session.researchSkills[0])

        XCTAssertEqual(requestCounter.current(), 1)
        XCTAssertEqual(session.researchWorkbenchStatus, "Skill enabled")
        XCTAssertNil(session.researchWorkbenchError)
        XCTAssertEqual(session.researchSkills.count, 1)
        XCTAssertEqual(session.researchSkills[0].slug, "paper-outline")
        XCTAssertTrue(session.researchSkills[0].isEnabled)
    }

    func testRegenerateFailedReadingOutlineActionPreparesNewOutlineAction() async throws {
        let generateRequestCounter = LockedCounter()
        let block = makeBlock(
            articleRevisionId: "revision-session",
            blockUid: "block-session",
            sourceMarkdown: "Selected source claim."
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { request in
                switch request.url?.path {
                case "/libraries":
                    return Self.jsonResponse("""
                    [
                      {
                        "id": "backend-library",
                        "path": "/tmp/library"
                      }
                    ]
                    """)
                case "/libraries/backend-library/research-plans/generate":
                    XCTAssertEqual(request.httpMethod, "POST")
                    _ = generateRequestCounter.increment()
                    let data = try XCTUnwrap(Self.requestBodyData(from: request))
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    XCTAssertEqual(json["kind"] as? String, "paper_reading")
                    XCTAssertEqual(json["article_revision_id"] as? String, "revision-session")
                    XCTAssertEqual(json["skill_slug"] as? String, "paper-outline")
                    return Self.jsonResponse("""
                    {
                      "id": "reading-outline-retry",
                      "kind": "generate_research_outline",
                      "status": "pending",
                      "title": "Generate reading outline: Session Paper",
                      "description": "Prepare a paper-specific mastery outline.",
                      "payload_hash": "payload-outline-retry",
                      "idempotency_key": "outline-retry-key",
                      "required_permissions": ["provider_call"],
                      "payload": {
                        "article_revision_id": "revision-session",
                        "selected_block_uid": "block-session"
                      },
                      "preview": {
                        "outline_policy": "paper_mastery"
                      },
                      "result": null,
                      "steps": [],
                      "created_at": "2027-01-15T08:00:00Z",
                      "updated_at": "2027-01-15T08:00:00Z",
                      "approved_at": null,
                      "finished_at": null,
                      "error": null
                    }
                    """)
                default:
                    throw URLError(.unsupportedURL)
                }
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [block]
        session.selectedBlockUid = block.blockUid
        session.researchSkills = [makePaperOutlineSkill()]
        let failedAction = AgentActionPlan(
            id: "failed-outline",
            kind: .generateResearchOutline,
            status: .failed,
            title: "Generate reading outline: Session Paper",
            summary: "Previous outline generation failed.",
            requestedPermissions: [.providerCall],
            steps: [],
            payloadHash: "payload-failed-outline",
            payload: [
                "article_revision_id": "revision-session",
                "selected_block_uid": "block-session"
            ],
            createdAt: now,
            updatedAt: now,
            errorMessage: "Provider failed"
        )
        session.researchActionPlans = [failedAction]

        await session.regenerateResearchActionPlan(failedAction)

        XCTAssertEqual(generateRequestCounter.current(), 1)
        XCTAssertEqual(session.researchWorkbenchStatus, "Reading outline action prepared")
        XCTAssertNil(session.researchWorkbenchError)
        XCTAssertEqual(session.researchActionPlans.first?.id, "reading-outline-retry")
        XCTAssertEqual(session.researchActionPlans.first?.kind, .generateResearchOutline)
    }

    func testUnavailableDetectedWorkspacePathDoesNotOverwriteAPIConnectionState() async {
        let session = ReaderWorkbenchSession(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.researchAPIStatus = "API connected"
        session.researchAPIError = nil
        let record = WorkspacePathRecord(
            id: "missing-vault",
            name: "Missing Vault",
            path: "/tmp/bilin-missing-vault-\(UUID().uuidString)",
            kind: .obsidianVault,
            status: .missing,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        await session.useDetectedWorkspacePath(record)

        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertNil(session.researchAPIError)
        XCTAssertEqual(session.researchWorkbenchStatus, "Location unavailable")
        XCTAssertTrue(session.researchWorkbenchError?.contains("Missing Vault") ?? false)
        XCTAssertTrue(session.researchWorkbenchError?.contains(record.path) ?? false)
    }

    func testDetectedZoteroOpenFailureDoesNotOverwriteAPIConnectionState() async {
        let session = ReaderWorkbenchSession(
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        let zoteroDirectory = temporaryDirectory()
        try? FileManager.default.createDirectory(at: zoteroDirectory, withIntermediateDirectories: true)
        session.researchAPIStatus = "API connected"
        session.researchAPIError = nil
        let record = WorkspacePathRecord(
            id: "broken-zotero",
            name: "Broken Zotero",
            path: zoteroDirectory.path,
            kind: .zoteroLibrary,
            status: .available,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        await session.useDetectedWorkspacePath(record)

        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertNil(session.researchAPIError)
        XCTAssertEqual(session.researchWorkbenchStatus, "Zotero unavailable")
        XCTAssertNotNil(session.researchWorkbenchError)
        XCTAssertTrue(session.zoteroItems.isEmpty)
        XCTAssertNil(session.workspaceDefaults.workspaceConfiguration.selectedZoteroLibrary)
    }

    func testReadingOutlineActionDoesNotExposeLocalPatchApply() {
        let outlineAction = makeOutlineActionPlan(status: .approved)
        let noteAction = makeActionPlan(id: "note-write", status: .approved)
        var writingAction = makeActionPlan(id: "writing-write", status: .approved)
        writingAction.kind = .writingPatch

        XCTAssertNil(AgentActionPlanLocalExecutionPolicy.applyButtonTitle(for: outlineAction))
        XCTAssertFalse(AgentActionPlanLocalExecutionPolicy.supportsLocalApply(outlineAction))
        XCTAssertEqual(AgentActionPlanRemoteExecutionPolicy.runButtonTitle(for: outlineAction), "Generate Outline")
        XCTAssertTrue(AgentActionPlanRemoteExecutionPolicy.supportsRemoteRun(outlineAction))
        XCTAssertEqual(AgentActionPlanLocalExecutionPolicy.applyButtonTitle(for: noteAction), "Apply Note Patch")
        XCTAssertEqual(AgentActionPlanLocalExecutionPolicy.applyButtonTitle(for: writingAction), "Apply Writing Patch")
        XCTAssertNil(AgentActionPlanRemoteExecutionPolicy.runButtonTitle(for: noteAction))
    }

    func testApplyReadingOutlineActionDoesNotRouteToLocalPatchExecutor() async {
        let requestCounter = LockedCounter()
        let session = ReaderWorkbenchSession(researchAPIClient: makeClient { _ in
            _ = requestCounter.increment()
            throw URLError(.unsupportedURL)
        })
        session.selectedLibraryId = "local-library"
        let outlineAction = makeOutlineActionPlan(status: .approved)

        await session.applyResearchActionPlan(outlineAction)

        XCTAssertEqual(requestCounter.current(), 0)
        XCTAssertFalse(session.researchAPIBusy)
        XCTAssertEqual(session.researchWorkbenchStatus, "No local patch")
        XCTAssertTrue(session.researchWorkbenchError?.contains("does not have a local file patch") ?? false)
    }

    func testResearchActionMutationDoesNotStartWhileBusy() async {
        let requestCounter = LockedCounter()
        let session = ReaderWorkbenchSession(researchAPIClient: makeClient { _ in
            _ = requestCounter.increment()
            throw URLError(.unsupportedURL)
        })
        session.selectedLibraryId = "local-library"
        session.researchAPIBusy = true
        let actionPlan = makeActionPlan(id: "pending-note", status: .pendingApproval)

        await session.approveResearchActionPlan(actionPlan)

        XCTAssertEqual(requestCounter.current(), 0)
        XCTAssertTrue(session.researchAPIBusy)
        XCTAssertEqual(session.researchWorkbenchStatus, "Research action busy")
        XCTAssertTrue(session.researchWorkbenchError?.contains("already running") ?? false)
    }

    func testPrepareReadingOutlineActionDoesNotRequestBackendWhileBusy() async {
        let requestCounter = LockedCounter()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ReaderWorkbenchSession(
            researchAPIClient: makeClient { _ in
                _ = requestCounter.increment()
                throw URLError(.unsupportedURL)
            },
            workspaceConfigurationCoordinator: isolatedWorkspaceConfigurationCoordinator()
        )
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.researchSkills = [makePaperOutlineSkill()]
        session.researchAPIBusy = true

        await session.prepareSelectedArticleReadingOutlineActionPlan()

        XCTAssertEqual(requestCounter.current(), 0)
        XCTAssertTrue(session.researchAPIBusy)
        XCTAssertEqual(session.researchWorkbenchStatus, "Research action busy")
        XCTAssertTrue(session.researchActionPlans.isEmpty)
    }

    func testRegenerateResearchActionPlanDoesNotChangeSelectionWhileBusy() async {
        let session = ReaderWorkbenchSession()
        session.blocks = [
            makeBlock(blockUid: "block-current"),
            makeBlock(blockUid: "block-failed")
        ]
        session.selectedBlockUid = "block-current"
        session.researchAPIBusy = true
        var failedAction = makeActionPlan(id: "failed-note", status: .failed)
        failedAction.payload["block_uid"] = "block-failed"

        await session.regenerateResearchActionPlan(failedAction)

        XCTAssertEqual(session.selectedBlockUid, "block-current")
        XCTAssertTrue(session.researchAPIBusy)
        XCTAssertEqual(session.researchWorkbenchStatus, "Research action busy")
        XCTAssertTrue(session.researchWorkbenchError?.contains("already running") ?? false)
    }

    func testRunApprovedReadingOutlineActionMaterializesAndRefreshesResearchPlan() async throws {
        let requestCounter = LockedCounter()
        let session = ReaderWorkbenchSession(researchAPIClient: makeClient { request in
            let requestNumber = requestCounter.increment()
            switch (requestNumber, request.url?.path) {
            case (1, "/libraries"):
                return Self.jsonResponse("""
                [
                  {
                    "id": "backend-library",
                    "path": "/tmp/library"
                  }
                ]
                """)
            case (2, "/libraries/backend-library/agent-action-plans/outline-action/start"):
                XCTAssertEqual(request.httpMethod, "POST")
                let data = try XCTUnwrap(Self.requestBodyData(from: request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let payload = try XCTUnwrap(json["payload"] as? [String: Any])
                XCTAssertEqual(payload["executor"] as? String, "macos")
                XCTAssertEqual(payload["mode"] as? String, "research_outline")
                return Self.jsonResponse(Self.outlineActionJSON(status: "running"))
            case (3, "/libraries/backend-library/agent-action-plans/outline-action/succeed"):
                XCTAssertEqual(request.httpMethod, "POST")
                let data = try XCTUnwrap(Self.requestBodyData(from: request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let result = try XCTUnwrap(json["result"] as? [String: Any])
                XCTAssertEqual(result["status"] as? String, "done")
                XCTAssertEqual(result["executor"] as? String, "macos")
                XCTAssertEqual(result["outline_source"] as? String, "visible_reader_blocks")
                let readingOutline = try XCTUnwrap(result["reading_outline"] as? [String: Any])
                XCTAssertEqual(readingOutline["status"] as? String, "ready")
                XCTAssertTrue((readingOutline["summary"] as? String)?.contains("Session Paper") ?? false)
                let masteryOutlines = try XCTUnwrap(readingOutline["paper_mastery_outlines"] as? [[String: Any]])
                let mastery = try XCTUnwrap(masteryOutlines.first)
                XCTAssertEqual(mastery["paper_id"] as? String, "2401.00001")
                XCTAssertEqual(mastery["paper_title"] as? String, "Session Paper")
                XCTAssertTrue(((mastery["claim"] as? [String])?.first ?? "").contains("We propose"))
                XCTAssertTrue(((mastery["equation"] as? [String])?.first ?? "").contains("\\\\mathcal{L}"))
                XCTAssertTrue(((mastery["evidence"] as? [String])?.first ?? "").contains("Experiments"))
                let resultData = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                let resultJSON = try XCTUnwrap(String(data: resultData, encoding: .utf8))
                return Self.jsonResponse(Self.outlineActionJSON(
                    status: "succeeded",
                    finishedAt: "2027-01-15T08:02:00Z",
                    resultJSON: resultJSON
                ))
            case (4, "/libraries/backend-library/research-plans"):
                XCTAssertEqual(request.httpMethod, "GET")
                let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                XCTAssertEqual(queryItems["article_revision_id"], "revision-session")
                XCTAssertEqual(queryItems["kind"], "paper_reading")
                return Self.jsonResponse("""
                [
                  {
                    "id": "plan-generated",
                    "kind": "paper_reading",
                    "status": "active",
                    "title": "Generated reading outline",
                    "topic": "Session Paper",
                    "article_revision_id": "revision-session",
                    "skill_slug": "paper-outline",
                    "payload_hash": "payload-plan-generated",
                    "candidate_papers": [],
                    "reading_outline": {
                      "id": "outline-generated",
                      "article_revision_id": "revision-session",
                      "title": "Generated reading outline",
                      "status": "ready",
                      "summary": "Read this paper through its main claim and method.",
                      "questions": ["Which assumption carries the result?"],
                      "sourceRefs": ["2401.00001"],
                      "paperMasteryOutlines": [
                        {
                          "paperId": "article-session",
                          "paperTitle": "Session Paper",
                          "claim": ["The method improves reading workflow."],
                          "method": ["Trace the action plan before notes."],
                          "followUp": ["Compare with the static outline fallback."]
                        }
                      ]
                    },
                    "payload": {
                      "source_action_plan_id": "outline-action"
                    },
                    "preview": null,
                    "result": null,
                    "error": null,
                    "created_at": "2027-01-15T08:02:00Z",
                    "updated_at": "2027-01-15T08:02:00Z"
                  }
                ]
                """)
            case (5, "/libraries/backend-library/agent-action-plans"):
                XCTAssertEqual(request.httpMethod, "GET")
                let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                XCTAssertEqual(queryItems["article_revision_id"], "revision-session")
                return Self.jsonResponse("[\(Self.outlineActionJSON(status: "succeeded", finishedAt: "2027-01-15T08:02:00Z"))]")
            default:
                throw URLError(.unsupportedURL)
            }
        })
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [
            makeBlock(
                articleRevisionId: "revision-session",
                blockUid: "block-abstract",
                blockType: .abstract,
                sourceMarkdown: "We propose a reader-centered workflow that links reading, notes, and writing."
            ),
            makeBlock(
                articleRevisionId: "revision-session",
                blockUid: "block-method",
                blockType: .paragraph,
                sourceMarkdown: "The method traces each agent action plan before it reaches local notes."
            ),
            makeBlock(
                articleRevisionId: "revision-session",
                blockUid: "block-equation",
                blockType: .equation,
                sourceMarkdown: "\\\\mathcal{L}(\\\\theta)=\\\\sum_i f_\\\\theta(x_i)"
            ),
            makeBlock(
                articleRevisionId: "revision-session",
                blockUid: "block-evidence",
                blockType: .paragraph,
                sourceMarkdown: "Experiments show the workflow keeps provenance visible during note writing."
            )
        ]
        session.selectedBlockUid = "block-method"
        let outlineAction = makeOutlineActionPlan(status: .approved)
        session.researchActionPlans = [outlineAction]

        await session.runResearchOutlineActionPlan(outlineAction)

        XCTAssertEqual(requestCounter.current(), 5)
        XCTAssertFalse(session.researchAPIBusy)
        XCTAssertEqual(session.researchWorkbenchStatus, "Reading outline generated")
        XCTAssertNil(session.researchWorkbenchError)
        XCTAssertEqual(session.researchActionPlans.first?.status, .succeeded)
        XCTAssertEqual(session.researchPlans.count, 1)
        XCTAssertEqual(session.researchPlans.first?.readingOutline?.summary, "Read this paper through its main claim and method.")
        XCTAssertEqual(session.researchPlans.first?.readingOutline?.paperMasteryOutlines.first?.claim, ["The method improves reading workflow."])
    }

    func testRunReadingOutlineActionFallsBackToSucceededActionResultWhenPlanRefreshFails() async throws {
        let requestCounter = LockedCounter()
        let session = ReaderWorkbenchSession(researchAPIClient: makeClient { request in
            let requestNumber = requestCounter.increment()
            switch (requestNumber, request.url?.path) {
            case (1, "/libraries"):
                return Self.jsonResponse("""
                [
                  {
                    "id": "backend-library",
                    "path": "/tmp/library"
                  }
                ]
                """)
            case (2, "/libraries/backend-library/agent-action-plans/outline-action/start"):
                return Self.jsonResponse(Self.outlineActionJSON(status: "running"))
            case (3, "/libraries/backend-library/agent-action-plans/outline-action/succeed"):
                let data = try XCTUnwrap(Self.requestBodyData(from: request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let result = try XCTUnwrap(json["result"] as? [String: Any])
                let resultData = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                let resultJSON = try XCTUnwrap(String(data: resultData, encoding: .utf8))
                return Self.jsonResponse(Self.outlineActionJSON(
                    status: "succeeded",
                    finishedAt: "2027-01-15T08:02:00Z",
                    resultJSON: resultJSON
                ))
            case (4, "/libraries/backend-library/research-plans"):
                throw URLError(.cannotParseResponse)
            default:
                throw URLError(.unsupportedURL)
            }
        })
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        session.libraries = [
            Library(
                id: "local-library",
                name: "Local Library",
                path: "/tmp/library",
                createdAt: now,
                updatedAt: now
            )
        ]
        session.selectedLibraryId = "local-library"
        session.articles = [
            Article(
                id: "article-session",
                libraryId: "local-library",
                source: "arxiv",
                externalId: "2401.00001",
                title: "Session Paper",
                activeRevisionId: "revision-session"
            )
        ]
        session.selectedLibraryItem = .article(id: "article-session")
        session.blocks = [
            makeBlock(
                articleRevisionId: "revision-session",
                blockUid: "block-abstract",
                blockType: .abstract,
                sourceMarkdown: "We propose a local-first reader that keeps research planning attached to the paper."
            ),
            makeBlock(
                articleRevisionId: "revision-session",
                blockUid: "block-equation",
                blockType: .equation,
                sourceMarkdown: "\\\\mathcal{R}=\\\\nabla_\\\\theta f_\\\\theta(x)"
            )
        ]
        let outlineAction = makeOutlineActionPlan(status: .approved)
        session.researchActionPlans = [outlineAction]

        await session.runResearchOutlineActionPlan(outlineAction)
        let snapshot = ResearchWorkbenchSnapshot(session: session)

        XCTAssertEqual(requestCounter.current(), 4)
        XCTAssertEqual(session.researchWorkbenchStatus, "Reading outline generated")
        XCTAssertTrue(session.researchWorkbenchError?.contains("could not be refreshed") ?? false)
        XCTAssertEqual(session.researchActionPlans.first?.status, .succeeded)
        XCTAssertNotNil(session.researchActionPlans.first?.result?["reading_outline"])
        XCTAssertEqual(snapshot.outline.status, .ready)
        XCTAssertTrue(snapshot.outline.summary.contains("Session Paper"))
        XCTAssertTrue(snapshot.outline.paperMasteryOutlines.first?.claim.first?.contains("We propose") ?? false)
        XCTAssertTrue(snapshot.outline.paperMasteryOutlines.first?.equation.first?.contains("\\\\mathcal{R}") ?? false)
    }

    func testDismissResearchActionPlanRemovesRecoverableApprovedPlan() {
        let session = ReaderWorkbenchSession()
        let staleWrite = makeActionPlan(id: "stale-write", status: .approved)
        let otherWrite = makeActionPlan(id: "other-write", status: .pendingApproval)
        session.researchActionPlans = [staleWrite, otherWrite]
        session.researchAPIBusy = true
        session.researchWorkbenchError = "Previous error"

        session.dismissResearchActionPlan(staleWrite)

        XCTAssertEqual(session.researchActionPlans.map(\.id), ["other-write"])
        XCTAssertTrue(session.researchAPIBusy)
        XCTAssertEqual(session.researchWorkbenchStatus, "Action plan dismissed")
        XCTAssertNil(session.researchWorkbenchError)
    }

    private func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> BilinResearchAPIClient {
        ResearchStatusMockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResearchStatusMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return BilinResearchAPIClient(
            baseURL: URL(string: "http://127.0.0.1:8000")!,
            session: session
        )
    }

    nonisolated private static func jsonResponse(_ json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8000/mock")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(json.utf8))
    }

    nonisolated private static func requestBodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    nonisolated private static func outlineActionJSON(
        status: String,
        finishedAt: String? = nil,
        resultJSON: String? = nil
    ) -> String {
        let resultPayload = resultJSON ?? """
        {
          "status": "\(status == "succeeded" ? "done" : "running")"
        }
        """
        return """
        {
          "id": "outline-action",
          "kind": "generate_research_outline",
          "status": "\(status)",
          "title": "Generate reading outline: Session Paper",
          "description": "Prepare a paper-specific mastery outline.",
          "payload_hash": "payload-outline-action",
          "idempotency_key": "outline-key",
          "required_permissions": ["provider_call"],
          "payload": {
            "article_revision_id": "revision-session",
            "outline_policy": "paper_mastery"
          },
          "preview": {
            "scope": "selected_article"
          },
          "result": \(resultPayload),
          "steps": [],
          "created_at": "2027-01-15T08:00:00Z",
          "updated_at": "2027-01-15T08:02:00Z",
          "approved_at": "2027-01-15T08:01:00Z",
          "finished_at": \(finishedAt.map { "\"\($0)\"" } ?? "null"),
          "error": null
        }
        """
    }

    nonisolated private static func paperOutlineSkillJSON(enabled: Bool) -> String {
        let status = enabled ? "enabled" : "disabled"
        let grantedPermissions = enabled ? "[\"provider_call\"]" : "[]"
        return """
        {
          "id": "skill-paper-outline",
          "slug": "paper-outline",
          "title": "Paper Outline",
          "description": "Build per-paper mastery outlines.",
          "source_path": "/tmp/paper-outline/SKILL.md",
          "cache_path": null,
          "digest": "sha256:paper-outline",
          "digest_algorithm": "sha256",
          "version": null,
          "manifest_version": 1,
          "install_status": "discovered",
          "status": "\(status)",
          "enabled": \(enabled ? "true" : "false"),
          "declared_permissions": ["provider_call"],
          "granted_permissions": \(grantedPermissions),
          "input_shape": {},
          "output_shape": {},
          "supported_tasks": ["paper_reading"],
          "metadata": {},
          "created_at": "2027-01-15T08:00:00Z",
          "updated_at": "2027-01-15T08:01:00Z"
        }
        """
    }

    nonisolated private static func zoteroImportActionJSON(
        status: String,
        libraryPath: String,
        attachmentPath: String,
        result: [String: Any]? = nil
    ) -> String {
        let resultJSON: String
        if let result,
           JSONSerialization.isValidJSONObject(result),
           let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            resultJSON = string
        } else {
            resultJSON = "null"
        }
        let finishedAt = status == "succeeded" ? "\"2027-01-15T08:02:00Z\"" : "null"
        return """
        {
          "id": "zotero-import-action",
          "kind": "download_paper",
          "status": "\(status)",
          "title": "Prepare Zotero arXiv import",
          "description": "Confirm arXiv download and Bilin library import for Zotero Paper.",
          "payload_hash": "payload-zotero-import",
          "idempotency_key": "zotero-import-key",
          "required_permissions": ["network", "download_paper", "import_library", "write_library_bundle"],
          "payload": {
            "source": "zotero",
            "zotero_item_id": "42",
            "zotero_key": "ZOT42",
            "title": "Zotero Paper",
            "arxiv_id": "2401.00001",
            "local_library_id": "local-library",
            "local_library_path": "\(libraryPath)",
            "attachment_file_paths": "\(attachmentPath)"
          },
          "preview": {
            "candidate_summary": "Zotero Paper\\narXiv: 2401.00001",
            "import_summary": "Stage the Zotero import bundle."
          },
          "result": \(resultJSON),
          "steps": [
            {
              "id": "download-step",
              "kind": "download",
              "title": "Download arXiv paper",
              "required_permissions": ["network", "download_paper"],
              "payload": {
                "arxiv_id": "2401.00001"
              }
            },
            {
              "id": "import-step",
              "kind": "import_item",
              "title": "Import Zotero item into Bilin",
              "required_permissions": ["import_library", "write_library_bundle"],
              "payload": {
                "zotero_item_id": "42"
              }
            }
          ],
          "created_at": "2027-01-15T08:00:00Z",
          "updated_at": "2027-01-15T08:01:00Z",
          "approved_at": "2027-01-15T08:00:30Z",
          "finished_at": \(finishedAt),
          "error": null
        }
        """
    }

    private func makeBlock(
        articleRevisionId: String = "revision-1",
        blockUid: String = "block-1",
        blockType: DocumentBlockKind = .paragraph,
        sourceMarkdown: String = "Source paragraph."
    ) -> DocumentBlock {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return DocumentBlock(
            id: blockUid,
            articleRevisionId: articleRevisionId,
            blockUid: blockUid,
            structuralPath: "00001",
            blockType: blockType,
            contentHash: "hash-\(blockUid)",
            sourceMarkdown: sourceMarkdown,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeZoteroImportActionPlan(
        status: AgentActionStatus,
        libraryPath: String,
        attachmentPath: String
    ) -> AgentActionPlan {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return AgentActionPlan(
            id: "zotero-import-action",
            kind: .downloadPaper,
            status: status,
            title: "Prepare Zotero arXiv import",
            summary: "Confirm arXiv download and Bilin library import for Zotero Paper.",
            requestedPermissions: [.network, .downloadPaper, .importLibrary, .writeLibraryBundle],
            steps: [],
            payloadHash: "payload-zotero-import",
            payload: [
                "source": "zotero",
                "zotero_item_id": "42",
                "zotero_key": "ZOT42",
                "title": "Zotero Paper",
                "arxiv_id": "2401.00001",
                "local_library_id": "local-library",
                "local_library_path": libraryPath,
                "attachment_file_paths": attachmentPath
            ],
            preview: [
                "candidate_summary": "Zotero Paper\narXiv: 2401.00001",
                "import_summary": "Stage the Zotero import bundle."
            ],
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeActionPlan(id: String, status: AgentActionStatus) -> AgentActionPlan {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return AgentActionPlan(
            id: id,
            kind: .writeObsidian,
            status: status,
            title: id,
            summary: "Test action plan",
            requestedPermissions: [],
            steps: [],
            payloadHash: "payload-\(id)",
            payload: [
                "block_uid": "block-1",
                "target_path": "/tmp/current-vault/Papers/No paper selected.md"
            ],
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeOutlineActionPlan(status: AgentActionStatus) -> AgentActionPlan {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return AgentActionPlan(
            id: "outline-action",
            kind: .generateResearchOutline,
            status: status,
            title: "Generate reading outline: Session Paper",
            summary: "Prepare a paper-specific mastery outline.",
            requestedPermissions: [.providerCall],
            steps: [],
            payloadHash: "payload-outline-action",
            payload: [
                "article_revision_id": "revision-session",
                "outline_policy": "paper_mastery"
            ],
            preview: [
                "scope": "selected_article"
            ],
            createdAt: now,
            updatedAt: now
        )
    }

    private func makePaperOutlineSkill(
        status: ResearchSkillStatus = .enabled,
        supportedTasks: [ResearchSkillTask] = [.paperReading]
    ) -> ResearchSkill {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return ResearchSkill(
            id: "skill-paper-outline",
            slug: "paper-outline",
            title: "Paper Outline",
            description: "Build per-paper mastery outlines.",
            digest: "sha256:paper-outline",
            source: ResearchSkillSource(kind: .project, identifier: "/tmp/paper-outline/SKILL.md"),
            status: status,
            permissions: [.providerCall],
            supportedTasks: supportedTasks,
            createdAt: now,
            updatedAt: now
        )
    }

    private func isolatedWorkspaceConfigurationCoordinator() -> WorkspaceConfigurationCoordinator {
        let configurationURL = temporaryDirectory()
            .appendingPathComponent("workspace-configuration.json")
        let store = WorkspaceConfigurationStore(configurationFileURL: configurationURL)
        return WorkspaceConfigurationCoordinator(
            configurationStore: store,
            pathDetector: WorkspacePathDetector(homeDirectoryURL: temporaryDirectory()),
            bookmarkDataProvider: { _ in nil }
        )
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("bilin-research-status-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func current() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class ResearchStatusMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
