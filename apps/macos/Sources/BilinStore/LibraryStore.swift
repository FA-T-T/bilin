import Foundation
import BilinReaderKit

public protocol LibraryStore: Sendable {
    func listLibraries() async throws -> [Library]
    func articles(in libraryId: Library.ID) async throws -> [Article]
    func revision(id: ArticleRevision.ID) async throws -> ArticleRevision?
    func blocks(for revisionId: ArticleRevision.ID) async throws -> [DocumentBlock]
    func notes(for revisionId: ArticleRevision.ID) async throws -> [ReaderNote]
    func saveNote(_ note: ReaderNote) async throws
}

public actor FixtureLibraryStore: LibraryStore {
    private var fixture: ReaderFixture

    public init(fixture: ReaderFixture) {
        self.fixture = fixture
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
