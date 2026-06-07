import Foundation
import CryptoKit

public struct LocalFilePatchResult: Codable, Hashable, Sendable {
    public var targetPath: String
    public var bytes: Int
    public var alreadyPresent: Bool
    public var baseFileHash: String?
    public var appliedFileHash: String?

    public init(
        targetPath: String,
        bytes: Int,
        alreadyPresent: Bool,
        baseFileHash: String? = nil,
        appliedFileHash: String? = nil
    ) {
        self.targetPath = targetPath
        self.bytes = bytes
        self.alreadyPresent = alreadyPresent
        self.baseFileHash = baseFileHash
        self.appliedFileHash = appliedFileHash
    }

    public var actionResultPayload: [String: String] {
        var payload = [
            "target_path": targetPath,
            "bytes": String(bytes),
            "already_present": String(alreadyPresent)
        ]
        if let baseFileHash {
            payload["base_file_hash"] = baseFileHash
        }
        if let appliedFileHash {
            payload["applied_file_hash"] = appliedFileHash
        }
        return payload
    }
}

public struct LocalFilePatchExecutor: Sendable {
    public init() {}

    public static func contentHash(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var fileManager: FileManager {
        .default
    }

    public func apply(
        actionPlan: AgentActionPlan,
        configuration: WorkspaceConfiguration
    ) throws -> LocalFilePatchResult {
        guard actionPlan.status == .approved || actionPlan.status == .running else {
            throw LocalFilePatchExecutionError.approvalRequired
        }

        let targetPath = try localPatchTargetPath(
            for: actionPlan,
            configuration: configuration
        )
        let targetURL = URL(fileURLWithPath: targetPath)
        let patchText = try localPatchText(for: actionPlan)
        try validatePatchTarget(targetURL, for: actionPlan, configuration: configuration)

        let accessURL = securityScopedRootURL(for: actionPlan, configuration: configuration)
        let didAccess = accessURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didAccess {
                accessURL?.stopAccessingSecurityScopedResource()
            }
        }

        let parentURL = targetURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let currentText: String
        if fileManager.fileExists(atPath: targetURL.path) {
            currentText = try String(contentsOf: targetURL, encoding: .utf8)
        } else {
            currentText = ""
        }
        let baseFileHash = Self.contentHash(for: currentText)
        let marker = patchMarker(for: actionPlan, targetURL: targetURL)
        let alreadyPresent = patchAlreadyPresent(
            in: currentText,
            marker: marker,
            actionPlan: actionPlan
        )
        if !alreadyPresent {
            try validateBaseFileHash(for: actionPlan, observed: baseFileHash)
        }
        let finalText: String
        if alreadyPresent {
            finalText = currentText
        } else {
            finalText = textByApplyingPatch(
                patchText,
                marker: marker,
                to: currentText,
                actionPlan: actionPlan
            )
        }
        let appliedFileHash = Self.contentHash(for: finalText)
        try finalText.write(to: targetURL, atomically: true, encoding: .utf8)
        return LocalFilePatchResult(
            targetPath: targetURL.path,
            bytes: finalText.utf8.count,
            alreadyPresent: alreadyPresent,
            baseFileHash: baseFileHash,
            appliedFileHash: appliedFileHash
        )
    }

