import Foundation

public struct ZoteroImportBundleWriteResult: Hashable, Sendable {
    public var bundlePath: String
    public var metadataPath: String
    public var bytes: Int
    public var copiedAttachmentCount: Int
    public var missingAttachmentCount: Int
    public var alreadyPresent: Bool

    public init(
        bundlePath: String,
        metadataPath: String,
        bytes: Int,
        copiedAttachmentCount: Int,
        missingAttachmentCount: Int,
        alreadyPresent: Bool
    ) {
        self.bundlePath = bundlePath
        self.metadataPath = metadataPath
        self.bytes = bytes
        self.copiedAttachmentCount = copiedAttachmentCount
        self.missingAttachmentCount = missingAttachmentCount
        self.alreadyPresent = alreadyPresent
    }

    public var actionResultPayload: [String: String] {
        [
            "bundle_path": bundlePath,
            "metadata_path": metadataPath,
            "bytes": String(bytes),
            "copied_attachment_count": String(copiedAttachmentCount),
            "missing_attachment_count": String(missingAttachmentCount),
            "already_present": String(alreadyPresent)
        ]
    }
}

public enum ZoteroImportBundleWriterError: Error, Equatable, LocalizedError, Sendable {
    case approvalRequired
    case unsupportedActionKind(String)
    case missingLibraryPath
    case missingLibraryDirectory(String)
    case missingZoteroIdentity
    case metadataEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .approvalRequired:
            return "Approve the Zotero import action plan before writing an import bundle."
        case .unsupportedActionKind(let kind):
            return "Zotero import bundle writing does not support action kind \(kind)."
        case .missingLibraryPath:
            return "The Zotero import action plan does not include a Bilin library path."
        case .missingLibraryDirectory(let path):
            return "The Bilin library directory is not available: \(path)."
        case .missingZoteroIdentity:
            return "The Zotero import action plan does not include a Zotero item id or key."
        case .metadataEncodingFailed:
            return "The Zotero import metadata could not be encoded as JSON."
        }
    }
}

public struct ZoteroImportBundleWriter: Sendable {
    public init() {}

    public func write(
        actionPlan: AgentActionPlan,
        libraryPath: String?
    ) throws -> ZoteroImportBundleWriteResult {
        guard actionPlan.status == .approved || actionPlan.status == .running else {
            throw ZoteroImportBundleWriterError.approvalRequired
        }
        guard actionPlan.kind == .downloadPaper || actionPlan.kind == .importLibrary else {
            throw ZoteroImportBundleWriterError.unsupportedActionKind(actionPlan.kind.rawValue)
        }
        guard let libraryPath = Self.trimmed(libraryPath ?? actionPlan.payload["local_library_path"]) else {
            throw ZoteroImportBundleWriterError.missingLibraryPath
        }

        let libraryURL = URL(fileURLWithPath: libraryPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: libraryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ZoteroImportBundleWriterError.missingLibraryDirectory(libraryURL.path)
        }

        guard let identity = Self.identity(from: actionPlan) else {
            throw ZoteroImportBundleWriterError.missingZoteroIdentity
        }

        let bundleURL = libraryURL
            .appendingPathComponent("imports", isDirectory: true)
            .appendingPathComponent("zotero", isDirectory: true)
            .appendingPathComponent(identity, isDirectory: true)
        let attachmentsURL = bundleURL.appendingPathComponent("attachments", isDirectory: true)
        let metadataURL = bundleURL.appendingPathComponent("metadata.json")

        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        let attachmentResult = try copyAttachments(
            from: Self.attachmentFilePaths(from: actionPlan),
            into: attachmentsURL
        )
        let metadata = try Self.metadataData(
            actionPlan: actionPlan,
            copiedAttachmentPaths: attachmentResult.copiedPaths,
            missingAttachmentPaths: attachmentResult.missingPaths
        )

        let alreadyPresent = Self.existingMetadata(at: metadataURL) == metadata
        try metadata.write(to: metadataURL, options: [.atomic])

        return ZoteroImportBundleWriteResult(
            bundlePath: bundleURL.path,
            metadataPath: metadataURL.path,
            bytes: metadata.count + attachmentResult.bytes,
            copiedAttachmentCount: attachmentResult.copiedPaths.count,
            missingAttachmentCount: attachmentResult.missingPaths.count,
            alreadyPresent: alreadyPresent
        )
    }

    private func copyAttachments(
        from sourcePaths: [String],
        into attachmentsURL: URL
    ) throws -> (copiedPaths: [String], missingPaths: [String], bytes: Int) {
        var copiedPaths: [String] = []
        var missingPaths: [String] = []
        var bytes = 0

        for sourcePath in sourcePaths {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                missingPaths.append(sourcePath)
                continue
            }

            let targetURL = Self.uniqueTargetURL(
                for: sourceURL.lastPathComponent,
                in: attachmentsURL
            )
            if !FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            }
            copiedPaths.append(targetURL.path)
            let attributes = try? FileManager.default.attributesOfItem(atPath: targetURL.path)
            bytes += attributes?[.size] as? Int ?? 0
        }

        return (copiedPaths, missingPaths, bytes)
    }

    private static func metadataData(
        actionPlan: AgentActionPlan,
        copiedAttachmentPaths: [String],
        missingAttachmentPaths: [String]
    ) throws -> Data {
        let object: [String: Any] = [
            "action_plan_id": actionPlan.id,
            "kind": actionPlan.kind.rawValue,
            "payload_hash": actionPlan.payloadHash,
            "payload": actionPlan.payload,
            "preview": actionPlan.preview ?? [:],
            "copied_attachment_paths": copiedAttachmentPaths,
            "missing_attachment_paths": missingAttachmentPaths
        ]
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ZoteroImportBundleWriterError.metadataEncodingFailed
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func existingMetadata(at url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    private static func identity(from actionPlan: AgentActionPlan) -> String? {
        let value = trimmed(actionPlan.payload["zotero_key"])
            ?? trimmed(actionPlan.payload["zotero_item_id"])
        return value.map(sanitizedPathComponent)
    }

    private static func attachmentFilePaths(from actionPlan: AgentActionPlan) -> [String] {
        guard let raw = trimmed(actionPlan.payload["attachment_file_paths"]) else {
            return []
        }
        return raw
            .split(whereSeparator: \.isNewline)
            .compactMap { trimmed(String($0)) }
    }

    private static func uniqueTargetURL(for fileName: String, in directoryURL: URL) -> URL {
        let cleanName = sanitizedFileName(fileName)
        return directoryURL.appendingPathComponent(cleanName, isDirectory: false)
    }

    private static func sanitizedFileName(_ fileName: String) -> String {
        let name = trimmed(fileName) ?? "attachment"
        let forbidden = CharacterSet(charactersIn: "/:")
        let scalars = name.unicodeScalars.map { scalar in
            forbidden.contains(scalar) ? "_" : Character(scalar)
        }
        return String(scalars)
    }

    private static func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(sanitized)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
