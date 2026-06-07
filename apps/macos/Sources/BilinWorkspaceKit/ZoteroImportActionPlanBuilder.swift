import Foundation

public struct ZoteroImportAttachmentCandidate: Hashable, Sendable {
    public var key: String
    public var contentType: String?
    public var path: String?
    public var resolvedFilePath: String?

    public init(
        key: String,
        contentType: String? = nil,
        path: String? = nil,
        resolvedFilePath: String? = nil
    ) {
        self.key = key
        self.contentType = contentType
        self.path = path
        self.resolvedFilePath = resolvedFilePath
    }
}

public struct ZoteroImportCandidate: Hashable, Sendable {
    public var itemID: String
    public var key: String
    public var itemType: String
    public var title: String
    public var abstract: String?
    public var doi: String?
    public var url: String?
    public var arxivIdentifier: String?
    public var arxivVersion: String?
    public var creators: [String]
    public var collections: [String]
    public var tags: [String]
    public var attachments: [ZoteroImportAttachmentCandidate]

    public init(
        itemID: String,
        key: String,
        itemType: String,
        title: String,
        abstract: String? = nil,
        doi: String? = nil,
        url: String? = nil,
        arxivIdentifier: String? = nil,
        arxivVersion: String? = nil,
        creators: [String] = [],
        collections: [String] = [],
        tags: [String] = [],
        attachments: [ZoteroImportAttachmentCandidate] = []
    ) {
        self.itemID = itemID
        self.key = key
        self.itemType = itemType
        self.title = title
        self.abstract = abstract
        self.doi = doi
        self.url = url
        self.arxivIdentifier = arxivIdentifier
        self.arxivVersion = arxivVersion
        self.creators = creators
        self.collections = collections
        self.tags = tags
        self.attachments = attachments
    }
}

public struct ZoteroImportActionPlanBuildResult: Hashable, Sendable {
    public var actionPlanPayload: [String: String]
    public var actionPlanPreview: [String: String]
    public var actionPlanDraft: AgentActionPlanDraft
    public var stepDrafts: [AgentActionPlanStepDraft]

    public init(
        actionPlanPayload: [String: String],
        actionPlanPreview: [String: String],
        actionPlanDraft: AgentActionPlanDraft,
        stepDrafts: [AgentActionPlanStepDraft]
    ) {
        self.actionPlanPayload = actionPlanPayload
        self.actionPlanPreview = actionPlanPreview
        self.actionPlanDraft = actionPlanDraft
        self.stepDrafts = stepDrafts
    }
}

public struct ZoteroImportActionPlanBuilder: Sendable {
    public init() {}

    public func build(
        candidate: ZoteroImportCandidate,
        localLibraryId: String,
        localLibraryPath: String?,
        zoteroLibraryPath: String?
    ) -> ZoteroImportActionPlanBuildResult {
        let arxivIdentifier = Self.trimmed(candidate.arxivIdentifier)
        let hasArXivDownload = arxivIdentifier != nil
        let permissions = Self.requiredPermissions(downloadsPaper: hasArXivDownload)
        let payload = Self.payload(
            candidate: candidate,
            localLibraryId: localLibraryId,
            localLibraryPath: localLibraryPath,
            zoteroLibraryPath: zoteroLibraryPath
        )
        let preview = Self.preview(candidate: candidate, downloadsPaper: hasArXivDownload)
        let steps = Self.steps(candidate: candidate, payload: payload, preview: preview, downloadsPaper: hasArXivDownload)
        let kind: AgentActionKind = hasArXivDownload ? .downloadPaper : .importLibrary
        let title = hasArXivDownload
            ? "Prepare Zotero arXiv import"
            : "Prepare Zotero metadata import"
        let description = hasArXivDownload
            ? "Confirm arXiv download and Bilin library import for \(candidate.title)."
            : "Confirm Bilin library import for Zotero metadata \(candidate.title)."

        let actionPlanDraft = AgentActionPlanDraft(
            kind: kind,
            title: title,
            description: description,
            idempotencyKey: Self.idempotencyKey(
                candidate: candidate,
                localLibraryId: localLibraryId,
                zoteroLibraryPath: zoteroLibraryPath
            ),
            requiredPermissions: permissions,
            payload: payload,
            preview: preview,
            steps: steps
        )

        return ZoteroImportActionPlanBuildResult(
            actionPlanPayload: payload,
            actionPlanPreview: preview,
            actionPlanDraft: actionPlanDraft,
            stepDrafts: steps
        )
    }

