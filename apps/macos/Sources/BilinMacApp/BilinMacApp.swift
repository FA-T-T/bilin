import SwiftUI
import AppKit
import BilinImportKit
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
                Button("Open Zotero Library...") {
                    Task {
                        await model.openZoteroLibraryFromPanel()
                    }
                }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
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
    @Published var schemaStatus: LibrarySchemaStatus?
    @Published var readingProgress: ArticleReadingProgress?
    @Published var zoteroItems: [ZoteroItem] = []
    @Published var zoteroCollections: [ZoteroCollection] = []
    @Published var selectedZoteroItemKey: ZoteroItem.ID?
    @Published var zoteroSchemaStatus: ZoteroSchemaStatus?
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

    var selectedZoteroItem: ZoteroItem? {
        guard let selectedZoteroItemKey else { return nil }
        return zoteroItems.first { $0.id == selectedZoteroItemKey }
    }

    var readingProgressLabel: String {
        guard let readingProgress else { return "No progress" }
        if readingProgress.totalSeconds < 60 {
            return "\(readingProgress.totalSeconds)s read"
        }
        return "\(readingProgress.totalSeconds / 60)m read"
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

    func openZoteroLibraryFromPanel() async {
        let panel = NSOpenPanel()
        panel.title = "Open Zotero Library"
        panel.message = "Choose a Zotero data directory or zotero.sqlite file."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        await openZoteroLibrary(at: url)
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
            clearLoadedState()
            loadError = String(describing: error)
        }
    }

    func openZoteroLibrary(at url: URL) async {
        do {
            let configuration: ZoteroLibraryConfiguration
            if url.lastPathComponent == "zotero.sqlite" {
                configuration = ZoteroLibraryConfiguration(databaseURL: url)
            } else {
                configuration = ZoteroLibraryConfiguration(dataDirectoryURL: url)
            }
            let reader = try ZoteroSQLiteReader(configuration: configuration)
            zoteroSchemaStatus = try await reader.schemaStatus()
            zoteroCollections = try await reader.collections()
            zoteroItems = try await reader.items(limit: 250)
            selectedZoteroItemKey = zoteroItems.first?.id
            selectedArticleId = zoteroItems.first.map { "zotero:\($0.id)" }
            activeRevisionId = nil
            blocks = []
            translations = []
            notes = []
            readingProgress = nil
            loadError = nil
        } catch {
            zoteroItems = []
            zoteroCollections = []
            selectedZoteroItemKey = nil
            zoteroSchemaStatus = nil
            loadError = String(describing: error)
        }
    }

    func selectArticle(id articleId: Article.ID?) async {
        selectedArticleId = articleId
        selectedZoteroItemKey = nil
        guard let article = articles.first(where: { $0.id == articleId }) else {
            activeRevisionId = nil
            blocks = []
            translations = []
            notes = []
            readingProgress = nil
            selectedBlockUid = nil
            return
        }
        await loadRevision(id: article.activeRevisionId)
    }

    func selectZoteroItem(id itemID: ZoteroItem.ID?) {
        selectedZoteroItemKey = itemID
        activeRevisionId = nil
        blocks = []
        translations = []
        notes = []
        readingProgress = nil
        selectedBlockUid = nil
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

    private func clearLoadedState() {
        store = nil
        libraries = []
        articles = []
        selectedLibraryId = nil
        selectedArticleId = nil
        selectedBlockUid = nil
        blocks = []
        translations = []
        notes = []
        tasks = []
        schemaStatus = nil
        readingProgress = nil
        zoteroItems = []
        zoteroCollections = []
        selectedZoteroItemKey = nil
        zoteroSchemaStatus = nil
        activeRevisionId = nil
    }

    private func load(store: any LibraryStore) async throws {
        self.store = store
        schemaStatus = try await store.schemaStatus()
        libraries = try await store.listLibraries()
        selectedLibraryId = libraries.first?.id
        articles = []
        blocks = []
        translations = []
        notes = []
        readingProgress = nil
        selectedZoteroItemKey = nil
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
            readingProgress = nil
            selectedBlockUid = nil
            return
        }
        do {
            blocks = try await store.blocks(for: revisionId)
            translations = try await store.translations(for: revisionId, targetLanguage: "zh-CN")
            readingProgress = try await store.readingProgress(for: revisionId)
            notes = try await store.notes(for: revisionId)
            selectedBlockUid = preferredInitialBlockUid()
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    private func preferredInitialBlockUid() -> String? {
        if
            let activeBlockUid = readingProgress?.activeBlockUid,
            blocks.contains(where: { $0.blockUid == activeBlockUid })
        {
            return activeBlockUid
        }
        return blocks.first(where: { $0.blockType == .paragraph })?.blockUid ?? blocks.first?.blockUid
    }
}
