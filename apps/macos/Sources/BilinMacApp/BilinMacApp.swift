import SwiftUI
import AppKit
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
                Button("Open Library...") {
                    Task {
                        await model.openLibraryFromPanel()
                    }
                }
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
    @Published var translations: [Translation] = []
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

    var selectedBlockTranslation: Translation? {
        guard let selectedBlock else { return nil }
        return translations.first { $0.blockId == selectedBlock.id && $0.isDefault }
            ?? translations.first { $0.blockId == selectedBlock.id }
    }

    func loadPrototypeFixture() async {
        do {
            let fixture = try ReaderFixtureLoader().loadFixture(
                named: "prototype-article",
                bundle: .module
            )
            let store = FixtureLibraryStore(fixture: fixture)
            try await load(store: store)
            tasks = fixture.tasks
        } catch {
            loadError = String(describing: error)
        }
    }

    func openLibraryFromPanel() async {
        let panel = NSOpenPanel()
        panel.title = "Open Bilin Library"
        panel.message = "Choose a Bilin library folder or its library.sqlite file."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        await openLibrary(at: url)
    }

    func openLibrary(at url: URL) async {
        do {
            let store: SQLiteLibraryStore
            if url.lastPathComponent == "library.sqlite" {
                store = try SQLiteLibraryStore(databaseURL: url)
            } else {
                store = try SQLiteLibraryStore(libraryDirectoryURL: url)
            }
            try await load(store: store)
            tasks = []
        } catch {
            loadError = String(describing: error)
        }
    }

    func selectArticle(id articleId: Article.ID?) async {
        selectedArticleId = articleId
        guard let article = articles.first(where: { $0.id == articleId }) else {
            activeRevisionId = nil
            blocks = []
            translations = []
            notes = []
            selectedBlockUid = nil
            return
        }
        await loadRevision(id: article.activeRevisionId)
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

    private func load(store: any LibraryStore) async throws {
        self.store = store
        libraries = try await store.listLibraries()
        selectedLibraryId = libraries.first?.id
        articles = []
        blocks = []
        translations = []
        notes = []
        selectedArticleId = nil
        selectedBlockUid = nil

        guard let libraryId = selectedLibraryId else {
            activeRevisionId = nil
            loadError = nil
            return
        }

        articles = try await store.articles(in: libraryId)
        selectedArticleId = articles.first?.id
        await loadRevision(id: articles.first?.activeRevisionId)
        loadError = nil
    }

    private func loadRevision(id revisionId: ArticleRevision.ID?) async {
        activeRevisionId = revisionId
        guard let revisionId, let store else {
            blocks = []
            translations = []
            notes = []
            selectedBlockUid = nil
            return
        }
        do {
            blocks = try await store.blocks(for: revisionId)
            translations = try await store.translations(for: revisionId, targetLanguage: "zh-CN")
            notes = try await store.notes(for: revisionId)
            selectedBlockUid = blocks.first(where: { $0.blockType == .paragraph })?.blockUid ?? blocks.first?.blockUid
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }
}
