import Foundation

public struct AgentActionPlanStepDraft: Hashable, Sendable {
    public var kind: String
    public var title: String
    public var description: String
    public var requiredPermissions: [AgentActionPermission]
    public var payload: [String: String]
    public var preview: [String: String]?

    public init(
        kind: String,
        title: String,
        description: String = "",
        requiredPermissions: [AgentActionPermission] = [],
        payload: [String: String] = [:],
        preview: [String: String]? = nil
    ) {
        self.kind = kind
        self.title = title
        self.description = description
        self.requiredPermissions = requiredPermissions
        self.payload = payload
        self.preview = preview
    }
}

public struct AgentActionPlanDraft: Hashable, Sendable {
    public var kind: AgentActionKind
    public var title: String
    public var description: String
    public var researchPlanId: String?
    public var articleRevisionId: String?
    public var skillId: String?
    public var skillSlug: String?
    public var jobId: String?
    public var idempotencyKey: String?
    public var requiredPermissions: [AgentActionPermission]
    public var payload: [String: String]
    public var preview: [String: String]?
    public var steps: [AgentActionPlanStepDraft]

    public init(
        kind: AgentActionKind,
        title: String,
        description: String = "",
        researchPlanId: String? = nil,
        articleRevisionId: String? = nil,
        skillId: String? = nil,
        skillSlug: String? = nil,
        jobId: String? = nil,
        idempotencyKey: String? = nil,
        requiredPermissions: [AgentActionPermission] = [],
        payload: [String: String] = [:],
        preview: [String: String]? = nil,
        steps: [AgentActionPlanStepDraft] = []
    ) {
        self.kind = kind
        self.title = title
        self.description = description
        self.researchPlanId = researchPlanId
        self.articleRevisionId = articleRevisionId
        self.skillId = skillId
        self.skillSlug = skillSlug
        self.jobId = jobId
        self.idempotencyKey = idempotencyKey
        self.requiredPermissions = requiredPermissions
        self.payload = payload
        self.preview = preview
        self.steps = steps
    }
}

public struct BilinAPIHealth: Hashable, Sendable {
    public var status: String
    public var app: String
    public var version: String?

    public init(status: String, app: String, version: String? = nil) {
        self.status = status
        self.app = app
        self.version = version
    }
}

