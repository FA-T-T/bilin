import Foundation

public protocol ResearchActionPlanRemoteClient: Sendable {
    func resolveLibraryId(identifier: String, path: String?) async throws -> String

    func approveAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        expectedPayloadHash: String?,
        payload: [String: String]
    ) async throws -> AgentActionPlan

    func rejectAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        payload: [String: String]
    ) async throws -> AgentActionPlan

    func startAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        payload: [String: String]
    ) async throws -> AgentActionPlan

    func succeedAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        result: [String: String]
    ) async throws -> AgentActionPlan

    func failAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        error: [String: String]
    ) async throws -> AgentActionPlan
}

extension BilinResearchAPIClient: ResearchActionPlanRemoteClient {}

public protocol LocalActionPlanPatchApplying: Sendable {
    func apply(
        actionPlan: AgentActionPlan,
        configuration: WorkspaceConfiguration
    ) throws -> LocalFilePatchResult
}

extension LocalFilePatchExecutor: LocalActionPlanPatchApplying {}

public enum ResearchActionPlanCoordinatorError: Error, LocalizedError, Sendable {
    case approvalRequired

    public var errorDescription: String? {
        switch self {
        case .approvalRequired:
            return "Action plan must be approved before it can write files."
        }
    }
}

public enum ResearchActionPlanApplyOutcome: Sendable {
    case succeeded(
        libraryId: String,
        running: AgentActionPlan,
        succeeded: AgentActionPlan,
        localResult: LocalFilePatchResult
    )
    case failed(
        libraryId: String?,
        running: AgentActionPlan?,
        failed: AgentActionPlan?,
        errorMessage: String
    )

    public var actionPlanUpdates: [AgentActionPlan] {
        switch self {
        case .succeeded(_, let running, let succeeded, _):
            return [running, succeeded]
        case .failed(_, let running, let failed, _):
            return [running, failed].compactMap { $0 }
        }
    }

    public var errorMessage: String? {
        switch self {
        case .succeeded:
            return nil
        case .failed(_, _, _, let errorMessage):
            return errorMessage
        }
    }
}

public struct ResearchActionPlanCoordinator<
    Client: ResearchActionPlanRemoteClient,
    PatchApplier: LocalActionPlanPatchApplying
>: Sendable {
    private var client: Client
    private var patchApplier: PatchApplier

    public init(client: Client, patchApplier: PatchApplier) {
        self.client = client
        self.patchApplier = patchApplier
    }

    public func approve(
        libraryIdentifier: String,
        libraryPath: String?,
        actionPlan: AgentActionPlan
    ) async throws -> AgentActionPlan {
        let libraryId = try await client.resolveLibraryId(
            identifier: libraryIdentifier,
            path: libraryPath
        )
        return try await client.approveAgentActionPlan(
            libraryId: libraryId,
            actionPlanId: actionPlan.id,
            expectedPayloadHash: actionPlan.payloadHash,
            payload: ["approved_by": "macos"]
        )
    }

    public func reject(
        libraryIdentifier: String,
        libraryPath: String?,
        actionPlan: AgentActionPlan
    ) async throws -> AgentActionPlan {
        let libraryId = try await client.resolveLibraryId(
            identifier: libraryIdentifier,
            path: libraryPath
        )
        return try await client.rejectAgentActionPlan(
            libraryId: libraryId,
            actionPlanId: actionPlan.id,
            payload: ["rejected_by": "macos"]
        )
    }

    public func apply(
        libraryIdentifier: String,
        libraryPath: String?,
        actionPlan: AgentActionPlan,
        configuration: WorkspaceConfiguration
    ) async throws -> ResearchActionPlanApplyOutcome {
        guard actionPlan.status == .approved else {
            throw ResearchActionPlanCoordinatorError.approvalRequired
        }

        var backendLibraryId: String?
        var runningActionPlan: AgentActionPlan?
        do {
            let resolvedLibraryId = try await client.resolveLibraryId(
                identifier: libraryIdentifier,
                path: libraryPath
            )
            backendLibraryId = resolvedLibraryId
            let running = try await client.startAgentActionPlan(
                libraryId: resolvedLibraryId,
                actionPlanId: actionPlan.id,
                payload: ["executor": "macos"]
            )
            runningActionPlan = running

            let result = try patchApplier.apply(
                actionPlan: running,
                configuration: configuration
            )
            let succeeded = try await client.succeedAgentActionPlan(
                libraryId: resolvedLibraryId,
                actionPlanId: running.id,
                result: result.actionResultPayload
            )
            return .succeeded(
                libraryId: resolvedLibraryId,
                running: running,
                succeeded: succeeded,
                localResult: result
            )
        } catch {
            var failedActionPlan: AgentActionPlan?
            if let backendLibraryId, let runningActionPlan {
                failedActionPlan = try? await client.failAgentActionPlan(
                    libraryId: backendLibraryId,
                    actionPlanId: runningActionPlan.id,
                    error: Self.failurePayload(for: error, actionPlan: runningActionPlan)
                )
            }
            return .failed(
                libraryId: backendLibraryId,
                running: runningActionPlan,
                failed: failedActionPlan,
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func failurePayload(for error: Error, actionPlan: AgentActionPlan) -> [String: String] {
        var payload = [
            "code": "local_patch_failed",
            "message": error.localizedDescription
        ]
        if let targetPath = actionPlan.payload["target_path"]
            ?? actionPlan.steps.compactMap(\.targetPath).first
        {
            payload["target_path"] = targetPath
        }
        if let targetNote = actionPlan.payload["target_note"] {
            payload["target_note"] = targetNote
        }
        if case LocalFilePatchExecutionError.fileChangedSincePreview(let expected, let observed) = error {
            payload["code"] = "file_changed_since_preview"
            payload["expected_base_file_hash"] = expected
            payload["observed_file_hash"] = observed
        }
        return payload
    }
}

public typealias DefaultResearchActionPlanCoordinator = ResearchActionPlanCoordinator<
    BilinResearchAPIClient,
    LocalFilePatchExecutor
>

public extension DefaultResearchActionPlanCoordinator {
    init(client: BilinResearchAPIClient) {
        self.init(client: client, patchApplier: LocalFilePatchExecutor())
    }
}
