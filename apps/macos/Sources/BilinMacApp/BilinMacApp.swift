import SwiftUI
import BilinReaderKit
import BilinStore

@main
struct BilinMacApp: App {
    @StateObject private var model = ReaderWorkbenchModel()

    var body: some Scene {
        WindowGroup {
            WorkbenchView()
                .environmentObject(model)
                .task {
                    await model.loadPrototypeFixture()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Library...") {}
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Import Paper...") {}
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandMenu("Reader") {
                Button("Translate Selection") {}
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Export Notes") {}
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class ReaderWorkbenchModel: ObservableObject {
    @Published var libraries: [Library] = []
    @Published var articles: [Article] = []
    @Published var selectedLibraryId: Library.ID?
    @Published var selectedArticleId: Article.ID?
    @Published var selectedBlockUid: String?
    @Published var blocks: [DocumentBlock] = []
    @Published var notes: [ReaderNote] = []
    @Published var tasks: [ArticleTask] = []
    @Published var loadError: String?

    private var store: (any LibraryStore)?
    private var activeRevisionId: ArticleRevision.ID?

    var selectedArticle: Article? {
        articles.first { $0.id == selectedArticleId }
    }

    var selectedBlock: DocumentBlock? {
        blocks.first { $0.blockUid == selectedBlockUid }
    }

    func loadPrototypeFixture() async {
        do {
            let fixture = try ReaderFixtureLoader().loadFixture(
                named: "prototype-article",
                bundle: .module
            )
            let store = FixtureLibraryStore(fixture: fixture)
            self.store = store
            libraries = try await store.listLibraries()
            selectedLibraryId = libraries.first?.id
            if let libraryId = selectedLibraryId {
                articles = try await store.articles(in: libraryId)
            }
            selectedArticleId = articles.first?.id
            activeRevisionId = articles.first?.activeRevisionId
            if let revisionId = activeRevisionId {
                blocks = try await store.blocks(for: revisionId)
                notes = try await store.notes(for: revisionId)
            }
            tasks = fixture.tasks
            selectedBlockUid = blocks.first(where: { $0.blockType == .paragraph })?.blockUid
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    func saveDraftNote(title: String, markdown: String) async {
        guard let revisionId = activeRevisionId, let store else { return }
        let now = Date()
        let note = ReaderNote(
            id: UUID().uuidString,
            articleRevisionId: revisionId,
            blockUid: selectedBlockUid,
            title: title,
            markdown: markdown,
            createdAt: now,
            updatedAt: now
        )
        do {
            try await store.saveNote(note)
            notes = try await store.notes(for: revisionId)
        } catch {
            loadError = String(describing: error)
        }
    }
}
