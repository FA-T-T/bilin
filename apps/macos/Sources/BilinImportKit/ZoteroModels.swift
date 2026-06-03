import Foundation

public struct ZoteroLibraryConfiguration: Codable, Hashable, Sendable {
    public var databaseURL: URL
    public var dataDirectoryURL: URL

    public init(databaseURL: URL, dataDirectoryURL: URL? = nil) {
        self.databaseURL = databaseURL
        self.dataDirectoryURL = dataDirectoryURL ?? databaseURL.deletingLastPathComponent()
    }

    public init(dataDirectoryURL: URL) {
        self.databaseURL = dataDirectoryURL.appendingPathComponent("zotero.sqlite")
        self.dataDirectoryURL = dataDirectoryURL
    }
}

public struct ZoteroSchemaStatus: Codable, Hashable, Sendable {
    public var missingTables: [String]
    public var missingColumns: [String: [String]]

    public var isReadable: Bool {
        missingTables.isEmpty && missingColumns.values.allSatisfy(\.isEmpty)
    }

    public init(missingTables: [String], missingColumns: [String: [String]]) {
        self.missingTables = missingTables
        self.missingColumns = missingColumns
    }
}

public struct ZoteroCollection: Identifiable, Codable, Hashable, Sendable {
    public var id: Int64
    public var key: String?
    public var name: String
    public var parentCollectionID: Int64?

    public init(id: Int64, key: String?, name: String, parentCollectionID: Int64?) {
        self.id = id
        self.key = key
        self.name = name
        self.parentCollectionID = parentCollectionID
    }
}

public struct ZoteroCreator: Codable, Hashable, Sendable {
    public var firstName: String?
    public var lastName: String?
    public var displayName: String
    public var creatorType: String

    public init(firstName: String?, lastName: String?, displayName: String, creatorType: String) {
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
        self.creatorType = creatorType
    }
}

public struct ZoteroAttachment: Identifiable, Codable, Hashable, Sendable {
    public var id: Int64
    public var key: String
    public var parentItemID: Int64?
    public var contentType: String?
    public var path: String?
    public var resolvedFileURL: URL?

    public init(
        id: Int64,
        key: String,
        parentItemID: Int64?,
        contentType: String?,
        path: String?,
        resolvedFileURL: URL?
    ) {
        self.id = id
        self.key = key
        self.parentItemID = parentItemID
        self.contentType = contentType
        self.path = path
        self.resolvedFileURL = resolvedFileURL
    }
}

public struct ZoteroArXivMetadata: Codable, Hashable, Sendable {
    public var identifier: String
    public var version: String?
    public var sourceField: String

    public init(identifier: String, version: String?, sourceField: String) {
        self.identifier = identifier
        self.version = version
        self.sourceField = sourceField
    }

    public var concreteIdentifier: String {
        version.map { identifier + $0 } ?? identifier
    }
}

public struct ZoteroItem: Identifiable, Codable, Hashable, Sendable {
    public var id: Int64
    public var key: String
    public var itemType: String
    public var title: String?
    public var abstractNote: String?
    public var date: String?
    public var doi: String?
    public var url: String?
    public var extra: String?
    public var libraryCatalog: String?
    public var collections: [ZoteroCollection]
    public var tags: [String]
    public var creators: [ZoteroCreator]
    public var attachments: [ZoteroAttachment]
    public var arxiv: ZoteroArXivMetadata?
    public var dateAdded: String?
    public var dateModified: String?

    public init(
        id: Int64,
        key: String,
        itemType: String,
        title: String?,
        abstractNote: String?,
        date: String?,
        doi: String?,
        url: String?,
        extra: String?,
        libraryCatalog: String?,
        collections: [ZoteroCollection] = [],
        tags: [String] = [],
        creators: [ZoteroCreator] = [],
        attachments: [ZoteroAttachment] = [],
        arxiv: ZoteroArXivMetadata? = nil,
        dateAdded: String? = nil,
        dateModified: String? = nil
    ) {
        self.id = id
        self.key = key
        self.itemType = itemType
        self.title = title
        self.abstractNote = abstractNote
        self.date = date
        self.doi = doi
        self.url = url
        self.extra = extra
        self.libraryCatalog = libraryCatalog
        self.collections = collections
        self.tags = tags
        self.creators = creators
        self.attachments = attachments
        self.arxiv = arxiv
        self.dateAdded = dateAdded
        self.dateModified = dateModified
    }
}

public enum ZoteroBilinAction: String, Codable, Hashable, Sendable {
    case inspectLocalMetadata
    case downloadArXivMetadata
    case importIntoBilinLibrary
    case translateAfterImport
}