    private static func payload(
        candidate: ZoteroImportCandidate,
        localLibraryId: String,
        localLibraryPath: String?,
        zoteroLibraryPath: String?
    ) -> [String: String] {
        var payload: [String: String] = [
            "source": "zotero",
            "zotero_item_id": candidate.itemID,
            "zotero_key": candidate.key,
            "item_type": candidate.itemType,
            "title": candidate.title,
            "local_library_id": localLibraryId
        ]
        insert(&payload, key: "local_library_path", value: localLibraryPath)
        insert(&payload, key: "zotero_library_path", value: zoteroLibraryPath)
        insert(&payload, key: "abstract", value: candidate.abstract)
        insert(&payload, key: "doi", value: candidate.doi)
        insert(&payload, key: "url", value: candidate.url)
        insert(&payload, key: "arxiv_id", value: candidate.arxivIdentifier)
        insert(&payload, key: "arxiv_version", value: candidate.arxivVersion)
        insert(&payload, key: "creators", value: joined(candidate.creators, separator: "; "))
        insert(&payload, key: "collections", value: joined(candidate.collections, separator: "; "))
        insert(&payload, key: "tags", value: joined(candidate.tags, separator: ", "))
        insert(&payload, key: "attachment_keys", value: joined(candidate.attachments.map(\.key), separator: "\n"))
        insert(&payload, key: "attachment_paths", value: joined(candidate.attachments.compactMap(\.path), separator: "\n"))
        insert(
            &payload,
            key: "attachment_file_paths",
            value: joined(candidate.attachments.compactMap(\.resolvedFilePath), separator: "\n")
        )
        return payload
    }

    private static func preview(
        candidate: ZoteroImportCandidate,
        downloadsPaper: Bool
    ) -> [String: String] {
        var lines = [
            candidate.title,
            "Zotero key: \(candidate.key)",
            "Item type: \(candidate.itemType)"
        ]
        if let arxivIdentifier = trimmed(candidate.arxivIdentifier) {
            lines.append("arXiv: \(arxivIdentifier)\(candidate.arxivVersion ?? "")")
        }
        if let doi = trimmed(candidate.doi) {
            lines.append("DOI: \(doi)")
        }
        if !candidate.creators.isEmpty {
            lines.append("Creators: \(candidate.creators.joined(separator: "; "))")
        }
        if !candidate.attachments.isEmpty {
            lines.append("Attachments: \(candidate.attachments.count)")
        }

        return [
            "candidate_summary": lines.joined(separator: "\n"),
            "import_summary": downloadsPaper
                ? "Download the arXiv paper, then import the Zotero metadata into the selected Bilin library."
                : "Import the selected Zotero metadata into the selected Bilin library."
        ]
    }

    private static func steps(
        candidate: ZoteroImportCandidate,
        payload: [String: String],
        preview: [String: String],
        downloadsPaper: Bool
    ) -> [AgentActionPlanStepDraft] {
        var steps: [AgentActionPlanStepDraft] = []
        if downloadsPaper {
            steps.append(
                AgentActionPlanStepDraft(
                    kind: "download",
                    title: "Download arXiv paper",
                    description: "Fetch the arXiv source or PDF before importing it into the Bilin library.",
                    requiredPermissions: [.network, .downloadPaper],
                    payload: payload,
                    preview: preview
                )
            )
        }
        steps.append(
            AgentActionPlanStepDraft(
                kind: "import_item",
                title: "Import Zotero item into Bilin",
                description: "Create or update the Bilin library record after the user approves this plan.",
                requiredPermissions: [.importLibrary, .writeLibraryBundle],
                payload: payload,
                preview: preview
            )
        )
        return steps
    }

    private static func requiredPermissions(downloadsPaper: Bool) -> [AgentActionPermission] {
        if downloadsPaper {
            return [.network, .downloadPaper, .importLibrary, .writeLibraryBundle]
        }
        return [.importLibrary, .writeLibraryBundle]
    }

    private static func idempotencyKey(
        candidate: ZoteroImportCandidate,
        localLibraryId: String,
        zoteroLibraryPath: String?
    ) -> String {
        [
            "zotero-import",
            localLibraryId,
            candidate.itemID,
            candidate.key,
            trimmed(candidate.arxivIdentifier) ?? "metadata",
            trimmed(zoteroLibraryPath) ?? "unconfigured-zotero"
        ]
        .map(sanitizedKeyPart)
        .joined(separator: "-")
    }

    private static func insert(_ payload: inout [String: String], key: String, value: String?) {
        guard let value = trimmed(value) else { return }
        payload[key] = value
    }

    private static func joined(_ values: [String], separator: String) -> String? {
        let clean = values.compactMap(trimmed)
        guard !clean.isEmpty else { return nil }
        return clean.joined(separator: separator)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func sanitizedKeyPart(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        .reduce(into: "") { result, character in
            result.append(character)
        }
    }
}
