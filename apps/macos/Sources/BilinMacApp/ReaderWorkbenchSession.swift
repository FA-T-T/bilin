import SwiftUI
import BilinImportKit
import BilinReaderKit
import BilinStore
import BilinWorkspaceKit

typealias ReaderTranslation = BilinReaderKit.Translation

struct ReaderTextSelection: Hashable, Sendable {
    var blockUid: String
    var text: String
    var textHash: String
}

struct PendingReaderTextSelection: Hashable, Sendable {
    var selection: ReaderTextSelection?
    var clearingBlockUid: String
}

struct ReaderBlockScrollRequest: Hashable, Sendable {
    var id: UUID
    var blockUid: String

    init(blockUid: String, id: UUID = UUID()) {
        self.id = id
        self.blockUid = blockUid
    }
}

enum ReaderWorkbenchLaunchPolicy: Equatable, Sendable {
    case openConfiguredLibrary
    case loadPrototypeFixture
}

enum ReaderLibraryItemLoadState: Equatable, Sendable {
    case idle
    case loading(ReaderLibrarySelection)
    case loaded(ReaderLibrarySelection)
    case failed(ReaderLibrarySelection, message: String)
}

struct ConfiguredBilinLibraryRecovery: Hashable, Sendable {
    var name: String
    var path: String
    var message: String
}

@MainActor
final class ReaderWorkbenchSession: ObservableObject {
    let sessionID = UUID()
    @Published var libraries: [Library] = []
    @Published var articles: [Article] = []
    @Published var selectedLibraryId: Library.ID?
    @Published var selectedLibraryItem: ReaderLibrarySelection?
    @Published var selectedBlockUid: String?
    @Published var selectedCitationEntryId: String?
    @Published var blocks: [DocumentBlock] = []
    @Published var citationResolver = ReaderCitationResolver.empty
    @Published var translations: [ReaderTranslation] = []
    @Published var notes: [ReaderNote] = []
    @Published var tasks: [ArticleTask] = []
    @Published var schemaStatus: LibrarySchemaStatus?
    @Published var readingProgress: ArticleReadingProgress?
    @Published var zoteroItems: [ZoteroItem] = []
    @Published var zoteroCollections: [ZoteroCollection] = []
    @Published var zoteroSchemaStatus: ZoteroSchemaStatus?
    @Published var equationEditorPresented = false
    @Published var loadError: String?
    @Published var configuredBilinLibraryRecovery: ConfiguredBilinLibraryRecovery?
    @Published var researchSkills: [ResearchSkill] = []
    @Published var researchPlans: [ResearchPlan] = []
    @Published var researchActionPlans: [AgentActionPlan] = []
    @Published var researchAPIStatus = "Not connected"
    @Published var researchAPIError: String?
    @Published var researchAPIHealth: BilinAPIHealth?
    @Published var researchWorkbenchStatus = "No library"
    @Published var researchWorkbenchError: String?
    @Published var researchAPIBusy = false
    @Published var readerTextSelection: ReaderTextSelection?
    @Published var readerBlockScrollRequest: ReaderBlockScrollRequest?
    @Published var selectedLibraryItemLoadState: ReaderLibraryItemLoadState = .idle
    @Published var selectedWritingTargetSection: String?

    var store: (any LibraryStore)?
    var activeRevisionId: ArticleRevision.ID?
    var pendingReaderTextSelection: PendingReaderTextSelection?
    var readerTextSelectionCommitTask: Task<Void, Never>?
    var librarySelectionTask: Task<Void, Never>?
    var libraryItemSelectionTask: Task<Void, Never>?
    var researchWorkbenchRefreshTask: Task<Void, Never>?
    var researchWorkbenchRefreshGeneration = 0
    var selectionLoadGeneration = 0
    let researchAPIClient: BilinResearchAPIClient
    let actionPlanCoordinator: DefaultResearchActionPlanCoordinator
    let workspaceDefaults: WorkspaceDefaultsModel
    let launchEnvironment: [String: String]
    let loadPrototypeFixtureWhenUnconfigured: Bool

