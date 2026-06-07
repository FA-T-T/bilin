import Foundation
import BilinImportKit
import BilinReaderKit
import BilinStore
import BilinWorkspaceKit

@MainActor
extension ReaderWorkbenchSession {
    func loadInitialWorkbench() async {
        workspaceDefaults.detectWorkspacePaths()
        let policy = initialLaunchPolicy()
        if
            case .openConfiguredLibrary = policy,
            let url = initialBilinLibraryURL(),
            await loadBilinLibrary(
                at: url,
                persist: false,
                refreshImmediately: true,
                recoveryRecord: workspaceDefaults.workspaceConfiguration.selectedBilinLibrary
            )
        {
            await openConfiguredZoteroLibraryIfAvailable()
            return
        }
        if case .loadPrototypeFixture = policy {
            await loadPrototypeFixture()
            await openConfiguredZoteroLibraryIfAvailable()
            return
        }
        await openConfiguredZoteroLibraryIfAvailable()
        await refreshResearchWorkbench(indicatesBusy: false)
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
            await refreshResearchWorkbench(indicatesBusy: false)
        } catch {
            loadError = String(describing: error)
        }
    }

    func requestLibrarySelection(_ libraryId: Library.ID?) {
        guard libraryId != selectedLibraryId else { return }
        selectionLoadGeneration += 1
        let generation = selectionLoadGeneration
        selectedLibraryId = libraryId
        articles = []
        selectedLibraryItem = nil
        selectedLibraryItemLoadState = .idle
        clearReaderContentWithoutAdvancingGeneration()
        librarySelectionTask?.cancel()
        libraryItemSelectionTask?.cancel()
        librarySelectionTask = Task { @MainActor [weak self] in
            await self?.loadSelectedLibrary(id: libraryId, generation: generation)
        }
    }

    func requestLibraryItemSelection(_ selection: ReaderLibrarySelection?) {
        guard shouldStartLibraryItemLoad(for: selection) else { return }
        selectionLoadGeneration += 1
        let generation = selectionLoadGeneration
        selectedLibraryItem = selection
        beginLibraryItemLoad(for: selection)
        libraryItemSelectionTask?.cancel()
        libraryItemSelectionTask = Task { @MainActor [weak self] in
            await self?.loadSelectedLibraryItem(selection, generation: generation)
        }
    }

    func reloadSelectedLibraryItem() {
        guard let selection = selectedLibraryItem else { return }
        selectionLoadGeneration += 1
        let generation = selectionLoadGeneration
        selectedLibraryItem = selection
        beginLibraryItemLoad(for: selection)
        libraryItemSelectionTask?.cancel()
        libraryItemSelectionTask = Task { @MainActor [weak self] in
            await self?.loadSelectedLibraryItem(selection, generation: generation)
        }
    }

    func openLibrary(at url: URL) async {
        await loadBilinLibrary(at: url, persist: true)
    }

    func selectLibrary(id libraryId: Library.ID?) async {
        selectionLoadGeneration += 1
        let generation = selectionLoadGeneration
        selectedLibraryId = libraryId
        articles = []
        selectedLibraryItem = nil
        selectedLibraryItemLoadState = .idle
        clearReaderContentWithoutAdvancingGeneration()
        await loadSelectedLibrary(id: libraryId, generation: generation)
    }

    private func loadSelectedLibrary(id libraryId: Library.ID?, generation: Int) async {
        guard isCurrentSelectionGeneration(generation), !Task.isCancelled else { return }

        guard let libraryId, let store else {
            researchActionPlans = []
            return
        }

        do {
            let loadedArticles = try await store.articles(in: libraryId)
            guard isCurrentSelectionGeneration(generation), !Task.isCancelled else { return }
            articles = loadedArticles
            if selectedLibraryItem == nil, let firstArticle = loadedArticles.first {
                selectedLibraryItem = .article(id: firstArticle.id)
                await loadSelectedLibraryItem(.article(id: firstArticle.id), generation: generation)
            }
            loadError = nil
        } catch {
            guard isCurrentSelectionGeneration(generation), !Task.isCancelled else { return }
            loadError = String(describing: error)
        }
    }

    func selectLibraryItem(_ selection: ReaderLibrarySelection?) async {
        selectionLoadGeneration += 1
        let loadGeneration = selectionLoadGeneration
        selectedLibraryItem = selection
        beginLibraryItemLoad(for: selection)
        await loadSelectedLibraryItem(selection, generation: loadGeneration)
    }

    private func loadSelectedLibraryItem(_ selection: ReaderLibrarySelection?, generation loadGeneration: Int) async {
        guard isCurrentSelectionGeneration(loadGeneration), !Task.isCancelled else { return }
        switch selection {
        case .article(let articleId):
            await loadArticle(id: articleId, generation: loadGeneration)
        case .zoteroItem(let itemID):
            selectZoteroItem(id: itemID, generation: loadGeneration)
        case nil:
            clearReaderContent()
            researchActionPlans = []
        }
    }

    func openZoteroLibrary(at url: URL) async {
        let shouldKeepReaderSelection = selectedLibraryItem?.articleId != nil
        if !shouldKeepReaderSelection {
            selectionLoadGeneration += 1
            librarySelectionTask?.cancel()
            librarySelectionTask = nil
            libraryItemSelectionTask?.cancel()
            libraryItemSelectionTask = nil
        }
        let openingSelectionGeneration = selectionLoadGeneration
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
            workspaceDefaults.persistWorkspacePath(url: url, kind: .zoteroLibrary)
            if !shouldKeepReaderSelection, selectionLoadGeneration == openingSelectionGeneration {
                selectionLoadGeneration += 1
                let selection = zoteroItems.first.map { ReaderLibrarySelection.zoteroItem(id: $0.id) }
                discardPendingReaderTextSelection()
                selectedLibraryItem = selection
                activeRevisionId = nil
                blocks = []
                citationResolver = .empty
                translations = []
                notes = []
                readingProgress = nil
                selectedBlockUid = nil
                selectedCitationEntryId = nil
                researchActionPlans = []
                selectedLibraryItemLoadState = selection.map { .loaded($0) } ?? .idle
            }
            loadError = nil
        } catch {
            let message = String(describing: error)
            if selectedLibraryItem?.zoteroItemId != nil {
                selectionLoadGeneration += 1
                selectedLibraryItem = nil
                selectedLibraryItemLoadState = .idle
                clearReaderContent()
                researchActionPlans = []
            }
            zoteroItems = []
            zoteroCollections = []
            zoteroSchemaStatus = nil
            loadError = message
            researchWorkbenchStatus = "Zotero unavailable"
            researchWorkbenchError = message
        }
    }

    func selectArticle(id articleId: Article.ID?) async {
        await selectLibraryItem(articleId.map { .article(id: $0) })
    }

    func selectZoteroItem(id itemID: ZoteroItem.ID?) {
        let selection = itemID.map { ReaderLibrarySelection.zoteroItem(id: $0) }
        guard shouldApplyZoteroSelection(selection) else { return }
        selectionLoadGeneration += 1
        applyZoteroSelection(selection, generation: selectionLoadGeneration)
    }

    private func selectZoteroItem(id itemID: ZoteroItem.ID?, generation: Int) {
        let selection = itemID.map { ReaderLibrarySelection.zoteroItem(id: $0) }
        applyZoteroSelection(selection, generation: generation)
    }

    private func applyZoteroSelection(_ selection: ReaderLibrarySelection?, generation: Int) {
        guard isCurrentSelectionGeneration(generation) else { return }
        discardPendingReaderTextSelection()
        selectedLibraryItem = selection
        activeRevisionId = nil
        blocks = []
        citationResolver = .empty
        translations = []
        notes = []
        readingProgress = nil
        selectedBlockUid = nil
        selectedCitationEntryId = nil
        readerTextSelection = nil
        removeNonZoteroImportActionPlans()
        selectedLibraryItemLoadState = selection.map { .loaded($0) } ?? .idle
    }

    private func shouldApplyZoteroSelection(_ selection: ReaderLibrarySelection?) -> Bool {
        guard selection == selectedLibraryItem else { return true }
        guard let selection else {
            return selectedLibraryItemLoadState != .idle
                || activeRevisionId != nil
                || !blocks.isEmpty
                || selectedBlockUid != nil
                || selectedCitationEntryId != nil
                || readerTextSelection != nil
        }
        guard case .loaded(let loadedSelection) = selectedLibraryItemLoadState,
              loadedSelection == selection
        else {
            return true
        }
        return activeRevisionId != nil
            || !blocks.isEmpty
            || selectedBlockUid != nil
            || selectedCitationEntryId != nil
            || readerTextSelection != nil
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

    private func clearLoadedState(preservingResearchAPIState: Bool = false) {
        let preservedResearchAPIStatus = researchAPIStatus
        let preservedResearchAPIError = researchAPIError
        let preservedResearchAPIHealth = researchAPIHealth
        let preservedResearchAPIBusy = researchAPIBusy
        selectionLoadGeneration += 1
        discardPendingReaderTextSelection()
        librarySelectionTask?.cancel()
        librarySelectionTask = nil
        libraryItemSelectionTask?.cancel()
        libraryItemSelectionTask = nil
        researchWorkbenchRefreshTask?.cancel()
        researchWorkbenchRefreshTask = nil
        store = nil
        libraries = []
        articles = []
        selectedLibraryId = nil
        selectedLibraryItem = nil
        selectedLibraryItemLoadState = .idle
        selectedBlockUid = nil
        selectedCitationEntryId = nil
        blocks = []
        citationResolver = .empty
        translations = []
        notes = []
        tasks = []
        schemaStatus = nil
        readingProgress = nil
        researchSkills = []
        researchActionPlans = []
        configuredBilinLibraryRecovery = nil
        if preservingResearchAPIState {
            researchAPIStatus = preservedResearchAPIStatus
            researchAPIError = preservedResearchAPIError
            researchAPIHealth = preservedResearchAPIHealth
        } else {
            researchAPIStatus = "Not connected"
            researchAPIError = nil
            researchAPIHealth = nil
        }
        researchWorkbenchStatus = "No library"
        researchWorkbenchError = nil
        researchAPIBusy = preservingResearchAPIState ? preservedResearchAPIBusy : false
        zoteroItems = []
        zoteroCollections = []
        zoteroSchemaStatus = nil
        activeRevisionId = nil
        readerTextSelection = nil
    }

    private func clearReaderContent() {
        selectionLoadGeneration += 1
        clearReaderContentWithoutAdvancingGeneration()
    }

    private func clearReaderContentWithoutAdvancingGeneration() {
        discardPendingReaderTextSelection()
        libraryItemSelectionTask?.cancel()
        libraryItemSelectionTask = nil
        researchWorkbenchRefreshTask?.cancel()
        researchWorkbenchRefreshTask = nil
        activeRevisionId = nil
        blocks = []
        citationResolver = .empty
        translations = []
        notes = []
        readingProgress = nil
        selectedBlockUid = nil
        selectedCitationEntryId = nil
        readerTextSelection = nil
        selectedLibraryItemLoadState = .idle
    }

    private func clearReaderDocumentForPendingLibraryItemLoad(for selection: ReaderLibrarySelection?) {
        discardPendingReaderTextSelection()
        activeRevisionId = nil
        blocks = []
        citationResolver = .empty
        translations = []
        notes = []
        readingProgress = nil
        selectedBlockUid = nil
        selectedCitationEntryId = nil
        readerTextSelection = nil
        if selection?.zoteroItemId != nil {
            removeNonZoteroImportActionPlans()
        } else {
            researchActionPlans = []
        }
        loadError = nil
    }

    private func beginLibraryItemLoad(for selection: ReaderLibrarySelection?) {
        guard let selection else {
            selectedLibraryItemLoadState = .idle
            clearReaderDocumentForPendingLibraryItemLoad(for: nil)
            return
        }
        selectedLibraryItemLoadState = .loading(selection)
        clearReaderDocumentForPendingLibraryItemLoad(for: selection)
    }

    private func shouldStartLibraryItemLoad(for selection: ReaderLibrarySelection?) -> Bool {
        guard selection == selectedLibraryItem else { return true }
        guard let selection else { return false }
        if case .failed(let failedSelection, _) = selectedLibraryItemLoadState {
            return failedSelection == selection
        }
        if shouldReloadSelectedArticle(selection) {
            return true
        }
        return false
    }

    private func shouldReloadSelectedArticle(_ selection: ReaderLibrarySelection) -> Bool {
        guard let articleId = selection.articleId else { return false }
        guard selectedArticle?.id == articleId else { return false }
        guard case .loaded(let loadedSelection) = selectedLibraryItemLoadState,
              loadedSelection == selection
        else {
            return false
        }
        return activeRevisionId == nil || blocks.isEmpty
    }

    private func removeNonZoteroImportActionPlans() {
        researchActionPlans.removeAll { !$0.isZoteroImportActionPlan }
    }

    private func initialBilinLibraryURL() -> URL? {
        if
            let path = launchEnvironment["BILIN_LIBRARY_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        {
            return URL(fileURLWithPath: path)
        }
        guard let record = workspaceDefaults.workspaceConfiguration.selectedBilinLibrary else {
            return nil
        }
        return URL(fileURLWithPath: record.path, isDirectory: true)
    }

    private func initialZoteroLibraryURL() -> URL? {
        if
            let path = launchEnvironment["BILIN_ZOTERO_LIBRARY_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        {
            return URL(fileURLWithPath: path)
        }
        guard let record = workspaceDefaults.workspaceConfiguration.selectedZoteroLibrary else {
            return nil
        }
        return URL(fileURLWithPath: record.path, isDirectory: true)
    }

    private func openConfiguredZoteroLibraryIfAvailable() async {
        guard let url = initialZoteroLibraryURL() else { return }
        await openZoteroLibrary(at: url)
    }

    func initialLaunchPolicy() -> ReaderWorkbenchLaunchPolicy {
        if initialBilinLibraryURL() != nil {
            return .openConfiguredLibrary
        }
        return loadPrototypeFixtureWhenUnconfigured ? .loadPrototypeFixture : .openConfiguredLibrary
    }

    static func prototypeFixtureEnabled(in environment: [String: String]) -> Bool {
        let value = environment["BILIN_MAC_LOAD_PROTOTYPE_FIXTURE"]
            ?? environment["BILIN_LOAD_PROTOTYPE_FIXTURE"]
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    @discardableResult
    private func loadBilinLibrary(
        at url: URL,
        persist: Bool,
        refreshImmediately: Bool = false,
        recoveryRecord: WorkspacePathRecord? = nil
    ) async -> Bool {
        do {
            let store: SQLiteLibraryStore
            if url.lastPathComponent == "library.sqlite" {
                store = try SQLiteLibraryStore(databaseURL: url)
            } else {
                store = try SQLiteLibraryStore(libraryDirectoryURL: url)
            }
            try await load(store: store)
            tasks = []
            if persist {
                workspaceDefaults.persistWorkspacePath(url: url, kind: .bilinLibrary)
            }
            configuredBilinLibraryRecovery = nil
            if refreshImmediately {
                await refreshResearchWorkbench(indicatesBusy: false)
            } else {
                requestResearchWorkbenchRefresh()
            }
            return true
        } catch {
            clearLoadedState(preservingResearchAPIState: true)
            let message = Self.libraryLoadErrorMessage(error)
            if let recoveryRecord {
                configuredBilinLibraryRecovery = ConfiguredBilinLibraryRecovery(
                    name: recoveryRecord.name,
                    path: recoveryRecord.path,
                    message: message
                )
                researchWorkbenchStatus = "Library needs attention"
                researchWorkbenchError = message
            }
            loadError = message
            return false
        }
    }

    private static func libraryLoadErrorMessage(_ error: Error) -> String {
        switch error {
        case SQLiteLibraryStoreError.missingDatabase(let path):
            return "The configured Bilin library database could not be found at \(path)."
        case SQLiteLibraryStoreError.invalidLibrary(let path):
            return "The configured Bilin library at \(path) is not a readable Bilin library."
        case SQLiteLibraryStoreError.unsupportedSchema(let missingRequiredVersions, let unknownVersions):
            let missing = missingRequiredVersions.isEmpty ? nil : "missing \(missingRequiredVersions.joined(separator: ", "))"
            let unknown = unknownVersions.isEmpty ? nil : "unknown \(unknownVersions.joined(separator: ", "))"
            return "The configured Bilin library schema is unsupported: \([missing, unknown].compactMap { $0 }.joined(separator: "; "))."
        default:
            return "The configured Bilin library could not be opened: \(error.localizedDescription)"
        }
    }

    private func load(store: any LibraryStore) async throws {
        self.store = store
        schemaStatus = try await store.schemaStatus()
        libraries = try await store.listLibraries()
        articles = []
        clearReaderContent()
        selectedLibraryItem = nil

        guard let libraryId = libraries.first?.id else {
            selectedLibraryId = nil
            loadError = nil
            return
        }

        await selectLibrary(id: libraryId)
        loadError = nil
    }

    private func loadArticle(id articleId: Article.ID, generation: Int) async {
        guard isCurrentSelectionGeneration(generation) else { return }
        let selection = ReaderLibrarySelection.article(id: articleId)
        guard let article = articles.first(where: { $0.id == articleId }) else {
            clearReaderDocumentForPendingLibraryItemLoad(for: selection)
            selectedLibraryItemLoadState = .failed(selection, message: "The selected paper is no longer available in this library.")
            researchActionPlans = []
            return
        }
        await loadRevision(id: article.activeRevisionId, generation: generation, selection: selection)
    }

    private func loadRevision(
        id revisionId: ArticleRevision.ID?,
        generation: Int? = nil,
        selection: ReaderLibrarySelection? = nil
    ) async {
        guard isCurrentSelectionGeneration(generation) else { return }
        activeRevisionId = revisionId
        guard let revisionId, let store else {
            blocks = []
            citationResolver = .empty
            translations = []
            notes = []
            readingProgress = nil
            selectedBlockUid = nil
            selectedCitationEntryId = nil
            if let selection {
                selectedLibraryItemLoadState = .failed(selection, message: "The selected paper does not have an active parsed revision.")
            }
            return
        }
        do {
            let loadedBlocks = try await store.blocks(for: revisionId)
            let loadedTranslations = try await store.translations(for: revisionId, targetLanguage: "zh-CN")
            let loadedReadingProgress = try await store.readingProgress(for: revisionId)
            let loadedNotes = try await store.notes(for: revisionId)
            guard isCurrentSelectionGeneration(generation) else { return }
            blocks = loadedBlocks
            citationResolver = ReaderCitationResolver(blocks: loadedBlocks)
            translations = loadedTranslations
            readingProgress = loadedReadingProgress
            notes = loadedNotes
            selectedBlockUid = preferredInitialBlockUid()
            selectedCitationEntryId = nil
            requestReaderBlockScroll(to: selectedBlockUid)
            loadError = nil
            if let selection {
                selectedLibraryItemLoadState = .loaded(selection)
            }
            requestResearchWorkbenchRefresh()
        } catch {
            guard isCurrentSelectionGeneration(generation) else { return }
            let message = String(describing: error)
            loadError = message
            if let selection {
                selectedLibraryItemLoadState = .failed(selection, message: message)
            }
        }
    }

    func isCurrentSelectionGeneration(_ generation: Int?) -> Bool {
        guard let generation else { return true }
        return generation == selectionLoadGeneration
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
