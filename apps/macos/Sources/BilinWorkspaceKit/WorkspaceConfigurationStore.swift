import Foundation

public struct WorkspaceConfigurationStore {
    public let configurationFileURL: URL

    public init(configurationFileURL: URL) {
        self.configurationFileURL = configurationFileURL
    }

    public func load() throws -> WorkspaceConfiguration {
        guard FileManager.default.fileExists(atPath: configurationFileURL.path) else {
            return WorkspaceConfiguration()
        }

        let data: Data
        do {
            data = try Data(contentsOf: configurationFileURL)
        } catch {
            throw WorkspaceConfigurationStoreError.readFailed(
                url: configurationFileURL,
                message: error.localizedDescription
            )
        }

        do {
            return try Self.decoder.decode(WorkspaceConfiguration.self, from: data)
        } catch {
            throw WorkspaceConfigurationStoreError.corruptConfiguration(
                url: configurationFileURL,
                message: error.localizedDescription
            )
        }
    }

    public func save(_ configuration: WorkspaceConfiguration) throws {
        let data: Data
        do {
            data = try Self.encoder.encode(configuration)
        } catch {
            throw WorkspaceConfigurationStoreError.writeFailed(
                url: configurationFileURL,
                message: error.localizedDescription
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: configurationFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: configurationFileURL, options: [.atomic])
        } catch {
            throw WorkspaceConfigurationStoreError.writeFailed(
                url: configurationFileURL,
                message: error.localizedDescription
            )
        }
    }

    @discardableResult
    public func updatePathRecord(_ record: WorkspacePathRecord) throws -> WorkspaceConfiguration {
        var configuration = try load()
        configuration.upsertPathRecord(record)
        try save(configuration)
        return configuration
    }

    @discardableResult
    public func removePathRecord(kind: WorkspacePathKind, id: String? = nil) throws -> WorkspaceConfiguration {
        var configuration = try load()
        configuration.removePathRecord(kind: kind, id: id)
        try save(configuration)
        return configuration
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum WorkspaceConfigurationStoreError: Error, Equatable, LocalizedError {
    case readFailed(url: URL, message: String)
    case corruptConfiguration(url: URL, message: String)
    case writeFailed(url: URL, message: String)

    public var errorDescription: String? {
        switch self {
        case .readFailed(let url, let message):
            return "Could not read workspace configuration at \(url.path): \(message)"
        case .corruptConfiguration(let url, let message):
            return "Workspace configuration at \(url.path) is not valid JSON for this schema: \(message)"
        case .writeFailed(let url, let message):
            return "Could not write workspace configuration at \(url.path): \(message)"
        }
    }
}
