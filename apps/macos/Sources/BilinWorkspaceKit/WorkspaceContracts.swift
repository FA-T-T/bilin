import Foundation

public struct ReadingOutline: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var articleRevisionId: String
    public var title: String
    public var status: ReadingOutlineStatus
    public var items: [ReadingOutlineItem]
    public var sourceProvenance: [SourceBlockProvenance]
    public var summary: String
    public var sections: [ResearchPlanJSONObject]
    public var questions: [String]
    public var sourceRefs: [String]
    public var paperMasteryOutlines: [ResearchPaperMasteryOutline]
    public var metadata: ResearchPlanJSONObject
    public var generatedAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        articleRevisionId: String,
        title: String,
        status: ReadingOutlineStatus = .draft,
        items: [ReadingOutlineItem] = [],
        sourceProvenance: [SourceBlockProvenance] = [],
        summary: String = "",
        sections: [ResearchPlanJSONObject] = [],
        questions: [String] = [],
        sourceRefs: [String] = [],
        paperMasteryOutlines: [ResearchPaperMasteryOutline] = [],
        metadata: ResearchPlanJSONObject = [:],
        generatedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.articleRevisionId = articleRevisionId
        self.title = title
        self.status = status
        self.items = items
        self.sourceProvenance = sourceProvenance
        self.summary = summary
        self.sections = sections
        self.questions = questions
        self.sourceRefs = sourceRefs
        self.paperMasteryOutlines = paperMasteryOutlines
        self.metadata = metadata
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case articleRevisionId
        case title
        case status
        case items
        case sourceProvenance
        case summary
        case sections
        case questions
        case sourceRefs
        case paperMasteryOutlines
        case metadata
        case generatedAt
        case updatedAt
    }

    private static let compatibilityDate = Date(timeIntervalSince1970: 0)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        articleRevisionId = try container.decodeIfPresent(String.self, forKey: .articleRevisionId) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        status = try container.decodeIfPresent(ReadingOutlineStatus.self, forKey: .status) ?? .draft
        items = try container.decodeIfPresent([ReadingOutlineItem].self, forKey: .items) ?? []
        sourceProvenance = try container.decodeIfPresent([SourceBlockProvenance].self, forKey: .sourceProvenance) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sections = try container.decodeIfPresent([ResearchPlanJSONObject].self, forKey: .sections) ?? []
        questions = try container.decodeIfPresent([String].self, forKey: .questions) ?? []
        sourceRefs = try container.decodeIfPresent([String].self, forKey: .sourceRefs) ?? []
        paperMasteryOutlines = try container.decodeIfPresent([ResearchPaperMasteryOutline].self, forKey: .paperMasteryOutlines) ?? []
        metadata = try container.decodeIfPresent(ResearchPlanJSONObject.self, forKey: .metadata) ?? [:]
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Self.compatibilityDate
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Self.compatibilityDate
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)

        if !summary.isEmpty {
            try container.encode(summary, forKey: .summary)
        }
        if !sections.isEmpty {
            try container.encode(sections, forKey: .sections)
        }
        if !questions.isEmpty {
            try container.encode(questions, forKey: .questions)
        }
        if !sourceRefs.isEmpty {
            try container.encode(sourceRefs, forKey: .sourceRefs)
        }
        if !paperMasteryOutlines.isEmpty {
            try container.encode(paperMasteryOutlines, forKey: .paperMasteryOutlines)
        }
        if !metadata.isEmpty {
            try container.encode(metadata, forKey: .metadata)
        }

        let hasLegacyFields = !id.isEmpty
            || !articleRevisionId.isEmpty
            || status != .draft
            || !items.isEmpty
            || !sourceProvenance.isEmpty
            || generatedAt != Self.compatibilityDate
            || updatedAt != Self.compatibilityDate
        if hasLegacyFields {
            try container.encode(id, forKey: .id)
            try container.encode(articleRevisionId, forKey: .articleRevisionId)
            try container.encode(status, forKey: .status)
            try container.encode(items, forKey: .items)
            try container.encode(sourceProvenance, forKey: .sourceProvenance)
            try container.encode(generatedAt, forKey: .generatedAt)
            try container.encode(updatedAt, forKey: .updatedAt)
        }
    }
}

