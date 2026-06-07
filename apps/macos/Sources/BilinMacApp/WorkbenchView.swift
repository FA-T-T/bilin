import SwiftUI
import AppKit
import BilinImportKit
import BilinReaderKit
import BilinRenderKit
import BilinWorkspaceKit

struct WorkbenchView: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            ArticleListPane()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            ReaderDetailPane()
        }
        .frame(minWidth: 1080, minHeight: 720)
        .sheet(isPresented: $session.equationEditorPresented) {
            EquationEditorView(initialLatex: session.selectedEquationLatex)
        }
    }
}

private struct LibrarySidebar: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession

    var body: some View {
        List(selection: librarySelection) {
            Section("Libraries") {
                ForEach(session.libraries) { library in
                    Label(library.name, systemImage: "books.vertical")
                        .tag(Optional(library.id))
                }
            }
            Section("Local State") {
                Label("\(session.tasks.count) tasks", systemImage: "bolt.horizontal")
                Label("\(session.notes.count) notes", systemImage: "note.text")
                Label(session.readingProgressLabel, systemImage: "clock")
                Label("\(session.zoteroItems.count) Zotero items", systemImage: "tray.full")
                if let schemaStatus = session.schemaStatus {
                    Label(schemaStatus.isWritable ? "schema current" : "schema read-only", systemImage: "checkmark.seal")
                }
                if let zoteroSchemaStatus = session.zoteroSchemaStatus {
                    Label(zoteroSchemaStatus.isReadable ? "Zotero readable" : "Zotero unsupported", systemImage: "externaldrive")
                }
            }
        }
        .navigationTitle("Bilin")
    }

    private var librarySelection: Binding<Library.ID?> {
        Binding(
            get: { session.selectedLibraryId },
            set: { libraryId in
                session.requestLibrarySelection(libraryId)
            }
        )
    }
}

