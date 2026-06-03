import Foundation

public struct Library: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public var status: LibraryStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        path: String,
        status: LibraryStatus = .active,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum LibraryStatus: String, Codable, Hashable, Sendable {
    case active
    case missing
    case archived
}

public struct Article: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var libraryId: String
    public var source: String
    public var externalId: String
    public var title: String
    public var activeRevisionId: String

    public init(
        id: String,
        libraryId: String,
        source: String,
        externalId: String,
        title: String,
        activeRevisionId: String
    ) {
        self.id = id
        self.libraryId = libraryId
        self.source = source
        self.externalId = externalId
        self.title = title
        self.activeRevisionId = activeRevisionId
    }
}

public struct ArticleRevision: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var articleId: String
    public var version: String
    public var bundlePath: String
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        articleId: String,
        version: String,
        bundlePath: String,
        status: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.articleId = articleId
        self.version = version
        self.bundlePath = bundlePath
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DocumentBlock: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var articleRevisionId: String
    public var blockUid: String
    public var structuralPath: String
    public var blockType: DocumentBlockKind
    public var parentUid: String?
    public var contentHash: String
    public var contextHash: String?
    public var sourceMarkdown: String
    public var sourceLatex: String?
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        articleRevisionId: String,
        blockUid: String,
        structuralPath: String,
        blockType: DocumentBlockKind,
        parentUid: String? = nil,
        contentHash: String,
        contextHash: String? = nil,
        sourceMarkdown: String,
        sourceLatex: String? = nil,
        metadata: [String: String] = [:],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.articleRevisionId = articleRevisionId
        self.blockUid = blockUid
        self.structuralPath = structuralPath
        self.blockType = blockType
        self.parentUid = parentUid
        self.contentHash = contentHash
        self.contextHash = contextHash
        self.sourceMarkdown = sourceMarkdown
        self.sourceLatex = sourceLatex
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum DocumentBlockKind: String, Codable, Hashable, Sendable {
    case title
    case abstract
    case section
    case subsection
    case paragraph
    case equation
    case figure
    case table
    case bibliography
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = DocumentBlockKind(rawValue: rawValue) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct Citation: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var articleRevisionId: String
    public var key: String
    public var label: String?
    public var title: String?

    public init(
        id: String,
        articleRevisionId: String,
        key: String,
        label: String? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.articleRevisionId = articleRevisionId
        self.key = key
        self.label = label
        self.title = title
    }
}

public struct Translation: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var blockId: String
    public var targetLanguage: String
    public var rawMarkdown: String
    public var isDefault: Bool

    public init(
        id: String,
        blockId: String,
        targetLanguage: String,
        rawMarkdown: String,
        isDefault: Bool = false
    ) {
        self.id = id
        self.blockId = blockId
        self.targetLanguage = targetLanguage
        self.rawMarkdown = rawMarkdown
        self.isDefault = isDefault
    }
}

public struct ReaderNote: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var articleRevisionId: String
    public var blockUid: String?
    public var title: String
    public var markdown: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        articleRevisionId: String,
        blockUid: String? = nil,
        title: String,
        markdown: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.articleRevisionId = articleRevisionId
        self.blockUid = blockUid
        self.title = title
        self.markdown = markdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ArticleTask: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var libraryId: String?
    public var articleRevisionId: String?
    public var articleTitle: String?
    public var status: ArticleTaskStatus
    public var stage: String?
    public var message: String?
    public var progress: Double?

    public init(
        id: String,
        libraryId: String? = nil,
        articleRevisionId: String? = nil,
        articleTitle: String? = nil,
        status: ArticleTaskStatus,
        stage: String? = nil,
        message: String? = nil,
        progress: Double? = nil
    ) {
        self.id = id
        self.libraryId = libraryId
        self.articleRevisionId = articleRevisionId
        self.articleTitle = articleTitle
        self.status = status
        self.stage = stage
        self.message = message
        self.progress = progress
    }
}

public enum ArticleTaskStatus: String, Codable, Hashable, Sendable {
    case queued
    case running
    case paused
    case succeeded
    case failed
    case cancelled
}

public struct ReaderFixture: Codable, Hashable, Sendable {
    public var library: Library
    public var article: Article
    public var revision: ArticleRevision
    public var blocks: [DocumentBlock]
    public var translations: [Translation]
    public var notes: [ReaderNote]
    public var tasks: [ArticleTask]

    public init(
        library: Library,
        article: Article,
        revision: ArticleRevision,
        blocks: [DocumentBlock],
        translations: [Translation] = [],
        notes: [ReaderNote] = [],
        tasks: [ArticleTask] = []
    ) {
        self.library = library
        self.article = article
        self.revision = revision
        self.blocks = blocks
        self.translations = translations
        self.notes = notes
        self.tasks = tasks
    }
}