    init(
        researchAPIClient: BilinResearchAPIClient? = nil,
        workspaceDefaults: WorkspaceDefaultsModel? = nil,
        workspaceConfigurationCoordinator: WorkspaceConfigurationCoordinator = .defaultCoordinator(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loadPrototypeFixtureWhenUnconfigured: Bool? = nil
    ) {
        self.launchEnvironment = environment
        self.loadPrototypeFixtureWhenUnconfigured = loadPrototypeFixtureWhenUnconfigured
            ?? Self.prototypeFixtureEnabled(in: environment)
        let effectiveResearchAPIClient = researchAPIClient ?? .fromEnvironment(environment: environment)
        self.researchAPIClient = effectiveResearchAPIClient
        self.actionPlanCoordinator = DefaultResearchActionPlanCoordinator(client: effectiveResearchAPIClient)
        self.workspaceDefaults = workspaceDefaults
            ?? WorkspaceDefaultsModel(workspaceConfigurationCoordinator: workspaceConfigurationCoordinator)
    }

    var selectedArticle: Article? {
        guard let articleId = selectedLibraryItem?.articleId else { return nil }
        return articles.first { $0.id == articleId }
    }

    var isLoadingSelectedLibraryItem: Bool {
        guard case .loading(let selection) = selectedLibraryItemLoadState else { return false }
        return selection == selectedLibraryItem
    }

    var canReloadSelectedLibraryItem: Bool {
        selectedLibraryItem != nil && !isLoadingSelectedLibraryItem
    }

    var selectedLibraryItemLoadError: String? {
        guard case .failed(let selection, let message) = selectedLibraryItemLoadState else { return nil }
        return selection == selectedLibraryItem ? message : nil
    }

    var selectedLibrary: Library? {
        libraries.first { $0.id == selectedLibraryId }
    }

    var selectedBlock: DocumentBlock? {
        blocks.first { $0.blockUid == selectedBlockUid }
    }

    var selectedBlockTranslation: ReaderTranslation? {
        guard let selectedBlock else { return nil }
        return translations.first { $0.blockId == selectedBlock.id && $0.isDefault }
            ?? translations.first { $0.blockId == selectedBlock.id }
    }

    var selectedEquationLatex: String? {
        guard let selectedBlock, selectedBlock.blockType == .equation else { return nil }
        return selectedBlock.sourceLatex ?? selectedBlock.sourceMarkdown
    }

    var selectedReaderText: String? {
        selectedReaderTextSelection?.text
    }

    var selectedReaderTextHash: String? {
        selectedReaderTextSelection?.textHash
    }

    var selectedReaderTextSelection: ReaderTextSelection? {
        guard let selectedBlock else { return nil }
        return readerTextSelection(for: selectedBlock.blockUid)
    }

    func readerTextSelection(for blockUid: String) -> ReaderTextSelection? {
        if let pendingReaderTextSelection {
            if let pendingSelection = pendingReaderTextSelection.selection,
               pendingSelection.blockUid == blockUid {
                return pendingSelection
            }
            if pendingReaderTextSelection.clearingBlockUid == blockUid {
                return nil
            }
        }
        guard readerTextSelection?.blockUid == blockUid else {
            return nil
        }
        return readerTextSelection
    }

    var isResearchAPIReady: Bool {
        researchAPIHealth != nil && researchAPIError == nil
    }

    var selectedZoteroItem: ZoteroItem? {
        guard let zoteroItemId = selectedLibraryItem?.zoteroItemId else { return nil }
        return zoteroItems.first { $0.id == zoteroItemId }
    }

    var selectedObsidianVaultIsAvailable: Bool {
        workspaceDefaults.workspaceConfiguration.selectedObsidianVault?.status == .available
    }

    var selectedWritingProjectRootIsAvailable: Bool {
        workspaceDefaults.workspaceConfiguration.writingProjectRoots.first?.status == .available
    }

    var canPrepareSelectedBlockNoteActionPlan: Bool {
        selectedLibraryId != nil
            && selectedBlock != nil
            && selectedObsidianVaultIsAvailable
            && isResearchAPIReady
            && !researchAPIBusy
    }

    var canPrepareSelectedBlockWritingActionPlan: Bool {
        selectedLibraryId != nil
            && selectedBlock != nil
            && selectedWritingProjectRootIsAvailable
            && workspaceDefaults.writingProjectLocation.mainFilePath != nil
            && isResearchAPIReady
            && !researchAPIBusy
    }

    var canPrepareSelectedArticleReadingOutlineActionPlan: Bool {
        selectedLibraryId != nil
            && selectedArticle != nil
            && isResearchAPIReady
            && !researchAPIBusy
            && researchSkills.contains { skill in
                skill.slug == "paper-outline"
                    && skill.supportsPaperReading
                    && skill.isEnabled
            }
    }

    var readingProgressLabel: String {
        guard let readingProgress else { return "No progress" }
        if readingProgress.totalSeconds < 60 {
            return "\(readingProgress.totalSeconds)s read"
        }
        return "\(readingProgress.totalSeconds / 60)m read"
    }

    func reportUnavailableFeature(_ message: String) {
        researchWorkbenchStatus = "Not implemented"
        researchWorkbenchError = message
    }

    func updateReaderTextSelection(blockUid: String, selectedText: String?) {
        if selectedBlockUid != blockUid {
            selectedBlockUid = blockUid
        }
        selectedCitationEntryId = nil

        let nextSelection = selectedText.flatMap { selectedText -> ReaderTextSelection? in
            guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return ReaderTextSelection(
                blockUid: blockUid,
                text: selectedText,
                textHash: ReaderSelectionSnapshot.sha256TextHash(for: selectedText)
            )
        }
        readerTextSelectionCommitTask?.cancel()
        pendingReaderTextSelection = PendingReaderTextSelection(
            selection: nextSelection,
            clearingBlockUid: blockUid
        )
        readerTextSelectionCommitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 90_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.flushPendingReaderTextSelection()
        }
    }