public enum ResearchPlanJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ResearchPlanJSONValue])
    case array([ResearchPlanJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: ResearchPlanJSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([ResearchPlanJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public typealias ResearchPlanJSONObject = [String: ResearchPlanJSONValue]

public struct ResearchPaperMasteryOutline: Codable, Hashable, Sendable {
    public var paperId: String?
    public var paperTitle: String
    public var claim: [String]
    public var method: [String]
    public var equation: [String]
    public var evidence: [String]
    public var limitation: [String]
    public var followUp: [String]

    public init(
        paperId: String? = nil,
        paperTitle: String = "",
        claim: [String] = [],
        method: [String] = [],
        equation: [String] = [],
        evidence: [String] = [],
        limitation: [String] = [],
        followUp: [String] = []
    ) {
        self.paperId = paperId
        self.paperTitle = paperTitle
        self.claim = claim
        self.method = method
        self.equation = equation
        self.evidence = evidence
        self.limitation = limitation
        self.followUp = followUp
    }

    private enum CodingKeys: String, CodingKey {
        case paperId
        case paperTitle
        case claim
        case method
        case equation
        case evidence
        case limitation
        case followUp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paperId = try container.decodeIfPresent(String.self, forKey: .paperId)
        paperTitle = try container.decodeIfPresent(String.self, forKey: .paperTitle) ?? ""
        claim = try container.decodeIfPresent([String].self, forKey: .claim) ?? []
        method = try container.decodeIfPresent([String].self, forKey: .method) ?? []
        equation = try container.decodeIfPresent([String].self, forKey: .equation) ?? []
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        limitation = try container.decodeIfPresent([String].self, forKey: .limitation) ?? []
        followUp = try container.decodeIfPresent([String].self, forKey: .followUp) ?? []
    }
}

public struct ResearchPlanGenerationRequest: Codable, Hashable, Sendable {
    public var title: String
    public var kind: ResearchPlanKind
    public var topic: String?
    public var articleRevisionId: String?
    public var skillSlug: String?
    public var candidatePapers: [ResearchPlanJSONObject]
    public var idempotencyKey: String?
    public var payload: ResearchPlanJSONObject

    public init(
        title: String,
        kind: ResearchPlanKind = .paperReading,
        topic: String? = nil,
        articleRevisionId: String? = nil,
        skillSlug: String? = nil,
        candidatePapers: [ResearchPlanJSONObject] = [],
        idempotencyKey: String? = nil,
        payload: ResearchPlanJSONObject = [:]
    ) {
        self.title = title
        self.kind = kind
        self.topic = topic
        self.articleRevisionId = articleRevisionId
        self.skillSlug = skillSlug
        self.candidatePapers = candidatePapers
        self.idempotencyKey = idempotencyKey
        self.payload = payload
    }
}

public struct ResearchPlan: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: ResearchPlanKind
    public var status: ResearchPlanStatus
    public var title: String
    public var topic: String?
    public var articleRevisionId: String?
    public var skillId: String?
    public var skillSlug: String?
    public var jobId: String?
    public var idempotencyKey: String?
    public var payloadHash: String
    public var candidatePapers: [ResearchPlanJSONObject]
    public var readingOutline: ReadingOutline?
    public var payload: ResearchPlanJSONObject
    public var preview: ResearchPlanJSONObject?
    public var result: ResearchPlanJSONObject?
    public var error: ResearchPlanJSONObject?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        kind: ResearchPlanKind = .custom,
        status: ResearchPlanStatus = .draft,
        title: String,
        topic: String? = nil,
        articleRevisionId: String? = nil,
        skillId: String? = nil,
        skillSlug: String? = nil,
        jobId: String? = nil,
        idempotencyKey: String? = nil,
        payloadHash: String,
        candidatePapers: [ResearchPlanJSONObject] = [],
        readingOutline: ReadingOutline? = nil,
        payload: ResearchPlanJSONObject = [:],
        preview: ResearchPlanJSONObject? = nil,
        result: ResearchPlanJSONObject? = nil,
        error: ResearchPlanJSONObject? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.topic = topic
        self.articleRevisionId = articleRevisionId
        self.skillId = skillId
        self.skillSlug = skillSlug
        self.jobId = jobId
        self.idempotencyKey = idempotencyKey
        self.payloadHash = payloadHash
        self.candidatePapers = candidatePapers
        self.readingOutline = readingOutline
        self.payload = payload
        self.preview = preview
        self.result = result
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct NoteBridge: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var articleRevisionId: String
    public var status: NoteBridgeStatus
    public var targetVault: NoteBridgeVault
    public var targetNotePath: String
    public var headingPath: [String]
    public var blockAnchor: String
    public var calloutType: NoteBridgeCalloutType
    public var tags: [String]
    public var sourcePayload: NoteBridgePayload
    public var translationPayload: NoteBridgePayload?
    public var pendingPatch: PendingFilePatch?
    public var provenance: SourceBlockProvenance
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        articleRevisionId: String,
        status: NoteBridgeStatus = .draft,
        targetVault: NoteBridgeVault,
        targetNotePath: String,
        headingPath: [String] = [],
        blockAnchor: String,
        calloutType: NoteBridgeCalloutType = .note,
        tags: [String] = [],
        sourcePayload: NoteBridgePayload,
        translationPayload: NoteBridgePayload? = nil,
        pendingPatch: PendingFilePatch? = nil,
        provenance: SourceBlockProvenance,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.articleRevisionId = articleRevisionId
        self.status = status
        self.targetVault = targetVault
        self.targetNotePath = targetNotePath
        self.headingPath = headingPath
        self.blockAnchor = blockAnchor
        self.calloutType = calloutType
        self.tags = tags
        self.sourcePayload = sourcePayload
        self.translationPayload = translationPayload
        self.pendingPatch = pendingPatch
        self.provenance = provenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WritingProject: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var rootPath: String
    public var kind: WritingProjectKind
    public var status: WritingProjectStatus
    public var mainFilePath: String?
    public var bibliographyFilePaths: [String]
    public var detectedFilePaths: [String]
    public var acceptedPatchIds: [String]
    public var pendingPatches: [PendingFilePatch]
    public var sourceProvenance: [SourceBlockProvenance]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        rootPath: String,
        kind: WritingProjectKind,
        status: WritingProjectStatus = .linked,
        mainFilePath: String? = nil,
        bibliographyFilePaths: [String] = [],
        detectedFilePaths: [String] = [],
        acceptedPatchIds: [String] = [],
        pendingPatches: [PendingFilePatch] = [],
        sourceProvenance: [SourceBlockProvenance] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.kind = kind
        self.status = status
        self.mainFilePath = mainFilePath
        self.bibliographyFilePaths = bibliographyFilePaths
        self.detectedFilePaths = detectedFilePaths
        self.acceptedPatchIds = acceptedPatchIds
        self.pendingPatches = pendingPatches
        self.sourceProvenance = sourceProvenance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AgentActionPlan: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: AgentActionKind
    public var status: AgentActionStatus
    public var title: String
    public var summary: String
    public var requestedPermissions: [AgentActionPermission]
    public var steps: [AgentActionStep]
    public var payloadHash: String
    public var payload: [String: String]
    public var preview: [String: String]?
    public var result: [String: String]?
    public var idempotencyKey: String?
    public var relatedPatchIds: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var approvedAt: Date?
    public var completedAt: Date?
    public var error: [String: String]?
    public var errorMessage: String?

    public var requiresConfirmation: Bool {
        !requestedPermissions.isEmpty
    }

    public init(
        id: String,
        kind: AgentActionKind,
        status: AgentActionStatus = .draft,
        title: String,
        summary: String,
        requestedPermissions: [AgentActionPermission] = [],
        steps: [AgentActionStep] = [],
        payloadHash: String,
        payload: [String: String] = [:],
        preview: [String: String]? = nil,
        result: [String: String]? = nil,
        idempotencyKey: String? = nil,
        relatedPatchIds: [String] = [],
        createdAt: Date,
        updatedAt: Date,
        approvedAt: Date? = nil,
        completedAt: Date? = nil,
        error: [String: String]? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.summary = summary
        self.requestedPermissions = requestedPermissions
        self.steps = steps
        self.payloadHash = payloadHash
        self.payload = payload
        self.preview = preview
        self.result = result
        self.idempotencyKey = idempotencyKey
        self.relatedPatchIds = relatedPatchIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.approvedAt = approvedAt
        self.completedAt = completedAt
        self.error = error
        self.errorMessage = errorMessage
    }
}

public struct ResearchSkill: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var slug: String
    public var title: String
    public var description: String
    public var version: String?
    public var digest: String
    public var source: ResearchSkillSource
    public var sourcePath: String?
    public var cachePath: String?
    public var status: ResearchSkillStatus
    public var permissions: [AgentActionPermission]
    public var inputShape: String?
    public var outputShape: String?
    public var supportedTasks: [ResearchSkillTask]
    public var createdAt: Date
    public var updatedAt: Date

    public var isEnabled: Bool {
        status == .enabled
    }

    public init(
        id: String,
        slug: String,
        title: String,
        description: String,
        version: String? = nil,
        digest: String,
        source: ResearchSkillSource,
        sourcePath: String? = nil,
        cachePath: String? = nil,
        status: ResearchSkillStatus = .metadataOnly,
        permissions: [AgentActionPermission] = [],
        inputShape: String? = nil,
        outputShape: String? = nil,
        supportedTasks: [ResearchSkillTask] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.description = description
        self.version = version
        self.digest = digest
        self.source = source
        self.sourcePath = sourcePath
        self.cachePath = cachePath
        self.status = status
        self.permissions = permissions
        self.inputShape = inputShape
        self.outputShape = outputShape
        self.supportedTasks = supportedTasks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SourceBlockProvenance: Codable, Hashable, Sendable {
    public var libraryId: String?
    public var articleId: String?
    public var articleRevisionId: String
    public var blockUid: String
    public var structuralPath: String?
    public var contentHash: String
    public var contextHash: String?
    public var sourceLanguage: String?
    public var translationId: String?
    public var translationLanguage: String?
    public var translationHash: String?
    public var selectedTextHash: String?
    public var capturedAt: Date

    public var stableBlockAnchor: String {
        "\(articleRevisionId)#\(blockUid)#\(contentHash)"
    }

    public init(
        libraryId: String? = nil,
        articleId: String? = nil,
        articleRevisionId: String,
        blockUid: String,
        structuralPath: String? = nil,
        contentHash: String,
        contextHash: String? = nil,
        sourceLanguage: String? = nil,
        translationId: String? = nil,
        translationLanguage: String? = nil,
        translationHash: String? = nil,
        selectedTextHash: String? = nil,
        capturedAt: Date
    ) {
        self.libraryId = libraryId
        self.articleId = articleId
        self.articleRevisionId = articleRevisionId
        self.blockUid = blockUid
        self.structuralPath = structuralPath
        self.contentHash = contentHash
        self.contextHash = contextHash
        self.sourceLanguage = sourceLanguage
        self.translationId = translationId
        self.translationLanguage = translationLanguage
        self.translationHash = translationHash
        self.selectedTextHash = selectedTextHash
        self.capturedAt = capturedAt
    }
}

public struct PendingFilePatch: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: PendingFilePatchKind
    public var format: PendingFilePatchFormat
    public var status: PendingFilePatchStatus
    public var targetPath: String
    public var targetAnchor: String?
    public var targetSectionPath: [String]
    public var patchText: String
    public var previewMarkdown: String?
    public var baseFileHash: String?
    public var appliedFileHash: String?
    public var conflict: FilePatchConflict?
    public var provenance: [SourceBlockProvenance]
    public var actionPlanId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        kind: PendingFilePatchKind,
        format: PendingFilePatchFormat,
        status: PendingFilePatchStatus = .draft,
        targetPath: String,
        targetAnchor: String? = nil,
        targetSectionPath: [String] = [],
        patchText: String,
        previewMarkdown: String? = nil,
        baseFileHash: String? = nil,
        appliedFileHash: String? = nil,
        conflict: FilePatchConflict? = nil,
        provenance: [SourceBlockProvenance] = [],
        actionPlanId: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.format = format
        self.status = status
        self.targetPath = targetPath
        self.targetAnchor = targetAnchor
        self.targetSectionPath = targetSectionPath
        self.patchText = patchText
        self.previewMarkdown = previewMarkdown
        self.baseFileHash = baseFileHash
        self.appliedFileHash = appliedFileHash
        self.conflict = conflict
        self.provenance = provenance
        self.actionPlanId = actionPlanId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ReadingOutlineItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: ReadingOutlineItemKind
    public var title: String
    public var summaryMarkdown: String
    public var importance: ReadingOutlineImportance
    public var sourceProvenance: [SourceBlockProvenance]

    public init(
        id: String,
        kind: ReadingOutlineItemKind,
        title: String,
        summaryMarkdown: String,
        importance: ReadingOutlineImportance = .medium,
        sourceProvenance: [SourceBlockProvenance] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summaryMarkdown = summaryMarkdown
        self.importance = importance
        self.sourceProvenance = sourceProvenance
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case summaryMarkdown
        case importance
        case sourceProvenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try container.decodeIfPresent(ReadingOutlineItemKind.self, forKey: .kind) ?? .claim
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        summaryMarkdown = try container.decodeIfPresent(String.self, forKey: .summaryMarkdown) ?? ""
        importance = try container.decodeIfPresent(ReadingOutlineImportance.self, forKey: .importance) ?? .medium
        sourceProvenance = try container.decodeIfPresent([SourceBlockProvenance].self, forKey: .sourceProvenance) ?? []
    }
}

public struct NoteBridgeVault: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var rootPath: String
    public var status: ExternalFileTargetStatus

    public init(
        id: String,
        name: String,
        rootPath: String,
        status: ExternalFileTargetStatus = .available
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.status = status
    }
}

public struct NoteBridgePayload: Codable, Hashable, Sendable {
    public var blockUid: String
    public var language: String
    public var markdown: String
    public var contentHash: String

    public init(
        blockUid: String,
        language: String,
        markdown: String,
        contentHash: String
    ) {
        self.blockUid = blockUid
        self.language = language
        self.markdown = markdown
        self.contentHash = contentHash
    }
}

public struct AgentActionStep: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: AgentActionStepKind
    public var title: String
    public var targetPath: String?
    public var permission: AgentActionPermission?

    public init(
        id: String,
        kind: AgentActionStepKind,
        title: String,
        targetPath: String? = nil,
        permission: AgentActionPermission? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.targetPath = targetPath
        self.permission = permission
    }
}

public struct ResearchSkillSource: Codable, Hashable, Sendable {
    public var kind: ResearchSkillSourceKind
    public var identifier: String

    public init(kind: ResearchSkillSourceKind, identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }
}

public struct FilePatchConflict: Codable, Hashable, Sendable {
    public var reason: FilePatchConflictReason
    public var expectedHash: String?
    public var observedHash: String?
    public var message: String

    public init(
        reason: FilePatchConflictReason,
        expectedHash: String? = nil,
        observedHash: String? = nil,
        message: String
    ) {
        self.reason = reason
        self.expectedHash = expectedHash
        self.observedHash = observedHash
        self.message = message
    }
}

public enum ReadingOutlineStatus: String, Codable, Hashable, Sendable {
    case draft
    case ready
    case stale
}

public enum ReadingOutlineItemKind: String, Codable, Hashable, Sendable {
    case definition
    case assumption
    case method
    case equation
    case evidence
    case limitation
    case followUpQuestion
    case claim
}

public enum ReadingOutlineImportance: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high
}