    private func patchAlreadyPresent(
        in currentText: String,
        marker: (start: String, end: String),
        actionPlan: AgentActionPlan
    ) -> Bool {
        if currentText.contains(marker.start) {
            return true
        }
        guard actionPlan.kind == .writeObsidian || actionPlan.kind == .notePatch,
              let blockAnchor = actionPlan.payload["block_anchor"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !blockAnchor.isEmpty
        else {
            return false
        }
        return currentText.contains(blockAnchor)
    }

    private func textByApplyingPatch(
        _ patchText: String,
        marker: (start: String, end: String),
        to currentText: String,
        actionPlan: AgentActionPlan
    ) -> String {
        let patchLines = patchText.components(separatedBy: "\n")
        let markedPatchLines = ["", marker.start] + patchLines + [marker.end, ""]
        if let insertionLine = sectionEndInsertionLine(for: actionPlan, in: currentText) {
            var lines = currentText.components(separatedBy: "\n")
            let insertionIndex = min(insertionLine + 1, lines.count)
            lines.insert(contentsOf: markedPatchLines, at: insertionIndex)
            return lines.joined(separator: "\n")
        }

        let separator = currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        return currentText + separator + marker.start + "\n" + patchText + "\n" + marker.end + "\n"
    }

    private func sectionEndInsertionLine(for actionPlan: AgentActionPlan, in currentText: String) -> Int? {
        guard actionPlan.kind == .editManuscript || actionPlan.kind == .writingPatch else {
            return nil
        }
        guard actionPlan.payload["insertion_mode"] == WritingPatchInsertionMode.sectionEnd.rawValue else {
            return nil
        }
        guard let lineValue = actionPlan.payload["insertion_line"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let line = Int(lineValue),
              line >= 0
        else {
            return nil
        }
        let lineCount = currentText.components(separatedBy: "\n").count
        guard line < lineCount else {
            return nil
        }
        return line
    }

    private func localPatchTargetPath(
        for actionPlan: AgentActionPlan,
        configuration: WorkspaceConfiguration
    ) throws -> String {
        if let targetPath = actionPlan.payload["target_path"], !targetPath.isEmpty {
            return targetPath
        }
        if
            let targetNote = actionPlan.payload["target_note"],
            let vault = configuration.selectedObsidianVault
        {
            return (vault.path as NSString).appendingPathComponent(targetNote)
        }
        if let targetPath = actionPlan.steps.compactMap(\.targetPath).first, !targetPath.isEmpty {
            return targetPath
        }
        throw LocalFilePatchExecutionError.missingTargetPath
    }

    private func localPatchText(for actionPlan: AgentActionPlan) throws -> String {
        if let patch = actionPlan.preview?["patch"], !patch.isEmpty {
            return patch
        }
        if let patch = actionPlan.payload["patch"], !patch.isEmpty {
            return patch
        }
        throw LocalFilePatchExecutionError.missingPatchText
    }

    private func validateBaseFileHash(for actionPlan: AgentActionPlan, observed: String) throws {
        guard let expected = expectedBaseFileHash(for: actionPlan) else { return }
        guard expected == observed else {
            throw LocalFilePatchExecutionError.fileChangedSincePreview(
                expected: expected,
                observed: observed
            )
        }
    }

    private func expectedBaseFileHash(for actionPlan: AgentActionPlan) -> String? {
        for key in ["base_file_hash", "base_hash", "target_content_hash"] {
            if let value = actionPlan.payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func validatePatchTarget(
        _ targetURL: URL,
        for actionPlan: AgentActionPlan,
        configuration: WorkspaceConfiguration
    ) throws {
        switch actionPlan.kind {
        case .writeObsidian, .notePatch:
            guard let vault = configuration.selectedObsidianVault else {
                throw LocalFilePatchExecutionError.missingWorkspaceRoot("Obsidian vault")
            }
            try validate(targetURL, isInside: vault.path, rootName: "Obsidian vault")
        case .editManuscript, .writingPatch:
            guard let writingRoot = configuration.writingProjectRoots.first else {
                throw LocalFilePatchExecutionError.missingWorkspaceRoot("writing project")
            }
            try validate(targetURL, isInside: writingRoot.path, rootName: "writing project")
            var isDirectory: ObjCBool = false
            if
                fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                throw LocalFilePatchExecutionError.targetIsDirectory(targetURL.path)
            }
        case .downloadPaper,
             .importLibrary,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .generateResearchOutline,
             .custom:
            throw LocalFilePatchExecutionError.unsupportedActionKind(actionPlan.kind.rawValue)
        }
    }

    private func securityScopedRootURL(
        for actionPlan: AgentActionPlan,
        configuration: WorkspaceConfiguration
    ) -> URL? {
        let record: WorkspacePathRecord?
        switch actionPlan.kind {
        case .writeObsidian, .notePatch:
            record = configuration.selectedObsidianVault
        case .editManuscript, .writingPatch:
            record = configuration.writingProjectRoots.first
        case .downloadPaper,
             .importLibrary,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .generateResearchOutline,
             .custom:
            record = nil
        }
        guard let record else { return nil }
        if let bookmarkData = record.securityScopedBookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale {
                return url
            }
        }
        return URL(fileURLWithPath: record.path, isDirectory: true)
    }

    private func validate(_ targetURL: URL, isInside rootPath: String, rootName: String) throws {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
        let target = targetURL.standardizedFileURL.path
        guard target == root || target.hasPrefix(root + "/") else {
            throw LocalFilePatchExecutionError.targetOutsideWorkspace(target, rootName)
        }
    }

    private func patchMarker(
        for actionPlan: AgentActionPlan,
        targetURL: URL
    ) -> (start: String, end: String) {
        switch targetURL.pathExtension.lowercased() {
        case "tex":
            return (
                "% ilios-action-plan:\(actionPlan.id)",
                "% /ilios-action-plan:\(actionPlan.id)"
            )
        case "typ":
            return (
                "// ilios-action-plan:\(actionPlan.id)",
                "// /ilios-action-plan:\(actionPlan.id)"
            )
        default:
            return (
                "<!-- ilios-action-plan:\(actionPlan.id) -->",
                "<!-- /ilios-action-plan:\(actionPlan.id) -->"
            )
        }
    }
}

public enum LocalFilePatchExecutionError: Error, LocalizedError, Sendable {
    case approvalRequired
    case missingTargetPath
    case missingPatchText
    case missingWorkspaceRoot(String)
    case targetOutsideWorkspace(String, String)
    case targetIsDirectory(String)
    case unsupportedActionKind(String)
    case fileChangedSincePreview(expected: String, observed: String)

    public var errorDescription: String? {
        switch self {
        case .approvalRequired:
            return "Action plan must be approved before it can write files."
        case .missingTargetPath:
            return "Action plan does not include a target file path."
        case .missingPatchText:
            return "Action plan does not include patch text."
        case .missingWorkspaceRoot(let name):
            return "No \(name) is configured."
        case .targetOutsideWorkspace(let path, let rootName):
            return "\(path) is outside the configured \(rootName)."
        case .targetIsDirectory(let path):
            return "\(path) is a directory, not a manuscript file."
        case .unsupportedActionKind(let kind):
            return "This local executor cannot apply \(kind) action plans."
        case .fileChangedSincePreview(let expected, let observed):
            return "Target file changed since preview. Expected base hash \(expected), observed \(observed)."
        }
    }
}