    func selectReaderBlock(_ blockUid: String) {
        discardPendingReaderTextSelection()
        selectedBlockUid = blockUid
        selectedCitationEntryId = nil
    }

    func requestReaderBlockScroll(to blockUid: String?) {
        guard
            let blockUid,
            blocks.contains(where: { $0.blockUid == blockUid })
        else {
            return
        }
        readerBlockScrollRequest = ReaderBlockScrollRequest(blockUid: blockUid)
    }

    @discardableResult
    func selectCitationEntry(_ entry: ReaderCitationEntry) -> String? {
        discardPendingReaderTextSelection()
        guard entry.hasBibliographyEntry else {
            researchWorkbenchStatus = "Citation target missing"
            researchWorkbenchError = "The bibliography target \(entry.displayLabel) is not available in this loaded document."
            return nil
        }
        guard blocks.contains(where: { $0.blockUid == entry.sourceBlockUid }) else {
            researchWorkbenchStatus = "Citation target missing"
            researchWorkbenchError = "The bibliography target \(entry.displayLabel) is not available in this loaded document."
            return nil
        }
        selectedBlockUid = entry.sourceBlockUid
        selectedCitationEntryId = entry.id
        readerTextSelection = nil
        clearCitationNavigationErrorIfNeeded()
        requestReaderBlockScroll(to: entry.sourceBlockUid)
        return entry.sourceBlockUid
    }

    func flushPendingReaderTextSelection() {
        readerTextSelectionCommitTask?.cancel()
        readerTextSelectionCommitTask = nil
        guard let pendingReaderTextSelection else { return }
        self.pendingReaderTextSelection = nil
        commitReaderTextSelection(
            pendingReaderTextSelection.selection,
            clearingBlockUid: pendingReaderTextSelection.clearingBlockUid
        )
    }

    func discardPendingReaderTextSelection() {
        readerTextSelectionCommitTask?.cancel()
        readerTextSelectionCommitTask = nil
        pendingReaderTextSelection = nil
    }

    private func clearCitationNavigationErrorIfNeeded() {
        guard researchWorkbenchStatus == "Citation target missing" else {
            return
        }
        researchWorkbenchStatus = "Citation selected"
        researchWorkbenchError = nil
    }

    private func commitReaderTextSelection(_ selection: ReaderTextSelection?, clearingBlockUid: String) {
        guard let selection else {
            if readerTextSelection?.blockUid == clearingBlockUid {
                readerTextSelection = nil
            }
            return
        }
        guard readerTextSelection != selection else {
            return
        }
        readerTextSelection = selection
    }

}
