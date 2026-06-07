import Foundation

public struct WorkspaceConfigurationCoordinator {
    public typealias BookmarkDataProvider = (URL) -> Data?

    public var configurationStore: WorkspaceConfigurationStore
    public var pathDetector: WorkspacePathDetector
    public var fileManager: FileManager
    private var bookmarkDataProvider: BookmarkDataProvider

    public init(
        configurationStore: WorkspaceConfigurationStore,
        pathDetector: WorkspacePathDetector = WorkspacePathDetector(),
        fileManager: FileManager = .default,
        bookmarkDataProvider: BookmarkDataProvider? = nil
    ) {
        self.configurationStore = configurationStore
        self.pathDetector = pathDetector
        self.fileManager = fileManager
        self.bookmarkDataProvider = bookmarkDataProvider ?? Self.securityScopedBookmarkData
    }

    public func load() throws -> WorkspaceConfiguration {
        try configurationStore.load()
    }

    public func detectPathRecords(now: Date = Date()) -> [WorkspacePathRecord] {
        pathDetector.detectPathRecords(now: now)
    }

    @discardableResult
    public func persistPath(
        url: URL,
        kind: WorkspacePathKind,
        now: Date = Date()
    ) throws -> WorkspaceConfiguration {
        try configurationStore.updatePathRecord(
            pathRecord(url: url, kind: kind, now: now)
        )
    }

    @discardableResult
    public func persistDetectedPathRecord(
        _ record: WorkspacePathRecord,
        now: Date = Date()
    ) throws -> WorkspaceConfiguration {
        let url = URL(fileURLWithPath: record.path, isDirectory: true)
        let persisted = WorkspacePathRecord(
            id: record.id,
            name: record.name,
            path: normalizedURL(url, kind: record.kind).path,
            kind: record.kind,
            status: status(for: normalizedURL(url, kind: record.kind), kind: record.kind),
            securityScopedBookmarkData: bookmarkDataProvider(url),
            createdAt: record.createdAt,
            updatedAt: now
        )
        return try configurationStore.updatePathRecord(persisted)
    }

    @discardableResult
    public func removePathRecord(_ record: WorkspacePathRecord) throws -> WorkspaceConfiguration {
        try configurationStore.removePathRecord(kind: record.kind, id: record.id)
    }

    @discardableResult
    public func refreshConfiguredPathStatuses(now: Date = Date()) throws -> WorkspaceConfiguration {
        let current = try configurationStore.load()
        let refreshed = current.refreshingPathRecords { record in
            refreshPathRecordStatus(record, now: now)
        }
        if refreshed != current {
            try configurationStore.save(refreshed)
        }
        return refreshed
    }

    public func pathRecord(
        url: URL,
        kind: WorkspacePathKind,
        now: Date = Date()
    ) -> WorkspacePathRecord {
        let normalizedURL = normalizedURL(url, kind: kind)
        return WorkspacePathRecord(
            id: recordID(kind: kind, url: normalizedURL),
            name: normalizedURL.lastPathComponent.isEmpty ? normalizedURL.path : normalizedURL.lastPathComponent,
            path: normalizedURL.path,
            kind: kind,
            status: status(for: normalizedURL, kind: kind),
            securityScopedBookmarkData: bookmarkDataProvider(normalizedURL),
            createdAt: now,
            updatedAt: now
        )
    }

    private func refreshPathRecordStatus(
        _ record: WorkspacePathRecord,
        now: Date
    ) -> WorkspacePathRecord {
        let normalizedURL = normalizedURL(URL(fileURLWithPath: record.path), kind: record.kind)
        let refreshedStatus = status(for: normalizedURL, kind: record.kind)
        var refreshed = record
        refreshed.path = normalizedURL.path
        refreshed.status = refreshedStatus
        if refreshed.path != record.path || refreshed.status != record.status {
            refreshed.updatedAt = now
        }
        return refreshed
    }

    private func normalizedURL(_ url: URL, kind: WorkspacePathKind) -> URL {
        switch kind {
        case .bilinLibrary where url.lastPathComponent == "library.sqlite":
            return url.deletingLastPathComponent()
        case .zoteroLibrary where url.lastPathComponent == "zotero.sqlite":
            return url.deletingLastPathComponent()
        case .bilinLibrary, .zoteroLibrary, .obsidianVault, .writingProjectRoot:
            return url
        }
    }

    private func recordID(kind: WorkspacePathKind, url: URL) -> String {
        switch kind {
        case .bilinLibrary:
            return "selected-bilin-library"
        case .zoteroLibrary:
            return "selected-zotero-library"
        case .obsidianVault:
            return "selected-obsidian-vault"
        case .writingProjectRoot:
            return "writing-project-\(url.path)"
        }
    }

    private func status(for url: URL, kind: WorkspacePathKind) -> ExternalFileTargetStatus {
        switch kind {
        case .bilinLibrary:
            return directoryStatus(for: url)
                ?? requiredFileStatus(in: url, filename: "library.sqlite")
        case .zoteroLibrary:
            return directoryStatus(for: url)
                ?? requiredFileStatus(in: url, filename: "zotero.sqlite")
        case .obsidianVault, .writingProjectRoot:
            return directoryStatus(for: url) ?? .available
        }
    }

    private func directoryStatus(for url: URL) -> ExternalFileTargetStatus? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        guard isDirectory.boolValue else {
            return .unsupported
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            return .permissionRequired
        }
        return nil
    }

    private func requiredFileStatus(in directoryURL: URL, filename: String) -> ExternalFileTargetStatus {
        let fileURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        return fileManager.isReadableFile(atPath: fileURL.path) ? .available : .permissionRequired
    }

    private static func securityScopedBookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

public extension WorkspaceConfigurationCoordinator {
    static func defaultCoordinator() -> WorkspaceConfigurationCoordinator {
        WorkspaceConfigurationCoordinator(configurationStore: .defaultStore())
    }
}

public extension WorkspaceConfigurationStore {
    static func defaultStore() -> WorkspaceConfigurationStore {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return WorkspaceConfigurationStore(
            configurationFileURL: applicationSupportURL
                .appendingPathComponent("Ilios", isDirectory: true)
                .appendingPathComponent("workspace-configuration.json")
        )
    }
}