private struct ArticleListPane: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession

    var body: some View {
        Group {
            if session.libraries.isEmpty && session.zoteroItems.isEmpty {
                LibraryOpeningState()
            } else {
                List(selection: libraryItemSelection) {
                    if let recovery = session.configuredBilinLibraryRecovery {
                        Section("Bilin Library") {
                            ConfiguredBilinLibraryRecoveryRow(recovery: recovery)
                        }
                    }
                    Section("Papers") {
                        if session.articles.isEmpty {
                            EmptyListHintRow(
                                title: "No papers loaded",
                                detail: "Open a Bilin library or import a paper to begin reading."
                            )
                        } else {
                            ForEach(session.articles) { article in
                                let selection = ReaderLibrarySelection.article(id: article.id)
                                ArticleListRow(
                                    title: article.title,
                                    subtitle: "\(article.source) \(article.externalId)",
                                    isSelected: session.selectedLibraryItem == selection,
                                    isLoading: rowIsLoading(selection)
                                )
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        session.requestLibraryItemSelection(selection)
                                    }
                                )
                                .accessibilityAction {
                                    session.requestLibraryItemSelection(selection)
                                }
                                .tag(Optional(selection))
                                .listRowBackground(
                                    rowBackground(isSelected: session.selectedLibraryItem == selection)
                                )
                            }
                        }
                    }
                    if !session.zoteroItems.isEmpty {
                        Section("Zotero Metadata") {
                            ForEach(session.zoteroItems) { item in
                                let selection = ReaderLibrarySelection.zoteroItem(id: item.id)
                                ZoteroItemRow(
                                    item: item,
                                    isSelected: session.selectedLibraryItem == selection,
                                    isLoading: rowIsLoading(selection)
                                )
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        session.requestLibraryItemSelection(selection)
                                    }
                                )
                                .accessibilityAction {
                                    session.requestLibraryItemSelection(selection)
                                }
                                .tag(Optional(selection))
                                .listRowBackground(
                                    rowBackground(isSelected: session.selectedLibraryItem == selection)
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Library")
    }

    private func rowBackground(isSelected: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.12) : Color.clear
    }

    private func rowIsLoading(_ selection: ReaderLibrarySelection) -> Bool {
        guard case .loading(let loadingSelection) = session.selectedLibraryItemLoadState else {
            return false
        }
        return loadingSelection == selection
    }

    private var libraryItemSelection: Binding<ReaderLibrarySelection?> {
        Binding(
            get: { session.selectedLibraryItem },
            set: { selection in
                session.requestLibraryItemSelection(selection)
            }
        )
    }
}

private struct LibraryOpeningState: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession

    var body: some View {
        ContentUnavailableView {
            Label("Open a Research Library", systemImage: "books.vertical")
        } description: {
            VStack(spacing: 8) {
                Text("Choose a Bilin library or Zotero data directory to start from a real paper list.")
                if !detectedStartupLocations.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(detectedStartupLocations) { record in
                            VStack(spacing: 4) {
                                Text(detectedLocationMessage(for: record))
                                    .foregroundStyle(.secondary)
                                Text(record.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                if let recovery = session.configuredBilinLibraryRecovery {
                    ConfiguredBilinLibraryRecoverySummary(recovery: recovery)
                }
            }
        } actions: {
            ViewThatFits(in: .horizontal) {
                libraryOpeningActions
                VStack(spacing: 8) {
                    detectedStartupLocationActions
                    manualLibraryOpeningActions
                    if detectedStartupLocations.count > 1 {
                        Text("Detected local paths stay inactive until you choose one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private var libraryOpeningActions: some View {
        HStack(spacing: 10) {
            detectedStartupLocationActions
            manualLibraryOpeningActions
        }
    }

    @ViewBuilder
    private var detectedStartupLocationActions: some View {
        ForEach(detectedStartupLocations) { record in
            Button {
                Task {
                    await session.useDetectedWorkspacePath(record)
                }
            } label: {
                Label(
                    WorkspacePathCommandLabels.useDetectedTitle(for: record.kind),
                    systemImage: "checkmark.circle"
                )
            }
            .help(detectedLocationHelp(for: record))
        }
    }

    @ViewBuilder
    private var manualLibraryOpeningActions: some View {
        Button {
            Task {
                await session.openLibraryFromPanel()
            }
        } label: {
            Label("Open Library", systemImage: "folder")
        }
        Button {
            Task {
                await session.openZoteroLibraryFromPanel()
            }
        } label: {
            Label("Open Zotero", systemImage: "tray.full")
        }
        if let recovery = session.configuredBilinLibraryRecovery {
            Button {
                WorkbenchFileActions.reveal(path: recovery.path)
            } label: {
                Label("Show Previous Library", systemImage: "magnifyingglass")
            }
        }
    }

    private var detectedStartupLocations: [WorkspacePathRecord] {
        [
            session.workspaceDefaults.uniqueAvailableDetectedWorkspacePath(kind: .zoteroLibrary),
            session.workspaceDefaults.uniqueAvailableDetectedWorkspacePath(kind: .obsidianVault)
        ]
        .compactMap { $0 }
    }

    private func detectedLocationMessage(for record: WorkspacePathRecord) -> String {
        switch record.kind {
        case .zoteroLibrary:
            return "Detected \(record.name). Use it only if this is the Zotero library you want Bilin to open."
        case .obsidianVault:
            return "Detected \(record.name). Use it only if this is the Obsidian vault for Note Bridge patches."
        case .bilinLibrary:
            return "Detected \(record.name). Use it only if this is the Bilin library you want to open."
        case .writingProjectRoot:
            return "Detected \(record.name). Use it only if this is the writing project you want to link."
        }
    }

    private func detectedLocationHelp(for record: WorkspacePathRecord) -> String {
        switch record.kind {
        case .zoteroLibrary:
            return "Open the detected Zotero library after confirming this local path"
        case .obsidianVault:
            return "Configure the detected Obsidian vault after confirming this local path"
        case .bilinLibrary:
            return "Open the detected Bilin library after confirming this local path"
        case .writingProjectRoot:
            return "Link the detected writing project after confirming this local path"
        }
    }
}

private struct ConfiguredBilinLibraryRecoveryRow: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession
    var recovery: ConfiguredBilinLibraryRecovery

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Previous library needs attention", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(recovery.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(recovery.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button {
                    Task {
                        await session.openLibraryFromPanel()
                    }
                } label: {
                    Label("Choose Library", systemImage: "folder")
                }
                Button {
                    WorkbenchFileActions.reveal(path: recovery.path)
                } label: {
                    Label("Show in Finder", systemImage: "magnifyingglass")
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }
}

private struct ConfiguredBilinLibraryRecoverySummary: View {
    var recovery: ConfiguredBilinLibraryRecovery

    var body: some View {
        VStack(spacing: 4) {
            Text(recovery.message)
                .foregroundStyle(.orange)
            Text(recovery.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct EmptyListHintRow: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

private struct ArticleListRow: View {
    var title: String
    var subtitle: String
    var isSelected = false
    var isLoading = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(3)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
                    .help("Loading paper")
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

private struct ZoteroItemRow: View {
    var item: ZoteroItem
    var isSelected = false
    var isLoading = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? item.key)
                    .font(.headline)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text(item.itemType)
                    if let arxiv = item.arxiv {
                        Text("arXiv \(arxiv.concreteIdentifier)")
                    }
                    if !item.tags.isEmpty {
                        Text(item.tags.prefix(2).joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
                    .help("Loading Zotero metadata")
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

private struct ReaderDetailPane: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession
    @SceneStorage("bilin.reader.inspectorPresented") private var inspectorPresented = true
    @SceneStorage("bilin.researchWorkbench.selectedMode")
    private var researchWorkbenchModeRawValue = ResearchWorkbenchMode.noteBridge.rawValue

    var body: some View {
        Group {
            if let item = session.selectedZoteroItem {
                HStack(spacing: 0) {
                    ZoteroMetadataDetailPane(item: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if inspectorPresented {
                        Divider()
                        ResearchWorkbenchInspectorPane(
                            selectedModeRawValue: $researchWorkbenchModeRawValue
                        )
                            .frame(width: 360)
                    }
                }
            } else if session.selectedArticle == nil && session.blocks.isEmpty {
                ReaderWelcomePane()
            } else {
                HStack(spacing: 0) {
                    ReaderSurface()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if inspectorPresented {
                        Divider()
                        ResearchWorkbenchInspectorPane(
                            selectedModeRawValue: $researchWorkbenchModeRawValue
                        )
                            .frame(width: 360)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    session.reloadSelectedLibraryItem()
                } label: {
                    Label("Reload Selection", systemImage: "arrow.clockwise")
                }
                .disabled(!session.canReloadSelectedLibraryItem)
                .help("Reload the selected paper or Zotero metadata")

                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label(
                        inspectorPresented ? "Hide Research Tools" : "Show Research Tools",
                        systemImage: "sidebar.right"
                    )
                }
                .disabled(!canShowResearchTools)
                .help(researchToolsHelp)
                Button {
                    session.openEquationEditor()
                } label: {
                    Label("Equation Editor", systemImage: "function")
                }
            }
        }
        .focusedSceneValue(\.readerInspectorPresented, $inspectorPresented)
        .focusedSceneValue(\.researchWorkbenchModeRawValue, $researchWorkbenchModeRawValue)
        .navigationTitle(session.selectedArticle?.title ?? session.selectedZoteroItem?.title ?? "Reader")
    }

    private var canShowResearchTools: Bool {
        session.selectedZoteroItem != nil
            || session.selectedArticle != nil
            || !session.blocks.isEmpty
    }

    private var researchToolsHelp: String {
        if canShowResearchTools {
            return inspectorPresented ? "Hide the research tools rail." : "Show the research tools rail."
        }
        return "Research tools are available after selecting a Bilin paper or Zotero item."
    }
}

private struct ReaderWelcomePane: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession

    var body: some View {
        ContentUnavailableView {
            Label("Choose a Paper", systemImage: "doc.text.magnifyingglass")
        } description: {
            VStack(spacing: 8) {
                Text("Select a paper from the library, open a local Bilin library, or inspect Zotero metadata.")
                if let recovery = session.configuredBilinLibraryRecovery {
                    ConfiguredBilinLibraryRecoverySummary(recovery: recovery)
                } else if let loadError = session.loadError {
                    Text(loadError)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
        } actions: {
            HStack(spacing: 10) {
                Button {
                    Task {
                        await session.openLibraryFromPanel()
                    }
                } label: {
                    Label("Open Library", systemImage: "folder")
                }
                Button {
                    Task {
                        await session.openZoteroLibraryFromPanel()
                    }
                } label: {
                    Label("Open Zotero", systemImage: "tray.full")
                }
                Button {
                    session.openEquationEditor()
                } label: {
                    Label("Equation Editor", systemImage: "function")
                }
                if let recovery = session.configuredBilinLibraryRecovery {
                    Button {
                        WorkbenchFileActions.reveal(path: recovery.path)
                    } label: {
                        Label("Show Previous Library", systemImage: "magnifyingglass")
                    }
                }
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ZoteroMetadataDetailPane: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession
    var item: ZoteroItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.title ?? item.key)
                    .font(.largeTitle.weight(.semibold))
                HStack(spacing: 10) {
                    Label(item.itemType, systemImage: "doc.text")
                    if let arxiv = item.arxiv {
                        Label("arXiv \(arxiv.concreteIdentifier)", systemImage: "number")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !item.creators.isEmpty {
                    MetadataSection(title: "Creators", value: item.creators.map(\.displayName).joined(separator: ", "))
                }
                if let abstractNote = item.abstractNote {
                    MetadataSection(title: "Abstract", value: abstractNote)
                }
                ZoteroMetadataStateRow(item: item)
                if !item.collections.isEmpty {
                    MetadataSection(title: "Collections", value: item.collections.map(\.name).joined(separator: ", "))
                }
                if !item.tags.isEmpty {
                    MetadataSection(title: "Tags", value: item.tags.joined(separator: ", "))
                }
                if let doi = item.doi {
                    MetadataSection(title: "DOI", value: doi)
                }
                if let url = item.url {
                    MetadataSection(title: "URL", value: url)
                }
                if !item.attachments.isEmpty {
                    ZoteroAttachmentSection(attachments: item.attachments)
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 46)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ZoteroMetadataStateRow: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession
    var item: ZoteroItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Metadata loaded from local Zotero", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                WorkbenchStatusPill(
                    text: statusPillText,
                    systemImage: statusPillSystemImage,
                    tint: statusPillTint
                )
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    await session.prepareSelectedZoteroImportActionPlan()
                }
            } label: {
                Label(actionTitle, systemImage: actionSystemImage)
            }
            .disabled(!canPrepareActionPlan)

            if session.selectedLibraryId == nil {
                Button {
                    Task {
                        await session.openLibraryFromPanel()
                    }
                } label: {
                    Label("Open Bilin Library", systemImage: "folder")
                }
                .help("Open a Bilin library before preparing a Zotero import plan")
            } else if !session.isResearchAPIReady {
                Button {
                    Task {
                        await session.refreshResearchWorkbench()
                    }
                } label: {
                    Label("Refresh Research API", systemImage: "arrow.clockwise")
                }
                .help("Check the local research backend before preparing a Zotero import plan")
            }

            if !zoteroActionPlans.isEmpty {
                ZoteroImportActionPlansSection(actionPlans: zoteroActionPlans)
            }
        }
        .font(.subheadline)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var zoteroActionPlans: [AgentActionPlan] {
        session.researchActionPlans
            .filter { $0.targetsZoteroImportItem(item.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var latestActionPlan: AgentActionPlan? {
        zoteroActionPlans.first
    }

    private var canPrepareActionPlan: Bool {
        session.selectedLibraryId != nil
            && session.isResearchAPIReady
            && !session.researchAPIBusy
            && !hasOpenActionPlan
    }

    private var hasOpenActionPlan: Bool {
        guard let latestActionPlan else { return false }
        switch latestActionPlan.status {
        case .draft, .pendingApproval, .approved, .queued, .running:
            return true
        case .rejected, .cancelled, .succeeded, .failed:
            return false
        }
    }

    private var actionTitle: String {
        item.arxiv == nil ? "Prepare Import Plan" : "Prepare Download Plan"
    }

    private var actionSystemImage: String {
        item.arxiv == nil ? "tray.and.arrow.down" : "arrow.down.doc"
    }

    private var statusText: String {
        if let latestActionPlan {
            switch latestActionPlan.status {
            case .draft, .pendingApproval:
                return "Review and approve the prepared Zotero action plan before Bilin writes any import bundle."
            case .approved:
                return "The Zotero action plan is approved. Write the import bundle when you are ready."
            case .queued, .running:
                return "The Zotero import action is running."
            case .succeeded:
                return "The Zotero import bundle has been written into the Bilin library."
            case .failed:
                return "The Zotero import action failed. Regenerate the plan or dismiss this attempt."
            case .rejected:
                return "The Zotero import plan was rejected. Prepare a new plan if you still want to import this item."
            case .cancelled:
                return "The Zotero import plan was cancelled. Prepare a new plan if you still want to import this item."
            }
        }
        if session.selectedLibraryId == nil {
            return "Open a Bilin library before preparing a confirmed Zotero import action plan."
        }
        if !session.isResearchAPIReady {
            return "Connect the research backend before preparing a confirmed Zotero import action plan."
        }
        if session.researchAPIBusy {
            return "Research action preparation is already running."
        }
        if item.arxiv == nil {
            return "Prepare a confirmed action plan before importing this Zotero metadata into the Bilin library."
        }
        return "Prepare a confirmed action plan before downloading the arXiv paper and importing it into the Bilin library."
    }

    private var statusPillText: String {
        guard let latestActionPlan else {
            return "Import needs action plan"
        }
        switch latestActionPlan.status {
        case .draft:
            return "Action plan drafted"
        case .pendingApproval:
            return "Awaiting approval"
        case .approved:
            return "Approved"
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .succeeded:
            return "Import written"
        case .failed:
            return "Import failed"
        case .rejected:
            return "Rejected"
        case .cancelled:
            return "Cancelled"
        }
    }

    private var statusPillSystemImage: String {
        latestActionPlan
            .map { AgentActionPlanStatusPresentation.resolve($0.status).systemImage }
            ?? "shield.lefthalf.filled"
    }

    private var statusPillTint: Color {
        latestActionPlan
            .map { AgentActionPlanStatusPresentation.resolve($0.status).tint }
            ?? .secondary
    }
}

private struct ZoteroImportActionPlansSection: View {
    var actionPlans: [AgentActionPlan]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zotero Action Plans")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(actionPlans) { actionPlan in
                ZoteroImportActionPlanRow(actionPlan: actionPlan)
            }
        }
        .padding(.top, 4)
    }
}

private struct ZoteroImportActionPlanRow: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession
    var actionPlan: AgentActionPlan

    var body: some View {
        let statusPresentation = AgentActionPlanStatusPresentation.resolve(actionPlan.status)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(actionPlan.title, systemImage: actionPlan.kind.zoteroImportSystemImage)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                WorkbenchStatusPill(
                    text: actionPlan.status.zoteroImportDisplayName,
                    systemImage: statusPresentation.systemImage,
                    tint: statusPresentation.tint
                )
            }

            Text(actionPlan.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let previewText {
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.65))
            }

            if let errorMessage = actionPlan.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                switch actionPlan.status {
                case .pendingApproval:
                    Button {
                        Task { await session.approveResearchActionPlan(actionPlan) }
                    } label: {
                        Label("Approve Plan", systemImage: "checkmark")
                    }
                    Button {
                        Task { await session.rejectResearchActionPlan(actionPlan) }
                    } label: {
                        Label("Reject Plan", systemImage: "xmark")
                    }
                case .approved:
                    Button {
                        Task { await session.applyResearchActionPlan(actionPlan) }
                    } label: {
                        Label("Write Import Bundle", systemImage: "square.and.arrow.down")
                    }
                case .failed:
                    Button {
                        Task { await session.regenerateResearchActionPlan(actionPlan) }
                    } label: {
                        Label("Regenerate Plan", systemImage: "arrow.clockwise")
                    }
                    Button {
                        session.dismissResearchActionPlan(actionPlan)
                    } label: {
                        Label("Dismiss", systemImage: "xmark.circle")
                    }
                case .rejected, .cancelled, .succeeded:
                    Button {
                        session.dismissResearchActionPlan(actionPlan)
                    } label: {
                        Label("Dismiss", systemImage: "xmark.circle")
                    }
                case .draft, .queued, .running:
                    EmptyView()
                }
            }
            .disabled(session.researchAPIBusy)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.65))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var previewText: String? {
        actionPlan.preview?["import_summary"]
            ?? actionPlan.preview?["candidate_summary"]
            ?? actionPlan.preview?["action_summary"]
    }
}

private extension AgentActionPlan {
    func targetsZoteroImportItem(_ zoteroItemId: Int64) -> Bool {
        switch kind {
        case .downloadPaper, .importLibrary:
            return payload["zotero_item_id"] == String(zoteroItemId)
        case .writeObsidian,
             .editManuscript,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .notePatch,
             .writingPatch,
             .generateResearchOutline,
             .custom:
            return false
        }
    }
}

private extension AgentActionKind {
    var zoteroImportSystemImage: String {
        switch self {
        case .downloadPaper:
            return "arrow.down.doc"
        case .importLibrary:
            return "tray.and.arrow.down"
        default:
            return "checklist"
        }
    }
}

private extension AgentActionStatus {
    var zoteroImportDisplayName: String {
        switch self {
        case .draft:
            return "Draft"
        case .pendingApproval:
            return "Pending approval"
        case .approved:
            return "Approved"
        case .queued:
            return "Queued"
        case .rejected:
            return "Rejected"
        case .cancelled:
            return "Cancelled"
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        }
    }
}

private enum WorkbenchFileActions {
    static func open(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func reveal(path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.selectFile(
                path,
                inFileViewerRootedAtPath: url.deletingLastPathComponent().path
            )
        }
    }
}

private struct ZoteroAttachmentSection: View {
    var attachments: [ZoteroAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(attachments.indices, id: \.self) { index in
                    ZoteroAttachmentRow(attachment: attachments[index])
                    if index < attachments.count - 1 {
                        Divider()
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

private struct ZoteroAttachmentRow: View {
    var attachment: ZoteroAttachment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ZoteroAttachmentPathText(path: displayPath)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)

            Spacer(minLength: 12)

            if let filePath = attachment.resolvedFileURL?.path {
                HStack(spacing: 6) {
                    Button {
                        WorkbenchFileActions.open(path: filePath)
                    } label: {
                        Label("Open Attachment", systemImage: "doc.text")
                    }
                    .help("Open attachment")

                    Button {
                        WorkbenchFileActions.reveal(path: filePath)
                    } label: {
                        Label("Show in Finder", systemImage: "magnifyingglass")
                    }
                    .help("Show attachment in Finder")
                }
                .controlSize(.small)
                .fixedSize()
            } else {
                WorkbenchStatusPill(
                    text: "Path unresolved",
                    systemImage: "exclamationmark.triangle",
                    tint: .secondary
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayTitle: String {
        if let resolvedFileURL = attachment.resolvedFileURL {
            return resolvedFileURL.lastPathComponent
        }
        guard let path = attachment.path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            return attachment.key
        }
        let storagePrefix = "storage:"
        if path.hasPrefix(storagePrefix) {
            return String(path.dropFirst(storagePrefix.count))
        }
        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
        return lastPathComponent.isEmpty ? path : lastPathComponent
    }

    private var displayPath: String {
        if let resolvedFileURL = attachment.resolvedFileURL {
            return resolvedFileURL.path
        }
        return attachment.path ?? "No local attachment path"
    }

    private var metadataText: String {
        [
            attachment.contentType,
            "Key \(attachment.key)"
        ]
        .compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        .joined(separator: " · ")
    }
}

private struct ZoteroAttachmentPathText: View {
    var path: String

    var body: some View {
        Text(path)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            .accessibilityLabel(path)
    }
}

enum ReaderBlockClipboardPayload {
    static func sourceText(for block: DocumentBlock) -> String {
        if let latex = equationLatex(for: block) {
            return ReaderSemanticCopyFormatter.displayMathMarkdown(latex: latex)
        }
        return ReaderSemanticCopyFormatter.blockMarkdown(markdown: block.sourceMarkdown)
    }

    static func equationLatex(for block: DocumentBlock) -> String? {
        guard block.blockType == .equation else {
            return nil
        }
        let latex = (block.sourceLatex ?? block.sourceMarkdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLatex = normalizedEquationLatex(latex)
        return normalizedLatex.isEmpty ? nil : normalizedLatex
    }

    private static func normalizedEquationLatex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count >= 4 {
            return String(trimmed.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("\\["), trimmed.hasSuffix("\\]"), trimmed.count >= 4 {
            return String(trimmed.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}

enum ReaderClipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct MetadataSection: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}

private struct ReaderSurface: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if session.isLoadingSelectedLibraryItem {
                        ReaderLoadingState(title: session.selectedArticle?.title)
                            .frame(maxWidth: .infinity, minHeight: 360)
                    } else if let loadError = session.selectedLibraryItemLoadError ?? session.loadError {
                        ReaderLoadFailureState(
                            message: loadError,
                            canRetry: session.selectedLibraryItem != nil,
                            retry: {
                                session.requestLibraryItemSelection(session.selectedLibraryItem)
                            }
                        )
                            .frame(maxWidth: .infinity, minHeight: 360)
                    } else if session.blocks.isEmpty {
                        ContentUnavailableView {
                            Label("No Document Loaded", systemImage: "doc.text")
                        } description: {
                            Text("Choose a paper from the library to load its parsed reading blocks.")
                        }
                        .frame(maxWidth: .infinity, minHeight: 360)
                    } else {
                        ForEach(session.blocks) { block in
                            ReaderBlockRow(
                                block: block,
                                citationResolver: session.citationResolver,
                                isSelected: session.selectedBlockUid == block.blockUid,
                                selectedCitationEntryId: session.selectedCitationEntryId,
                                selectedText: selectedText(in: block),
                                onSelect: {
                                    session.selectReaderBlock(block.blockUid)
                                },
                                onCitationClick: { entry in
                                    session.selectCitationEntry(entry)
                                },
                                onTextSelectionChange: { selectedText in
                                    session.updateReaderTextSelection(
                                        blockUid: block.blockUid,
                                        selectedText: selectedText
                                    )
                                }
                            )
                            .id(block.blockUid)
                        }
                    }
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 46)
                .frame(maxWidth: 860, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: session.readerBlockScrollRequest) { _, request in
                guard let request else { return }
                scrollToBlock(request.blockUid, with: scrollProxy)
            }
        }
    }

    private func selectedText(in block: DocumentBlock) -> String? {
        session.readerTextSelection(for: block.blockUid)?.text
    }

    private func scrollToBlock(_ blockUid: String, with scrollProxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            scrollProxy.scrollTo(blockUid, anchor: .center)
        }
    }
}

private struct ReaderLoadingState: View {
    var title: String?

    var body: some View {
        ContentUnavailableView {
            Label("Loading Paper", systemImage: "doc.text")
        } description: {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Preparing the parsed reader blocks.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ReaderLoadFailureState: View {
    var message: String
    var canRetry: Bool = false
    var retry: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label("Paper Could Not Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } actions: {
            if canRetry {
                Button {
                    retry()
                } label: {
                    Label("Retry Paper", systemImage: "arrow.clockwise")
                }
                .help("Retry loading the selected paper")
            }
        }
    }
}

private struct ReaderBlockRow: View {
    var block: DocumentBlock
    var citationResolver: ReaderCitationResolver
    var isSelected: Bool
    var selectedCitationEntryId: String?
    var selectedText: String?
    var onSelect: () -> Void
    var onCitationClick: (ReaderCitationEntry) -> Void
    var onTextSelectionChange: (String?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                onSelect()
            } label: {
                Image(systemName: isSelected ? "circle.fill" : "circle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .frame(width: 18, height: 22)
            .help("Select block")

            blockContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            if let selectedText, !selectedText.isEmpty {
                Button {
                    ReaderClipboard.copy(selectedText)
                } label: {
                    Label("Copy Selection", systemImage: "doc.on.doc")
                }
                Divider()
            }
            Button {
                ReaderClipboard.copy(ReaderBlockClipboardPayload.sourceText(for: block))
            } label: {
                Label("Copy Block Markdown", systemImage: "doc.text")
            }
            if let latex = ReaderBlockClipboardPayload.equationLatex(for: block) {
                Button {
                    ReaderClipboard.copy(latex)
                } label: {
                    Label("Copy LaTeX", systemImage: "function")
                }
            }
        }
    }

    @ViewBuilder
    private var blockContent: some View {
        let bibliographyLines = ReaderCitationResolver.bibliographyLines(in: block)
        if !bibliographyLines.isEmpty {
            SelectableInlineMarkupView(
                markdown: block.sourceMarkdown,
                font: .body,
                citationResolver: citationResolver,
                bibliographyLines: bibliographyLines,
                selectedCitationEntryId: selectedCitationEntryId,
                onActivate: onSelect,
                onCitationClick: onCitationClick,
                onSelectionChange: onTextSelectionChange
            )
        } else {
            switch block.blockType {
            case .title:
                SelectableInlineMarkupView(
                    markdown: block.sourceMarkdown,
                    font: .title,
                    citationResolver: citationResolver,
                    onActivate: onSelect,
                    onCitationClick: onCitationClick,
                    onSelectionChange: onTextSelectionChange
                )
            case .section, .subsection:
                SelectableInlineMarkupView(
                    markdown: block.sourceMarkdown,
                    font: .heading,
                    citationResolver: citationResolver,
                    onActivate: onSelect,
                    onCitationClick: onCitationClick,
                    onSelectionChange: onTextSelectionChange
                )
            case .equation:
                SelectableDisplayEquationBlock(
                    latex: block.sourceLatex ?? block.sourceMarkdown,
                    onActivate: onSelect,
                    onSelectionChange: onTextSelectionChange
                )
            default:
                ReaderMarkdownBlockContent(
                    markdown: block.sourceMarkdown,
                    font: .body,
                    citationResolver: citationResolver,
                    selectedCitationEntryId: selectedCitationEntryId,
                    onActivate: onSelect,
                    onCitationClick: onCitationClick,
                    onSelectionChange: onTextSelectionChange
                )
            }
        }
    }
}

private struct ReaderMarkdownBlockContent: View {
    var markdown: String
    var font: ReaderInlineFontStyle
    var citationResolver: ReaderCitationResolver
    var selectedCitationEntryId: String?
    var onActivate: () -> Void
    var onCitationClick: (ReaderCitationEntry) -> Void
    var onSelectionChange: (String?) -> Void

    private var segments: [ReaderMarkdownBlockSegment] {
        ReaderMarkdownBlockSegmenter.segments(in: markdown)
    }

    var body: some View {
        if segments.count == 1, let segment = segments.first, segment.kind == .markdown {
            inlineMarkdown(segment.text)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(segments) { segment in
                    switch segment.kind {
                    case .markdown:
                        inlineMarkdown(segment.text)
                    case .displayMath:
                        SelectableDisplayEquationBlock(
                            latex: segment.text,
                            onActivate: onActivate,
                            onSelectionChange: onSelectionChange
                        )
                    }
                }
            }
        }
    }

    private func inlineMarkdown(_ value: String) -> some View {
        SelectableInlineMarkupView(
            markdown: value,
            font: font,
            citationResolver: citationResolver,
            selectedCitationEntryId: selectedCitationEntryId,
            onActivate: onActivate,
            onCitationClick: onCitationClick,
            onSelectionChange: onSelectionChange
        )
    }
}

private struct SelectableDisplayEquationBlock: View {
    var latex: String
    var onActivate: () -> Void
    var onSelectionChange: (String?) -> Void

    private var trimmedLatex: String {
        latex.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        AsyncEquationBlockView(latex: trimmedLatex)
            .contentShape(Rectangle())
            .onTapGesture(perform: selectEquation)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, selectEquation)
    }

    private func selectEquation() {
        onActivate()
        guard !trimmedLatex.isEmpty else {
            onSelectionChange(nil)
            return
        }
        let semanticText = ReaderSemanticCopyFormatter.displayMathMarkdown(latex: trimmedLatex)
        onSelectionChange(semanticText)
    }
}

private struct AsyncEquationBlockView: View {
    @Environment(\.colorScheme) private var colorScheme

    var latex: String
    @State private var renderState = EquationBlockRenderState()

    private var options: RatexRenderOptions {
        ReaderMathRenderOptions.options(
            fontSize: 18,
            colorScheme: colorScheme,
            timeoutSeconds: 5
        )
    }

    var body: some View {
        let requestedLatex = trimmedLatex
        let requestedKey = renderKey(for: requestedLatex)
        equationContent(
            renderState.result(for: requestedKey)
                ?? cachedResidentResult(for: requestedKey, latex: requestedLatex)
                ?? FallbackMathRenderer().renderDisplay(latex: requestedLatex)
        )
            .task(id: requestedKey) {
                await renderIfNeeded()
            }
    }

    private var trimmedLatex: String {
        latex.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderKey(for requestedLatex: String) -> RatexRenderCacheKey {
        RatexRenderCacheKey(latex: requestedLatex, layoutMode: .block, options: options)
    }

    private func cachedResidentResult(for key: RatexRenderCacheKey, latex requestedLatex: String) -> MathRenderResult? {
        guard !requestedLatex.isEmpty else { return nil }
        return RatexRenderCacheStore.shared.cachedResidentResult(for: key)
    }

    @ViewBuilder
    private func equationContent(_ result: MathRenderResult) -> some View {
        switch result.payload {
        case .plainText(let value):
            equationText(
                value,
                accessibilityLabel: result.accessibilityLabel,
                latexForCopy: result.latex
            )
        case .unavailable(let reason):
            equationText(
                "\(result.latex)\n\(reason)",
                accessibilityLabel: result.accessibilityLabel,
                latexForCopy: result.latex
            )
        case .svg(let svg):
            SVGImageView(
                svg: svg,
                accessibilityLabel: "Equation \(result.accessibilityLabel)",
                preferNativeImage: true
            )
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .contextMenu {
                    Button {
                        copyLatex(result.latex)
                    } label: {
                        Label("Copy LaTeX", systemImage: "doc.on.doc")
                    }
                }
                .help("Right-click to copy LaTeX")
        }
    }

    private func equationText(
        _ value: String,
        accessibilityLabel: String,
        latexForCopy: String
    ) -> some View {
        Text(value)
            .font(.system(.body, design: .serif))
            .monospaced()
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
            .accessibilityLabel("Equation \(accessibilityLabel)")
            .contextMenu {
                Button {
                    copyLatex(latexForCopy)
                } label: {
                    Label("Copy LaTeX", systemImage: "doc.on.doc")
                }
            }
    }

    private func copyLatex(_ latex: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(latex, forType: .string)
    }

    @MainActor
    private func renderIfNeeded() async {
        let requestedLatex = trimmedLatex
        let key = renderKey(for: requestedLatex)
        renderState.prepareForLoad(key: key)
        guard !requestedLatex.isEmpty else { return }
        if let cached = RatexRenderCacheStore.shared.cachedResidentResult(for: key) {
            renderState.store(cached, for: key)
            return
        }

        let renderOptions = options
        let rendered = await RatexRenderCacheStore.shared.result(for: key, priority: .utility) {
            RatexMathRenderer(options: renderOptions).renderDisplay(latex: requestedLatex)
        }
        guard !Task.isCancelled, requestedLatex == trimmedLatex else { return }
        renderState.store(rendered, for: key)
    }
}

struct EquationBlockRenderState {
    private var key: RatexRenderCacheKey?
    private var renderResult: MathRenderResult?

    func result(for requestedKey: RatexRenderCacheKey) -> MathRenderResult? {
        key == requestedKey ? renderResult : nil
    }

    mutating func prepareForLoad(key requestedKey: RatexRenderCacheKey) {
        guard key != requestedKey else { return }
        key = requestedKey
        renderResult = nil
    }

    mutating func store(_ result: MathRenderResult, for requestedKey: RatexRenderCacheKey) {
        key = requestedKey
        renderResult = result
    }
}