public enum NoteBridgeStatus: String, Codable, Hashable, Sendable {
    case draft
    case previewReady
    case pendingApproval
    case accepted
    case rejected
    case conflicted
}

public enum NoteBridgeCalloutType: String, Codable, Hashable, Sendable {
    case note
    case important
    case info
    case success
    case question
    case abstract
}

public enum WritingProjectKind: String, Codable, Hashable, Sendable {
    case typst
    case tex
    case mixed
    case unknown
}

public enum WritingProjectStatus: String, Codable, Hashable, Sendable {
    case linked
    case missing
    case needsMainFile
    case unsupported
}

public enum AgentActionKind: String, Codable, Hashable, Sendable {
    case writeObsidian
    case editManuscript
    case downloadPaper
    case importLibrary
    case installSkill
    case enableSkill
    case runExternalTool
    case providerCall
    case writeLibraryBundle
    case exportArticle
    case notePatch
    case writingPatch
    case generateResearchOutline
    case custom
}

public enum ResearchPlanKind: String, Codable, Hashable, Sendable {
    case literatureReview = "literature_review"
    case paperReading = "paper_reading"
    case writingSupport = "writing_support"
    case skillInvocation = "skill_invocation"
    case custom
}

public enum ResearchPlanStatus: String, Codable, Hashable, Sendable {
    case draft
    case active
    case completed
    case failed
    case archived
}

