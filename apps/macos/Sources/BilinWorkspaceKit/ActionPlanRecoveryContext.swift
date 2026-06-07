import Foundation

public struct ActionPlanRecoveryContext: Hashable, Sendable {
    public var recoveringFromActionPlanId: String
    public var targetPath: String?
    public var targetNote: String?
    public var previousBaseFileHash: String?
    public var observedFileHash: String
    public var errorMessage: String?
    public var recoveredAt: Date

    public init(
        recoveringFromActionPlanId: String,
        targetPath: String? = nil,
        targetNote: String? = nil,
        previousBaseFileHash: String? = nil,
        observedFileHash: String,
        errorMessage: String? = nil,
        recoveredAt: Date = Date()
    ) {
        self.recoveringFromActionPlanId = recoveringFromActionPlanId
        self.targetPath = targetPath
        self.targetNote = targetNote
        self.previousBaseFileHash = previousBaseFileHash
        self.observedFileHash = observedFileHash
        self.errorMessage = errorMessage
        self.recoveredAt = recoveredAt
    }

    public var payloadFields: [String: String] {
        var fields = [
            "recovery_kind": "regenerate_patch",
            "recovering_from_action_plan_id": recoveringFromActionPlanId,
            "observed_file_hash": observedFileHash,
            "recovered_at": Self.iso8601.string(from: recoveredAt),
            "recovery_patch_strategy": "rebase_on_current_target"
        ]
        if let targetPath, !targetPath.isEmpty {
            fields["recovery_target_path"] = targetPath
        }
        if let targetNote, !targetNote.isEmpty {
            fields["recovery_target_note"] = targetNote
        }
        if let previousBaseFileHash, !previousBaseFileHash.isEmpty {
            fields["previous_base_file_hash"] = previousBaseFileHash
        }
        if let errorMessage, !errorMessage.isEmpty {
            fields["previous_error_message"] = errorMessage
        }
        return fields
    }

    public var previewFields: [String: String] {
        var fields = payloadFields
        fields["recovery_summary"] = [
            "Regenerated from \(recoveringFromActionPlanId)",
            "Previous base: \(previousBaseFileHash ?? "not recorded")",
            "Observed base: \(observedFileHash)"
        ].joined(separator: "\n")
        return fields
    }

    fileprivate static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

public struct ActionPlanRecoveryContextBuilder: Sendable {
    public init() {}

    public func build(
        from actionPlan: AgentActionPlan,
        configuration: WorkspaceConfiguration,
        recoveredAt: Date = Date()
    ) -> ActionPlanRecoveryContext {
        let targetNote = actionPlan.payload["target_note"]
        let targetPath = Self.targetPath(for: actionPlan, configuration: configuration)
        let currentText = targetPath.flatMap {
            try? String(contentsOf: URL(fileURLWithPath: $0), encoding: .utf8)
        } ?? ""
        return ActionPlanRecoveryContext(
            recoveringFromActionPlanId: actionPlan.id,
            targetPath: targetPath,
            targetNote: targetNote,
            previousBaseFileHash: Self.previousBaseHash(for: actionPlan),
            observedFileHash: LocalFilePatchExecutor.contentHash(for: currentText),
            errorMessage: actionPlan.errorMessage ?? actionPlan.error?["message"] ?? actionPlan.error?["code"],
            recoveredAt: recoveredAt
        )
    }

    private static func targetPath(
        for actionPlan: AgentActionPlan,
        configuration: WorkspaceConfiguration
    ) -> String? {
        if let targetPath = actionPlan.payload["target_path"], !targetPath.isEmpty {
            return targetPath
        }
        if let targetPath = actionPlan.error?["target_path"], !targetPath.isEmpty {
            return targetPath
        }
        if
            let targetNote = actionPlan.payload["target_note"],
            let vault = configuration.selectedObsidianVault
        {
            return (vault.path as NSString).appendingPathComponent(targetNote)
        }
        return actionPlan.steps.compactMap(\.targetPath).first
    }

    private static func previousBaseHash(for actionPlan: AgentActionPlan) -> String? {
        for key in ["base_file_hash", "base_hash", "target_content_hash"] {
            if let value = actionPlan.payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        for key in ["expected_base_file_hash", "previous_base_file_hash"] {
            if let value = actionPlan.error?[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

public enum ActionPlanRecoveryValidationError: Error, Equatable, LocalizedError, Sendable {
    case targetChanged(previous: String, current: String)
    case observedHashMismatch(targetPath: String, observed: String, current: String)

    public var errorDescription: String? {
        switch self {
        case .targetChanged(let previous, let current):
            return "Cannot regenerate patch because the failed action targeted \(previous), but the current action would target \(current)."
        case .observedHashMismatch(let targetPath, let observed, let current):
            return "Cannot regenerate patch because \(targetPath) changed again while preparing recovery. Observed \(observed), current \(current)."
        }
    }
}

public struct ActionPlanRecoveryTargetValidator: Sendable {
    public init() {}

    public func validate(
        context: ActionPlanRecoveryContext?,
        currentTargetPath: String?,
        currentBaseFileHash: String?
    ) throws {
        guard let context else { return }
        if
            let previousTargetPath = context.targetPath,
            let currentTargetPath,
            previousTargetPath != currentTargetPath
        {
            throw ActionPlanRecoveryValidationError.targetChanged(
                previous: previousTargetPath,
                current: currentTargetPath
            )
        }
        if
            let currentTargetPath,
            let currentBaseFileHash,
            currentBaseFileHash != context.observedFileHash
        {
            throw ActionPlanRecoveryValidationError.observedHashMismatch(
                targetPath: currentTargetPath,
                observed: context.observedFileHash,
                current: currentBaseFileHash
            )
        }
    }
}