public struct BilinResearchAPIClient: Sendable {
    public var baseURL: URL
    public var apiToken: String?
    public var session: URLSession

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8000")!,
        apiToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.session = session
    }

    public static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BilinResearchAPIClient {
        let rawBaseURL = environment["BILIN_API_BASE_URL"] ?? "http://127.0.0.1:8000"
        let baseURL = URL(string: rawBaseURL) ?? URL(string: "http://127.0.0.1:8000")!
        return BilinResearchAPIClient(
            baseURL: baseURL,
            apiToken: environment["BILIN_API_TOKEN"]
        )
    }

    public func health() async throws -> BilinAPIHealth {
        let response: BilinAPIHealthDTO = try await request(
            path: "/health",
            method: "GET"
        )
        return response.domain
    }

    public func listResearchSkills() async throws -> [ResearchSkill] {
        let response: [ResearchSkillDTO] = try await request(
            path: "/research-skills",
            method: "GET"
        )
        return response.map(\.domain)
    }

    public func resolveLibraryId(identifier: String, path: String? = nil) async throws -> String {
        let libraries: [LibraryReferenceDTO] = try await request(
            path: "/libraries",
            method: "GET"
        )
        if libraries.contains(where: { $0.id == identifier }) {
            return identifier
        }
        let localPath = path ?? identifier
        if let library = libraries.first(where: { $0.path == localPath }) {
            return library.id
        }
        throw BilinResearchAPIError.libraryNotRegistered(localPath)
    }

    public func indexLocalResearchSkills(
        projectRoot: String? = nil,
        codexSkillsRoot: String? = nil
    ) async throws -> [ResearchSkill] {
        let response: [ResearchSkillDTO] = try await request(
            path: "/research-skills/index-local",
            method: "POST",
            body: ResearchSkillIndexRequestDTO(
                projectRoot: projectRoot,
                codexSkillsRoot: codexSkillsRoot
            )
        )
        return response.map(\.domain)
    }

    public func enableResearchSkill(
        skillIdentifier: String,
        expectedDigest: String? = nil,
        grantedPermissions: [AgentActionPermission] = []
    ) async throws -> ResearchSkill {
        let response: ResearchSkillDTO = try await request(
            path: "/research-skills/\(Self.pathSegment(skillIdentifier))/enable",
            method: "POST",
            body: ResearchSkillEnableRequestDTO(
                expectedDigest: expectedDigest,
                grantedPermissions: grantedPermissions.map(\.backendValue)
            )
        )
        return response.domain
    }

    public func listResearchPlans(
        libraryId: String,
        articleRevisionId: String? = nil,
        status: ResearchPlanStatus? = nil,
        kind: ResearchPlanKind? = nil
    ) async throws -> [ResearchPlan] {
        var queryItems: [URLQueryItem] = []
        if let articleRevisionId {
            queryItems.append(URLQueryItem(name: "article_revision_id", value: articleRevisionId))
        }
        if let status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let kind {
            queryItems.append(URLQueryItem(name: "kind", value: kind.rawValue))
        }
        return try await request(
            path: "/libraries/\(Self.pathSegment(libraryId))/research-plans",
            method: "GET",
            queryItems: queryItems
        )
    }

    public func generateResearchPlanActionPlan(
        libraryId: String,
        request: ResearchPlanGenerationRequest
    ) async throws -> AgentActionPlan {
        let response: AgentActionPlanDTO = try await self.request(
            path: "/libraries/\(Self.pathSegment(libraryId))/research-plans/generate",
            method: "POST",
            body: request
        )
        return response.domain
    }

    public func listAgentActionPlans(
        libraryId: String,
        articleRevisionId: String? = nil,
        status: AgentActionStatus? = nil,
        kind: AgentActionKind? = nil
    ) async throws -> [AgentActionPlan] {
        var queryItems: [URLQueryItem] = []
        if let articleRevisionId {
            queryItems.append(URLQueryItem(name: "article_revision_id", value: articleRevisionId))
        }
        if let status {
            queryItems.append(URLQueryItem(name: "status", value: status.backendValue))
        }
        if let kind {
            queryItems.append(URLQueryItem(name: "kind", value: kind.backendValue))
        }
        let response: [AgentActionPlanDTO] = try await request(
            path: "/libraries/\(Self.pathSegment(libraryId))/agent-action-plans",
            method: "GET",
            queryItems: queryItems
        )
        return response.map(\.domain)
    }

    public func createAgentActionPlan(
        libraryId: String,
        draft: AgentActionPlanDraft
    ) async throws -> AgentActionPlan {
        let response: AgentActionPlanDTO = try await request(
            path: "/libraries/\(Self.pathSegment(libraryId))/agent-action-plans",
            method: "POST",
            body: AgentActionPlanCreateDTO(draft: draft)
        )
        return response.domain
    }

    public func approveAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        expectedPayloadHash: String? = nil,
        payload: [String: String] = [:]
    ) async throws -> AgentActionPlan {
        try await transitionAgentActionPlan(
            libraryId: libraryId,
            actionPlanId: actionPlanId,
            transition: "approve",
            request: AgentActionPlanTransitionDTO(
                expectedPayloadHash: expectedPayloadHash,
                payload: payload
            )
        )
    }

    public func rejectAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        payload: [String: String] = [:]
    ) async throws -> AgentActionPlan {
        try await transitionAgentActionPlan(
            libraryId: libraryId,
            actionPlanId: actionPlanId,
            transition: "reject",
            request: AgentActionPlanTransitionDTO(payload: payload)
        )
    }

    public func startAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        payload: [String: String] = [:]
    ) async throws -> AgentActionPlan {
        try await transitionAgentActionPlan(
            libraryId: libraryId,
            actionPlanId: actionPlanId,
            transition: "start",
            request: AgentActionPlanTransitionDTO(payload: payload)
        )
    }

    public func succeedAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        result: [String: String] = [:]
    ) async throws -> AgentActionPlan {
        try await transitionAgentActionPlan(
            libraryId: libraryId,
            actionPlanId: actionPlanId,
            transition: "succeed",
            request: AgentActionPlanTransitionDTO(result: result)
        )
    }

    public func succeedAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        jsonResult: ResearchPlanJSONObject
    ) async throws -> AgentActionPlan {
        try await transitionAgentActionPlan(
            libraryId: libraryId,
            actionPlanId: actionPlanId,
            transition: "succeed",
            request: AgentActionPlanTransitionDTO(jsonResult: jsonResult)
        )
    }

    public func failAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        error: [String: String] = [:]
    ) async throws -> AgentActionPlan {
        try await transitionAgentActionPlan(
            libraryId: libraryId,
            actionPlanId: actionPlanId,
            transition: "fail",
            request: AgentActionPlanTransitionDTO(error: error)
        )
    }

    private func transitionAgentActionPlan(
        libraryId: String,
        actionPlanId: String,
        transition: String,
        request: AgentActionPlanTransitionDTO
    ) async throws -> AgentActionPlan {
        let response: AgentActionPlanDTO = try await self.request(
            path: "/libraries/\(Self.pathSegment(libraryId))/agent-action-plans/\(Self.pathSegment(actionPlanId))/\(transition)",
            method: "POST",
            body: request
        )
        return response.domain
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await request(path: path, method: method, queryItems: queryItems, body: EmptyBody?.none)
    }

    private func request<RequestBody: Encodable, Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: RequestBody?
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BilinResearchAPIError.invalidURL(baseURL.absoluteString)
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = ([basePath, requestPath].filter { !$0.isEmpty }).joined(separator: "/")
        if !components.percentEncodedPath.hasPrefix("/") {
            components.percentEncodedPath = "/" + components.percentEncodedPath
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw BilinResearchAPIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "accept")
        if let apiToken {
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BilinResearchAPIError.invalidResponse
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            let detail = try? decoder.decode(APIErrorDTO.self, from: data)
            throw BilinResearchAPIError.httpStatus(
                httpResponse.statusCode,
                detail?.detail ?? String(data: data, encoding: .utf8)
            )
        }
        return try decoder.decode(Response.self, from: data)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.iso8601WithFractional.date(from: value)
                ?? Self.iso8601.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public enum BilinResearchAPIError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case invalidResponse
    case httpStatus(Int, String?)
    case libraryNotRegistered(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid Bilin API URL: \(path)"
        case .invalidResponse:
            return "Bilin API returned a non-HTTP response."
        case .httpStatus(let status, let detail):
            return detail.map { "Bilin API \(status): \($0)" } ?? "Bilin API \(status)"
        case .libraryNotRegistered(let path):
            return "Bilin API has no registered library for \(path)."
        }
    }
}

