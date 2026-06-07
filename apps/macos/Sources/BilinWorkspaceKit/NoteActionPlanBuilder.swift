import Foundation

public struct NoteActionPlanBuildResult: Hashable, Sendable {
    public var targetNotePath: String
    public var blockAnchor: String
    public var targetPath: String?
    public var baseFileHash: String?
    public var patchText: String
    public var actionPlanPayload: [String: String]
    public var actionPlanPreview: [String: String]
    public var actionPlanStepPayload: [String: String]
    public var actionPlanDraft: AgentActionPlanDraft
    public var stepDraft: AgentActionPlanStepDraft

    public init(
        targetNotePath: String,
        blockAnchor: String,
        targetPath: String?,
        baseFileHash: String?,
        patchText: String,
        actionPlanPayload: [String: String],
        actionPlanPreview: [String: String],
        actionPlanStepPayload: [String: String],
        actionPlanDraft: AgentActionPlanDraft,
        stepDraft: AgentActionPlanStepDraft
    ) {
        self.targetNotePath = targetNotePath
        self.blockAnchor = blockAnchor
        self.targetPath = targetPath
        self.baseFileHash = baseFileHash
        self.patchText = patchText
        self.actionPlanPayload = actionPlanPayload
        self.actionPlanPreview = actionPlanPreview
        self.actionPlanStepPayload = actionPlanStepPayload
        self.actionPlanDraft = actionPlanDraft
        self.stepDraft = stepDraft
    }
}

public struct NoteActionPlanBuilder: Sendable {
    public init() {}

    public func build(
        articleTitle: String,
        articleRevisionId: String,
        blockUid: String,
        sourceMarkdown: String,
        translationMarkdown: String? = nil,
        selectedTextHash: String? = nil,
        vaultPath: String? = nil,
        baseFileHash: String? = nil,
        recoveryContext: ActionPlanRecoveryContext? = nil
    ) -> NoteActionPlanBuildResult {
        let targetNotePath = "Papers/\(Self.noteFileName(for: articleTitle)).md"
        let blockAnchor = Self.blockAnchor(articleRevisionId: articleRevisionId, blockUid: blockUid)
        let targetPath = vaultPath.map { ($0 as NSString).appendingPathComponent(targetNotePath) }
        let patchText = Self.patchText(
            source: sourceMarkdown,
            translation: translationMarkdown,
            anchor: blockAnchor
        )
        let payload = Self.payload(
            articleRevisionId: articleRevisionId,
            blockUid: blockUid,
            blockAnchor: blockAnchor,
            targetNotePath: targetNotePath,
            sourceMarkdown: sourceMarkdown,
            translationMarkdown: translationMarkdown,
            selectedTextHash: selectedTextHash,
            vaultPath: vaultPath,
            targetPath: targetPath,
            baseFileHash: baseFileHash,
            recoveryContext: recoveryContext
        )
        let preview = ["patch": patchText].merging(
            recoveryContext?.previewFields ?? [:],
            uniquingKeysWith: { _, new in new }
        )
        let stepPayload = [
            "target_note": targetNotePath,
            "block_uid": blockUid
        ]
        let stepDraft = AgentActionPlanStepDraft(
            kind: "render_patch",
            title: "Render Markdown patch",
            requiredPermissions: [.writeObsidian],
            payload: stepPayload,
            preview: preview
        )
        let actionPlanDraft = AgentActionPlanDraft(
            kind: .writeObsidian,
            title: "Write Obsidian note patch",
            description: "Preview Markdown note patch for \(blockUid).",
            articleRevisionId: articleRevisionId,
            idempotencyKey: Self.idempotencyKey(
                articleRevisionId: articleRevisionId,
                blockUid: blockUid,
                targetNotePath: targetNotePath,
                vaultPath: vaultPath,
                targetPath: targetPath,
                baseFileHash: baseFileHash,
                selectedTextHash: selectedTextHash,
                recoveryContext: recoveryContext
            ),
            requiredPermissions: [.writeObsidian],
            payload: payload,
            preview: preview,
            steps: [stepDraft]
        )
        return NoteActionPlanBuildResult(
            targetNotePath: targetNotePath,
            blockAnchor: blockAnchor,
            targetPath: targetPath,
            baseFileHash: baseFileHash,
            patchText: patchText,
            actionPlanPayload: payload,
            actionPlanPreview: preview,
            actionPlanStepPayload: stepPayload,
            actionPlanDraft: actionPlanDraft,
            stepDraft: stepDraft
        )
    }

    public static func blockAnchor(articleRevisionId: String, blockUid: String) -> String {
        "^ilios-\(articleRevisionId)-\(blockUid)"
    }

    public static func patchText(source: String, translation: String?, anchor: String) -> String {
        var parts = ["> [!note] Source block \(anchor)"]
        parts.append(contentsOf: calloutLines(for: source))
        if let translation, !translation.isEmpty {
            parts.append(contentsOf: calloutLines(for: translation))
        }
        parts.append("")
        return parts.joined(separator: "\n")
    }

    private static func calloutLines(for markdown: String) -> [String] {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
    }

    public static func noteFileName(for title: String) -> String {
        let replaced = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        let trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "Untitled Paper" : trimmed).prefix(56))
    }

    private static func payload(
        articleRevisionId: String,
        blockUid: String,
        blockAnchor: String,
        targetNotePath: String,
        sourceMarkdown: String,
        translationMarkdown: String?,
        selectedTextHash: String?,
        vaultPath: String?,
        targetPath: String?,
        baseFileHash: String?,
        recoveryContext: ActionPlanRecoveryContext?
    ) -> [String: String] {
        var payload = [
            "article_revision_id": articleRevisionId,
            "block_uid": blockUid,
            "block_anchor": blockAnchor,
            "target_note": targetNotePath,
            "source_markdown": sourceMarkdown
        ]
        if let vaultPath, let targetPath, let baseFileHash {
            payload["target_vault_path"] = vaultPath
            payload["target_path"] = targetPath
            payload["base_file_hash"] = baseFileHash
        }
        if let translationMarkdown, !translationMarkdown.isEmpty {
            payload["translation_markdown"] = translationMarkdown
        }
        if let selectedTextHash, !selectedTextHash.isEmpty {
            payload["selected_text_hash"] = selectedTextHash
        }
        if let recoveryContext {
            payload.merge(recoveryContext.payloadFields) { _, new in new }
        }
        return payload
    }

    private static func idempotencyKey(
        articleRevisionId: String,
        blockUid: String,
        targetNotePath: String,
        vaultPath: String?,
        targetPath: String?,
        baseFileHash: String?,
        selectedTextHash: String?,
        recoveryContext: ActionPlanRecoveryContext?
    ) -> String {
        let targetIdentity = targetPath ?? [
            vaultPath ?? "no-vault",
            targetNotePath
        ].joined(separator: "/")
        let baseIdentity = baseFileHash ?? LocalFilePatchExecutor.contentHash(for: "")
        let recoveryIdentity = recoveryContext.map {
            "\($0.recoveringFromActionPlanId):\($0.observedFileHash)"
        } ?? "fresh"
        let fingerprint = LocalFilePatchExecutor.contentHash(
            for: [
                articleRevisionId,
                blockUid,
                targetIdentity,
                baseIdentity,
                selectedTextHash ?? "whole-block",
                recoveryIdentity
            ].joined(separator: "\u{1f}")
        )
        return "note-bridge-\(articleRevisionId)-\(blockUid)-\(fingerprint.prefix(16))"
    }
}
