import Foundation
import BilinReaderKit

public struct LibrarySchemaStatus: Codable, Hashable, Sendable {
    public var appliedVersions: [String]
    public var missingRequiredVersions: [String]
    public var unknownVersions: [String]

    public var isReadable: Bool {
        missingRequiredVersions.isEmpty
    }

    public var isWritable: Bool {
        isReadable && unknownVersions.isEmpty
    }

    public init(
        appliedVersions: [String],
        missingRequiredVersions: [String],
        unknownVersions: [String] = []
    ) {
        self.appliedVersions = appliedVersions
        self.missingRequiredVersions = missingRequiredVersions
        self.unknownVersions = unknownVersions
    }

    public static let fixture = LibrarySchemaStatus(
        appliedVersions: ["fixture"],
        missingRequiredVersions: [],
        unknownVersions: []
    )
}

public protocol LibraryStore: Sendable {
    func schemaStatus() async throws -> LibrarySchemaStatus
    func listLibraries() async throws -> [Library]
    func articles(in libraryId: Library.ID) async throws -> [Article]
    func revision(id: ArticleRevision.ID) async throws -> ArticleRevision?
    func blocks(for revisionId: ArticleRevision.ID) async throws -> [DocumentBlock]
    func translations(for revisionId: ArticleRevision.ID, targetLanguage: String) async throws -> [Translation]
    func readingProgress(for revisionId: ArticleRevision.ID) async throws -> ArticleReadingProgress
    func notes(for revisionId: ArticleRevision.ID) async throws -> [ReaderNote]
    func saveNote(_ note: ReaderNote) async throws
}

public actor FixtureLibraryStore: LibraryStore {
    private var fixture: ReaderFixture

    public init(fixture: ReaderFixture) {
        self.fixture = fixture
    }

    public func schemaStatus() async throws -> LibrarySchemaStatus {
        .fixture
    }

    public func listLibraries() async throws -> [Library] {
        [fixture.library]
    }

    public func articles(in libraryId: Library.ID) async throws -> [Article] {
        fixture.library.id == libraryId ? [fixture.article] : []
    }

    public func revision(id: ArticleRevision.ID) async throws -> ArticleRevision? {
        fixture.revision.id == id ? fixture.revision : nil
    }

    public func blocks(for revisionId: ArticleRevision.ID) async throws -> [DocumentBlock] {
        fixture.revision.id == revisionId ? fixture.blocks : []
    }

    public func translations(for revisionId: ArticleRevision.ID, targetLanguage: String) async throws -> [Translation] {
        guard fixture.revision.id == revisionId else { return [] }
        let blockIds = Set(fixture.blocks.map(\.id))
        return fixture.translations.filter {
            blockIds.contains($0.blockId) && $0.targetLanguage == targetLanguage
        }
    }

    public func readingProgress(for revisionId: ArticleRevision.ID) async throws -> ArticleReadingProgress {
        guard fixture.revision.id == revisionId else {
            return ArticleReadingProgress.empty(articleRevisionId: revisionId, blockUIDs: [])
        }
        return fixture.readingProgress
            ?? ArticleReadingProgress.empty(articleRevisionId: revisionId, blockUIDs: fixture.blocks.map(\.blockUid))
    }

    public func notes(for revisionId: ArticleRevision.ID) async throws -> [ReaderNote] {
        fixture.revision.id == revisionId ? fixture.notes : []
    }

    public func saveNote(_ note: ReaderNote) async throws {
        if let index = fixture.notes.firstIndex(where: { $0.id == note.id }) {
            fixture.notes[index] = note
        } else {
            fixture.notes.append(note)
        }
    }
}