private struct EmptyBody: Encodable {}

private struct APIErrorDTO: Decodable {
    var detail: String?
}

private struct BilinAPIHealthDTO: Decodable {
    var status: String
    var app: String
    var version: String?

    var domain: BilinAPIHealth {
        BilinAPIHealth(status: status, app: app, version: version)
    }
}

private struct LibraryReferenceDTO: Decodable {
    var id: String
    var path: String
}

private struct ResearchSkillIndexRequestDTO: Encodable {
    var projectRoot: String?
    var codexSkillsRoot: String?
}

private struct ResearchSkillEnableRequestDTO: Encodable {
    var expectedDigest: String?
    var grantedPermissions: [String]
}

private struct ResearchSkillDTO: Decodable {
    var id: String
    var slug: String
    var title: String
    var description: String
    var sourcePath: String
    var cachePath: String?
    var digest: String
    var version: String?
    var installStatus: String
    var status: String
    var enabled: Bool
    var declaredPermissions: [String]
    var grantedPermissions: [String]
    var supportedTasks: [String]
    var createdAt: Date
    var updatedAt: Date

    var domain: ResearchSkill {
        ResearchSkill(
            id: id,
            slug: slug,
            title: title,
            description: description,
            version: version,
            digest: digest,
            source: ResearchSkillSource(kind: sourceKind, identifier: sourcePath),
            sourcePath: sourcePath,
            cachePath: cachePath,
            status: skillStatus,
            permissions: (grantedPermissions.isEmpty ? declaredPermissions : grantedPermissions)
                .compactMap(AgentActionPermission.init(backendValue:)),
            supportedTasks: supportedTasks.compactMap(ResearchSkillTask.init(backendValue:)),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private var sourceKind: ResearchSkillSourceKind {
        if sourcePath.contains("/.agents/skills/") {
            return .project
        }
        if sourcePath.contains("/.codex/skills/") {
            return .user
        }
        return cachePath == nil ? .bundled : .cache
    }

    private var skillStatus: ResearchSkillStatus {
        if enabled {
            return .enabled
        }
        switch status {
        case "metadata_only":
            return .metadataOnly
        case "disabled":
            return .disabled
        case "enabled":
            return .enabled
        default:
            switch installStatus {
            case "cached":
                return .cached
            case "installed":
                return .installed
            default:
                return .discovered
            }
        }
    }
}

private struct AgentActionPlanCreateDTO: Encodable {
    var kind: String
    var title: String
    var description: String
    var researchPlanId: String?
    var articleRevisionId: String?
    var skillId: String?
    var skillSlug: String?
    var jobId: String?
    var idempotencyKey: String?
    var requiredPermissions: [String]
    var payload: [String: String]
    var preview: [String: String]?
    var steps: [AgentActionPlanStepCreateDTO]

    init(draft: AgentActionPlanDraft) {
        kind = draft.kind.backendValue
        title = draft.title
        description = draft.description
        researchPlanId = draft.researchPlanId
        articleRevisionId = draft.articleRevisionId
        skillId = draft.skillId
        skillSlug = draft.skillSlug
        jobId = draft.jobId
        idempotencyKey = draft.idempotencyKey
        requiredPermissions = draft.requiredPermissions.map(\.backendValue)
        payload = draft.payload
        preview = draft.preview
        steps = draft.steps.map(AgentActionPlanStepCreateDTO.init(draft:))
    }
}

private struct AgentActionPlanStepCreateDTO: Encodable {
    var kind: String
    var title: String
    var description: String
    var requiredPermissions: [String]
    var payload: [String: String]
    var preview: [String: String]?

    init(draft: AgentActionPlanStepDraft) {
        kind = draft.kind
        title = draft.title
        description = draft.description
        requiredPermissions = draft.requiredPermissions.map(\.backendValue)
        payload = draft.payload
        preview = draft.preview
    }
}

private struct AgentActionPlanTransitionDTO: Encodable {
    var expectedPayloadHash: String?
    var payload: [String: String]
    var result: ResearchPlanJSONObject?
    var error: [String: String]?

    init(
        expectedPayloadHash: String? = nil,
        payload: [String: String] = [:],
        result: [String: String]? = nil,
        error: [String: String]? = nil
    ) {
        self.expectedPayloadHash = expectedPayloadHash
        self.payload = payload
        self.result = result?.mapValues { .string($0) }
        self.error = error
    }

    init(
        expectedPayloadHash: String? = nil,
        payload: [String: String] = [:],
        jsonResult: ResearchPlanJSONObject,
        error: [String: String]? = nil
    ) {
        self.expectedPayloadHash = expectedPayloadHash
        self.payload = payload
        self.result = jsonResult
        self.error = error
    }
}

private struct AgentActionPlanDTO: Decodable {
    var id: String
    var kind: String
    var status: String
    var title: String
    var description: String
    var payloadHash: String
    var idempotencyKey: String?
    var requiredPermissions: [String]
    var payload: [String: JSONValue]
    var preview: [String: JSONValue]?
    var result: [String: JSONValue]?
    var steps: [AgentActionPlanStepDTO]
    var createdAt: Date
    var updatedAt: Date
    var approvedAt: Date?
    var finishedAt: Date?
    var error: [String: JSONValue]?

    var domain: AgentActionPlan {
        AgentActionPlan(
            id: id,
            kind: AgentActionKind(backendValue: kind),
            status: AgentActionStatus(backendValue: status),
            title: title,
            summary: description.isEmpty ? title : description,
            requestedPermissions: requiredPermissions.compactMap(AgentActionPermission.init(backendValue:)),
            steps: steps.map(\.domain),
            payloadHash: payloadHash,
            payload: payload.stringDictionary,
            preview: preview?.stringDictionary,
            result: result?.stringDictionary,
            idempotencyKey: idempotencyKey,
            createdAt: createdAt,
            updatedAt: updatedAt,
            approvedAt: approvedAt,
            completedAt: finishedAt,
            error: error?.stringDictionary,
            errorMessage: error?["message"]?.stringValue ?? error?["code"]?.stringValue
        )
    }
}

private struct AgentActionPlanStepDTO: Decodable {
    var id: String
    var kind: String
    var title: String
    var requiredPermissions: [String]
    var payload: [String: JSONValue]

    var domain: AgentActionStep {
        AgentActionStep(
            id: id,
            kind: AgentActionStepKind(backendValue: kind),
            title: title,
            targetPath: payload["target_path"]?.stringValue
                ?? payload["target"]?.stringValue
                ?? payload["target_note"]?.stringValue,
            permission: requiredPermissions.compactMap(AgentActionPermission.init(backendValue:)).first
        )
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    var stringDictionary: [String: String] {
        reduce(into: [:]) { result, element in
            if let stringValue = element.value.stringValue {
                result[element.key] = stringValue
            }
        }
    }
}

private enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .object, .array:
            return serializedJSONString
        case .null:
            return nil
        }
    }

