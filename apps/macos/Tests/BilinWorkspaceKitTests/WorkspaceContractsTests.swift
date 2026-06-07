import XCTest
@testable import BilinWorkspaceKit

final class WorkspaceContractsTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testCodableRoundTripPreservesWorkspaceContracts() throws {
        let bundle = WorkspaceContractBundle(
            outline: makeOutline(),
            noteBridge: makeNoteBridge(),
            writingProject: makeWritingProject(kind: .typst),
            actionPlan: makeActionPlan(),
            researchSkill: makeSkill(status: .enabled),
            pendingFilePatch: makePatch(status: .previewReady)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceContractBundle.self, from: data)

        XCTAssertEqual(decoded, bundle)
    }

    func testSourceBlockProvenanceKeepsStableAnchorFields() {
        let provenance = makeProvenance()
        let bridge = makeNoteBridge()

        XCTAssertEqual(provenance.articleRevisionId, "revision-1")
        XCTAssertEqual(provenance.blockUid, "block-7")
        XCTAssertEqual(provenance.contentHash, "sha256-source")
        XCTAssertEqual(provenance.stableBlockAnchor, "revision-1#block-7#sha256-source")
        XCTAssertEqual(bridge.blockAnchor, "^ilios-revision-1-block-7")
        XCTAssertEqual(bridge.provenance.stableBlockAnchor, provenance.stableBlockAnchor)
    }

    func testPendingFilePatchStatesTrackPreviewApprovalConflictAndTerminalOutcomes() {
        let preview = makePatch(status: .previewReady)
        XCTAssertFalse(preview.status.isTerminal)
        XCTAssertEqual(preview.baseFileHash, "sha256-base")
        XCTAssertNil(preview.appliedFileHash)

        let approved = makePatch(status: .approved, actionPlanId: "action-1")
        XCTAssertFalse(approved.status.isTerminal)
        XCTAssertEqual(approved.actionPlanId, "action-1")

        let rejected = makePatch(status: .rejected)
        XCTAssertTrue(rejected.status.isTerminal)

        let conflict = FilePatchConflict(
            reason: .fileChangedSincePreview,
            expectedHash: "sha256-base",
            observedHash: "sha256-new",
            message: "Target file changed after preview."
        )
        let conflicted = makePatch(status: .conflicted, conflict: conflict)
        XCTAssertEqual(conflicted.conflict?.reason, .fileChangedSincePreview)
        XCTAssertEqual(conflicted.conflict?.observedHash, "sha256-new")
        XCTAssertFalse(conflicted.status.isTerminal)
    }

    func testWritingProjectKindsRepresentTypstTexAndMixedProjects() {
        let typst = makeWritingProject(kind: .typst, mainFilePath: "paper.typ")
        let tex = makeWritingProject(kind: .tex, mainFilePath: "main.tex")
        let mixed = makeWritingProject(kind: .mixed, mainFilePath: "draft.tex")

        XCTAssertEqual(typst.kind, .typst)
        XCTAssertEqual(tex.kind, .tex)
        XCTAssertEqual(mixed.kind, .mixed)
        XCTAssertEqual(typst.bibliographyFilePaths, ["refs.bib"])
        XCTAssertEqual(Set([typst.kind, tex.kind, mixed.kind]), Set([.typst, .tex, .mixed]))
    }

    func testAgentActionPlanCarriesExplicitPermissions() {
        let plan = makeActionPlan()

        XCTAssertEqual(plan.kind, .editManuscript)
        XCTAssertEqual(plan.status, .pendingApproval)
        XCTAssertEqual(plan.payloadHash, "sha256-payload")
        XCTAssertEqual(plan.payload["target_path"], "/Users/example/DACDraft/paper.typ")
        XCTAssertEqual(plan.preview?["patch"], "#block[Related work]")
        XCTAssertEqual(plan.result?["target_path"], "/Users/example/DACDraft/paper.typ")
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertTrue(plan.requestedPermissions.contains(.editManuscript))
        XCTAssertTrue(plan.requestedPermissions.contains(.providerCall))
        XCTAssertEqual(plan.steps.first?.permission, .providerCall)
        XCTAssertEqual(plan.steps.last?.permission, .editManuscript)
    }

    func testResearchSkillEnabledAndDisabledState() {
        let disabled = makeSkill(status: .disabled)
        let enabled = makeSkill(status: .enabled)

        XCTAssertFalse(disabled.isEnabled)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertEqual(disabled.permissions, [.network, .providerCall])
        XCTAssertEqual(enabled.supportedTasks, [.literatureReview, .writing])
    }

    func testResearchPlanDecodesBackendReadingOutlineAndPaperMasteryAliases() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let data = try XCTUnwrap(
            """
            {
              "id": "plan-1",
              "kind": "paper_reading",
              "status": "active",
              "title": "Draft from candidate papers",
              "article_revision_id": "rev-1",
              "payload_hash": "hash-plan",
              "candidate_papers": [
                {
                  "id": "2401.00001",
                  "score": 0.91
                }
              ],
              "reading_outline": {
                "title": "Draft from candidate papers",
                "summary": "Follow the proof before implementation details.",
                "sections": [
                  {
                    "title": "Setup",
                    "block_uid": "s-1"
                  }
                ],
                "questions": ["Where is convexity used?"],
                "source_refs": ["s-1"],
                "paperMasteryOutlines": [
                  {
                    "paper_id": "2401.00001",
                    "paper_title": "A sample paper",
                    "claim": ["The method converges."],
                    "method": ["Constructive proof"],
                    "equation": ["x >= y"],
                    "evidence": ["benchmark A"],
                    "limitation": ["single dataset"],
                    "followUp": ["test on larger baselines"]
                  }
                ],
                "metadata": {
                  "seed": "2401.00001"
                }
              },
              "payload": {
                "skill_provenance": {
                  "skill_slug": "paper-outline"
                }
              },
              "preview": {
                "paper_count": 1
              },
              "result": {
                "ready": true
              },
              "error": null,
              "created_at": "2027-01-15T08:00:00Z",
              "updated_at": "2027-01-15T08:00:00Z"
            }
            """.data(using: .utf8)
        )

        let plan = try decoder.decode(ResearchPlan.self, from: data)

        XCTAssertEqual(plan.kind, .paperReading)
        XCTAssertEqual(plan.status, .active)
        XCTAssertEqual(plan.candidatePapers.first?["score"], .number(0.91))
        XCTAssertEqual(plan.readingOutline?.summary, "Follow the proof before implementation details.")
        XCTAssertEqual(plan.readingOutline?.sections.first?["block_uid"], .string("s-1"))
        XCTAssertEqual(plan.readingOutline?.paperMasteryOutlines.first?.paperId, "2401.00001")
        XCTAssertEqual(plan.readingOutline?.paperMasteryOutlines.first?.paperTitle, "A sample paper")
        XCTAssertEqual(plan.readingOutline?.paperMasteryOutlines.first?.followUp, ["test on larger baselines"])
        XCTAssertEqual(plan.readingOutline?.metadata["seed"], .string("2401.00001"))
        XCTAssertEqual(plan.payload["skill_provenance"], .object(["skill_slug": .string("paper-outline")]))
        XCTAssertEqual(plan.preview?["paper_count"], .number(1))
        XCTAssertEqual(plan.result?["ready"], .bool(true))
    }

    private func makeOutline() -> ReadingOutline {
        ReadingOutline(
            id: "outline-1",
            articleRevisionId: "revision-1",
            title: "Master the method",
            status: .ready,
            items: [
                ReadingOutlineItem(
                    id: "outline-item-1",
                    kind: .method,
                    title: "Sparse attention schedule",
                    summaryMarkdown: "Understand how the schedule bounds memory.",
                    importance: .high,
                    sourceProvenance: [makeProvenance()]
                )
            ],
            sourceProvenance: [makeProvenance()],
            generatedAt: baseDate,
            updatedAt: baseDate
        )
    }

    private func makeNoteBridge() -> NoteBridge {
        NoteBridge(
            id: "note-bridge-1",
            articleRevisionId: "revision-1",
            status: .pendingApproval,
            targetVault: NoteBridgeVault(
                id: "vault-1",
                name: "Research Notes",
                rootPath: "/Users/example/Notes"
            ),
            targetNotePath: "Papers/Bilin.md",
            headingPath: ["Papers", "Sparse attention"],
            blockAnchor: "^ilios-revision-1-block-7",
            calloutType: .important,
            tags: ["#bilin/key-idea"],
            sourcePayload: NoteBridgePayload(
                blockUid: "block-7",
                language: "en",
                markdown: "The method bounds memory by grouping tokens.",
                contentHash: "sha256-source"
            ),
            translationPayload: NoteBridgePayload(
                blockUid: "block-7",
                language: "zh-CN",
                markdown: "Translated method note.",
                contentHash: "sha256-translation"
            ),
            pendingPatch: makePatch(status: .pendingApproval),
            provenance: makeProvenance(),
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }

    private func makeWritingProject(
        kind: WritingProjectKind,
        mainFilePath: String = "paper.typ"
    ) -> WritingProject {
        WritingProject(
            id: "writing-project-\(kind.rawValue)",
            name: "DAC Draft",
            rootPath: "/Users/example/DACDraft",
            kind: kind,
            status: .linked,
            mainFilePath: mainFilePath,
            bibliographyFilePaths: ["refs.bib"],
            detectedFilePaths: [mainFilePath, "refs.bib"],
            acceptedPatchIds: ["patch-accepted"],
            pendingPatches: [makePatch(status: .previewReady)],
            sourceProvenance: [makeProvenance()],
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }

    private func makeActionPlan() -> AgentActionPlan {
        AgentActionPlan(
            id: "action-1",
            kind: .editManuscript,
            status: .pendingApproval,
            title: "Insert related-work paragraph",
            summary: "Prepare one manuscript insertion from the selected block.",
            requestedPermissions: [.providerCall, .editManuscript],
            steps: [
                AgentActionStep(
                    id: "step-1",
                    kind: .callProvider,
                    title: "Draft paragraph",
                    permission: .providerCall
                ),
                AgentActionStep(
                    id: "step-2",
                    kind: .writeFile,
                    title: "Apply accepted patch",
                    targetPath: "paper.typ",
                    permission: .editManuscript
                )
            ],
            payloadHash: "sha256-payload",
            payload: [
                "target_path": "/Users/example/DACDraft/paper.typ",
                "block_uid": "block-7"
            ],
            preview: ["patch": "#block[Related work]"],
            result: [
                "target_path": "/Users/example/DACDraft/paper.typ",
                "bytes": "128"
            ],
            idempotencyKey: "action-key-1",
            relatedPatchIds: ["patch-1"],
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }

    private func makeSkill(status: ResearchSkillStatus) -> ResearchSkill {
        ResearchSkill(
            id: "skill-1",
            slug: "literature-review",
            title: "Literature Review",
            description: "Find and compare related work.",
            version: "1.0.0",
            digest: "sha256-skill",
            source: ResearchSkillSource(kind: .user, identifier: "~/.codex/skills/research-lit"),
            sourcePath: "/Users/example/.codex/skills/research-lit/SKILL.md",
            cachePath: "/Users/example/Library/Application Support/Bilin/skill-cache/research-lit",
            status: status,
            permissions: [.network, .providerCall],
            inputShape: "topic, seed paper, constraints",
            outputShape: "ranked papers and rationale",
            supportedTasks: [.literatureReview, .writing],
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }

    private func makePatch(
        status: PendingFilePatchStatus,
        conflict: FilePatchConflict? = nil,
        actionPlanId: String? = nil
    ) -> PendingFilePatch {
        PendingFilePatch(
            id: "patch-1",
            kind: .typstInsertion,
            format: .typst,
            status: status,
            targetPath: "paper.typ",
            targetAnchor: "related-work",
            targetSectionPath: ["Related Work"],
            patchText: "Bilin keeps source provenance next to the insertion.",
            previewMarkdown: "Preview: Bilin keeps source provenance next to the insertion.",
            baseFileHash: "sha256-base",
            appliedFileHash: status == .applied ? "sha256-applied" : nil,
            conflict: conflict,
            provenance: [makeProvenance()],
            actionPlanId: actionPlanId,
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }

    private func makeProvenance() -> SourceBlockProvenance {
        SourceBlockProvenance(
            libraryId: "library-1",
            articleId: "article-1",
            articleRevisionId: "revision-1",
            blockUid: "block-7",
            structuralPath: "section.introduction.paragraph.3",
            contentHash: "sha256-source",
            contextHash: "sha256-context",
            sourceLanguage: "en",
            translationId: "translation-1",
            translationLanguage: "zh-CN",
            translationHash: "sha256-translation",
            selectedTextHash: "sha256-selection",
            capturedAt: baseDate
        )
    }
}

private struct WorkspaceContractBundle: Codable, Hashable {
    var outline: ReadingOutline
    var noteBridge: NoteBridge
    var writingProject: WritingProject
    var actionPlan: AgentActionPlan
    var researchSkill: ResearchSkill
    var pendingFilePatch: PendingFilePatch
}
