import Foundation

public struct WritingActionPlanDraft: Hashable, Sendable {
    public var actionPlanPayload: [String: String]
    public var actionPlanPreview: [String: String]
    public var actionPlanStepPayload: [String: String]
    public var actionPlanDraft: AgentActionPlanDraft
    public var stepDraft: AgentActionPlanStepDraft
    public var writingPatchDraft: WritingPatchDraft

    public init(
        actionPlanPayload: [String: String],
        actionPlanPreview: [String: String],
        actionPlanStepPayload: [String: String],
        actionPlanDraft: AgentActionPlanDraft,
        stepDraft: AgentActionPlanStepDraft,
        writingPatchDraft: WritingPatchDraft
    ) {
        self.actionPlanPayload = actionPlanPayload
        self.actionPlanPreview = actionPlanPreview
        self.actionPlanStepPayload = actionPlanStepPayload
        self.actionPlanDraft = actionPlanDraft
        self.stepDraft = stepDraft
        self.writingPatchDraft = writingPatchDraft
    }
}

public struct WritingActionPlanBuilder: Sendable {
    public init() {}

    public func build(
        mainFileText: String,
        targetPath: String,
        sourceBlock: String,
        articleRevisionId: String,
        blockUid: String,
        baseFileHash: String,
        targetSectionPreference: String,
        selectedTextHash: String? = nil,
        patchId: String? = nil,
        now: Date = Date(timeIntervalSince1970: 0),
        recoveryContext: ActionPlanRecoveryContext? = nil
    ) -> WritingActionPlanDraft {
        let planner = WritingPatchPlanner()
        let effectivePatchId = patchId ?? WritingActionPlanBuilder.makePatchIdentifier(
            articleRevisionId: articleRevisionId,
            blockUid: blockUid,
            targetPath: targetPath
        )
        var draft = planner.planInsertion(
            sourceBlock: sourceBlock,
            targetSectionPreference: targetSectionPreference,
            mainFileText: mainFileText,
            fileExtension: URL(fileURLWithPath: targetPath).pathExtension,
            targetPath: targetPath,
            patchId: effectivePatchId,
            now: now
        )

        draft.pendingPatch.baseFileHash = baseFileHash

        var payload = Self.makePayload(
            targetPath: targetPath,
            baseFileHash: baseFileHash,
            sourceBlock: sourceBlock,
            blockUid: blockUid,
            articleRevisionId: articleRevisionId,
            selectedTextHash: selectedTextHash,
            draft: draft
        )
        if let recoveryContext {
            payload.merge(recoveryContext.payloadFields) { _, new in new }
        }
        let preview: [String: String] = payload
            .merging(["preview_markdown": draft.pendingPatch.previewMarkdown ?? draft.pendingPatch.patchText]) { _, new in new }
            .merging(recoveryContext?.previewFields ?? [:]) { _, new in new }

        let actionPlanStepPayload = Self.makeStepPayload(from: payload)
        let actionPlanDraft = AgentActionPlanDraft(
            kind: .editManuscript,
            title: "Prepare manuscript insertion",
            description: "Preview manuscript patch for \(blockUid).",
            articleRevisionId: articleRevisionId,
            idempotencyKey: Self.idempotencyKey(
                articleRevisionId: articleRevisionId,
                blockUid: blockUid,
                targetPath: targetPath,
                baseFileHash: baseFileHash,
                selectedTextHash: selectedTextHash,
                recoveryContext: recoveryContext
            ),
            requiredPermissions: [.editManuscript],
            payload: payload,
            preview: preview,
            steps: [
                Self.makeStepDraft(
                    blockUid: blockUid,
                    targetPath: targetPath,
                    payload: actionPlanStepPayload,
                    preview: preview,
                    patchText: draft.pendingPatch.patchText
                )
            ]
        )
        let stepDraft = actionPlanDraft.steps.first ?? Self.makeStepDraft(
            blockUid: blockUid,
            targetPath: targetPath,
            payload: actionPlanStepPayload,
            preview: preview,
            patchText: draft.pendingPatch.patchText
        )
        return WritingActionPlanDraft(
            actionPlanPayload: payload,
            actionPlanPreview: preview,
            actionPlanStepPayload: actionPlanStepPayload,
            actionPlanDraft: actionPlanDraft,
            stepDraft: stepDraft,
            writingPatchDraft: draft
        )
    }

    private static func makePayload(
        targetPath: String,
        baseFileHash: String,
        sourceBlock: String,
        blockUid: String,
        articleRevisionId: String,
        selectedTextHash: String?,
        draft: WritingPatchDraft
    ) -> [String: String] {
        var payload = [
            "target_path": targetPath,
            "base_file_hash": baseFileHash,
            "source_markdown": sourceBlock,
            "block_uid": blockUid,
            "article_revision_id": articleRevisionId,
            "target_anchor": draft.pendingPatch.targetAnchor ?? "",
            "target_section_path": encodeStringList(draft.pendingPatch.targetSectionPath),
            "insertion_mode": draft.insertionMode.rawValue,
            "insertion_line": draft.insertionLine.flatMap(String.init) ?? "",
            "bibliography_paths": encodeStringList(draft.bibliographyFilePaths),
            "patch": draft.pendingPatch.patchText
        ]
        if let selectedTextHash, !selectedTextHash.isEmpty {
            payload["selected_text_hash"] = selectedTextHash
        }
        return payload
    }

    private static func makeStepPayload(from payload: [String: String]) -> [String: String] {
        payload
    }

    private static func makeStepDraft(
        blockUid: String,
        targetPath: String,
        payload: [String: String],
        preview: [String: String],
        patchText: String
    ) -> AgentActionPlanStepDraft {
        AgentActionPlanStepDraft(
            kind: AgentActionStepKind.writeFile.rawValue,
            title: "Write block \(blockUid) into \(targetPath)",
            requiredPermissions: [.editManuscript],
            payload: payload,
            preview: preview.merging(["patch": patchText]) { _, new in new }
        )
    }

    private static func makePatchIdentifier(
        articleRevisionId: String,
        blockUid: String,
        targetPath: String
    ) -> String {
        [
            "writing-patch",
            Self.slugify(articleRevisionId),
            Self.slugify(blockUid),
            Self.slugify(targetPath)
        ].joined(separator: "-")
    }

    private static func idempotencyKey(
        articleRevisionId: String,
        blockUid: String,
        targetPath: String,
        baseFileHash: String,
        selectedTextHash: String?,
        recoveryContext: ActionPlanRecoveryContext?
    ) -> String {
        var base = "writing-dock-\(articleRevisionId)-\(blockUid)-\(targetPath)-\(baseFileHash)"
        if let selectedTextHash, !selectedTextHash.isEmpty {
            base += "-selection-\(selectedTextHash)"
        }
        guard let recoveryContext else {
            return base
        }
        return "\(base)-recovery-\(recoveryContext.recoveringFromActionPlanId)-\(recoveryContext.observedFileHash)"
    }

    private static func slugify(_ value: String) -> String {
        let normalized = value.lowercased()
            .unicodeScalars
            .map { scalar -> String in
                if CharacterSet.alphanumerics.contains(scalar) {
                    return String(scalar)
                }
                if scalar == "_" || scalar == "-" {
                    return String(scalar)
                }
                return "-"
            }
            .joined()
        return normalized.trimmingCharacters(
            in: CharacterSet(charactersIn: "-_")
        )
    }

    private static func encodeStringList(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: values,
            options: [.fragmentsAllowed]
        ), let encoded = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return encoded
    }
}