    private var serializedJSONString: String? {
        let value = jsonCompatibleValue
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private var jsonCompatibleValue: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.jsonCompatibleValue }
        case .array(let value):
            return value.map { $0.jsonCompatibleValue }
        case .null:
            return NSNull()
        }
    }
}

private extension AgentActionKind {
    init(backendValue: String) {
        switch backendValue {
        case "write_obsidian":
            self = .writeObsidian
        case "edit_manuscript", "writing_patch":
            self = .editManuscript
        case "download_paper":
            self = .downloadPaper
        case "import_library":
            self = .importLibrary
        case "install_skill":
            self = .installSkill
        case "enable_skill":
            self = .enableSkill
        case "run_external_tool":
            self = .runExternalTool
        case "provider_call":
            self = .providerCall
        case "write_library_bundle":
            self = .writeLibraryBundle
        case "export_article":
            self = .exportArticle
        case "note_patch":
            self = .notePatch
        case "generate_research_outline":
            self = .generateResearchOutline
        default:
            self = .custom
        }
    }

    var backendValue: String {
        switch self {
        case .writeObsidian:
            return "write_obsidian"
        case .editManuscript:
            return "edit_manuscript"
        case .downloadPaper:
            return "download_paper"
        case .importLibrary:
            return "import_library"
        case .installSkill:
            return "install_skill"
        case .enableSkill:
            return "enable_skill"
        case .runExternalTool:
            return "run_external_tool"
        case .providerCall:
            return "provider_call"
        case .writeLibraryBundle:
            return "write_library_bundle"
        case .exportArticle:
            return "export_article"
        case .notePatch:
            return "note_patch"
        case .writingPatch:
            return "writing_patch"
        case .generateResearchOutline:
            return "generate_research_outline"
        case .custom:
            return "custom"
        }
    }
}

