import Foundation

public struct WorkspaceConfiguration: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var selectedBilinLibrary: WorkspacePathRecord?
    public var selectedZoteroLibrary: WorkspacePathRecord?
    public var selectedObsidianVault: WorkspacePathRecord?
    public var writingProjectRoots: [WorkspacePathRecord]

    public init(
        schemaVersion: Int = 1,
        selectedBilinLibrary: WorkspacePathRecord? = nil,
        selectedZoteroLibrary: WorkspacePathRecord? = nil,
        selectedObsidianVault: WorkspacePathRecord? = nil,
        writingProjectRoots: [WorkspacePathRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.selectedBilinLibrary = selectedBilinLibrary
        self.selectedZoteroLibrary = selectedZoteroLibrary
        self.selectedObsidianVault = selectedObsidianVault
        self.writingProjectRoots = writingProjectRoots
    }

    public mutating func upsertPathRecord(_ record: WorkspacePathRecord) {
        switch record.kind {
        case .bilinLibrary:
            selectedBilinLibrary = record
        case .zoteroLibrary:
            selectedZoteroLibrary = record
        case .obsidianVault:
            selectedObsidianVault = record
        case .writingProjectRoot:
            if let existingIndex = writingProjectRoots.firstIndex(where: { $0.id == record.id }) {
                writingProjectRoots[existingIndex] = record
            } else {
                writingProjectRoots.append(record)
            }
        }
    }

    public mutating func removePathRecord(kind: WorkspacePathKind, id: String? = nil) {
        switch kind {
        case .bilinLibrary:
            selectedBilinLibrary = nil
        case .zoteroLibrary:
            selectedZoteroLibrary = nil
        case .obsidianVault:
            selectedObsidianVault = nil
        case .writingProjectRoot:
            guard let id else {
                writingProjectRoots = []
                return
            }
            writingProjectRoots.removeAll { $0.id == id }
        }
    }

    public mutating func refreshPathRecords(_ refresh: (WorkspacePathRecord) -> WorkspacePathRecord) {
        selectedBilinLibrary = selectedBilinLibrary.map(refresh)
        selectedZoteroLibrary = selectedZoteroLibrary.map(refresh)
        selectedObsidianVault = selectedObsidianVault.map(refresh)
        writingProjectRoots = writingProjectRoots.map(refresh)
    }

    public func updatingPathRecord(_ record: WorkspacePathRecord) -> WorkspaceConfiguration {
        var configuration = self
        configuration.upsertPathRecord(record)
        return configuration
    }

    public func removingPathRecord(kind: WorkspacePathKind, id: String? = nil) -> WorkspaceConfiguration {
        var configuration = self
        configuration.removePathRecord(kind: kind, id: id)
        return configuration
    }

    public func refreshingPathRecords(_ refresh: (WorkspacePathRecord) -> WorkspacePathRecord) -> WorkspaceConfiguration {
        var configuration = self
        configuration.refreshPathRecords(refresh)
        return configuration
    }
}

public struct WorkspacePathRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public var kind: WorkspacePathKind
    public var status: ExternalFileTargetStatus
    public var securityScopedBookmarkData: Data?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        path: String,
        kind: WorkspacePathKind,
        status: ExternalFileTargetStatus = .available,
        securityScopedBookmarkData: Data? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.status = status
        self.securityScopedBookmarkData = securityScopedBookmarkData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum WorkspacePathKind: String, Codable, Hashable, Sendable {
    case bilinLibrary
    case zoteroLibrary
    case obsidianVault
    case writingProjectRoot
}