public enum AgentActionStatus: String, Codable, Hashable, Sendable {
    case draft
    case pendingApproval
    case approved
    case queued
    case rejected
    case cancelled
    case running
    case succeeded
    case failed
}

public enum AgentActionPermission: String, Codable, Hashable, Sendable {
    case network
    case providerCall
    case downloadPaper
    case importLibrary
    case writeLibraryBundle
    case writeObsidian
    case editManuscript
    case runExternalTool
    case installSkill
    case enableSkill
}

public enum AgentActionStepKind: String, Codable, Hashable, Sendable {
    case previewPatch
    case writeFile
    case download
    case importItem
    case installSkill
    case enableSkill
    case runTool
    case callProvider
    case notify
}

public enum ResearchSkillStatus: String, Codable, Hashable, Sendable {
    case discovered
    case cached
    case installed
    case metadataOnly
    case disabled
    case enabled
    case unavailable
}

public enum ResearchSkillSourceKind: String, Codable, Hashable, Sendable {
    case project
    case user
    case bundled
    case remoteIndex
    case cache
}

public enum ResearchSkillTask: String, Codable, Hashable, Sendable {
    case arxivSearch
    case literatureReview
    case relatedWork
    case paperReading
    case experimentPlanning
    case writing
    case citationDiscovery
}

public enum PendingFilePatchKind: String, Codable, Hashable, Sendable {
    case obsidianMarkdown
    case typstInsertion
    case texInsertion
    case bibliographyUpdate
    case libraryNote
    case exportArtifact
}

public enum PendingFilePatchFormat: String, Codable, Hashable, Sendable {
    case markdown
    case typst
    case tex
    case bibtex
    case plainText
}

public enum PendingFilePatchStatus: String, Codable, Hashable, Sendable {
    case draft
    case previewReady
    case pendingApproval
    case approved
    case rejected
    case applying
    case applied
    case conflicted
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .rejected, .applied, .failed, .cancelled:
            return true
        case .draft, .previewReady, .pendingApproval, .approved, .applying, .conflicted:
            return false
        }
    }
}

public enum FilePatchConflictReason: String, Codable, Hashable, Sendable {
    case targetMissing
    case fileChangedSincePreview
    case anchorMissing
    case unsupportedFormat
}

public enum ExternalFileTargetStatus: String, Codable, Hashable, Sendable {
    case available
    case missing
    case permissionRequired
    case unsupported
}