private extension AgentActionStatus {
    init(backendValue: String) {
        switch backendValue {
        case "pending":
            self = .pendingApproval
        case "approved":
            self = .approved
        case "queued":
            self = .queued
        case "running":
            self = .running
        case "succeeded":
            self = .succeeded
        case "failed":
            self = .failed
        case "rejected":
            self = .rejected
        case "cancelled":
            self = .cancelled
        default:
            self = .draft
        }
    }

    var backendValue: String {
        switch self {
        case .draft, .pendingApproval:
            return "pending"
        case .approved:
            return "approved"
        case .queued:
            return "queued"
        case .rejected:
            return "rejected"
        case .cancelled:
            return "cancelled"
        case .running:
            return "running"
        case .succeeded:
            return "succeeded"
        case .failed:
            return "failed"
        }
    }
}

private extension AgentActionPermission {
    init?(backendValue: String) {
        switch backendValue {
        case "network":
            self = .network
        case "provider_call":
            self = .providerCall
        case "download_paper":
            self = .downloadPaper
        case "import_library":
            self = .importLibrary
        case "write_library_bundle":
            self = .writeLibraryBundle
        case "write_obsidian":
            self = .writeObsidian
        case "edit_manuscript":
            self = .editManuscript
        case "run_external_tool":
            self = .runExternalTool
        case "install_skill":
            self = .installSkill
        case "enable_skill":
            self = .enableSkill
        default:
            return nil
        }
    }

    var backendValue: String {
        switch self {
        case .network:
            return "network"
        case .providerCall:
            return "provider_call"
        case .downloadPaper:
            return "download_paper"
        case .importLibrary:
            return "import_library"
        case .writeLibraryBundle:
            return "write_library_bundle"
        case .writeObsidian:
            return "write_obsidian"
        case .editManuscript:
            return "edit_manuscript"
        case .runExternalTool:
            return "run_external_tool"
        case .installSkill:
            return "install_skill"
        case .enableSkill:
            return "enable_skill"
        }
    }
}

private extension AgentActionStepKind {
    init(backendValue: String) {
        switch backendValue {
        case "preview_patch", "render_patch":
            self = .previewPatch
        case "write_file", "apply_patch":
            self = .writeFile
        case "download":
            self = .download
        case "import", "import_item":
            self = .importItem
        case "install_skill":
            self = .installSkill
        case "enable_skill":
            self = .enableSkill
        case "run_tool", "run_external_tool":
            self = .runTool
        case "call_provider", "provider_call":
            self = .callProvider
        default:
            self = .notify
        }
    }
}

private extension ResearchSkillTask {
    init?(backendValue: String) {
        switch backendValue {
        case "arxiv_search", "arxiv":
            self = .arxivSearch
        case "literature_review":
            self = .literatureReview
        case "related_work":
            self = .relatedWork
        case "paper_reading":
            self = .paperReading
        case "experiment_planning":
            self = .experimentPlanning
        case "writing":
            self = .writing
        case "citation_discovery", "citation":
            self = .citationDiscovery
        default:
            return nil
        }
    }
}
