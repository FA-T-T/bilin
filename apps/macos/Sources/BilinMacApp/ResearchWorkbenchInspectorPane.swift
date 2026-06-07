import Foundation
import AppKit
import SwiftUI
import BilinImportKit
import BilinReaderKit
import BilinWorkspaceKit

struct ResearchWorkbenchInspectorPane: View {
    @EnvironmentObject private var session: ReaderWorkbenchSession
    @EnvironmentObject private var workspaceDefaults: WorkspaceDefaultsModel
    @Binding var selectedModeRawValue: String
    @State private var snapshotCache = ResearchWorkbenchSnapshotCache()

    var body: some View {
        let snapshotKey = ResearchWorkbenchSnapshotKey(
            session: session,
            workspaceDefaults: workspaceDefaults
        )
        let activeMode = selectedMode
        let snapshot = snapshotCache.snapshot(for: snapshotKey) {
            ResearchWorkbenchSnapshot(
                session: session,
                workspaceDefaults: workspaceDefaults
            )
        }

        VStack(spacing: 0) {
            ResearchWorkbenchHeader(snapshot: snapshot)
            Divider()
            ResearchWorkbenchSetupPanel(snapshot: snapshot)
            Divider()
            ResearchWorkbenchModeTabs(selection: selectedModeBinding)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch activeMode {
                    case .noteBridge:
                        NoteBridgeModeView(snapshot: snapshot)
                    case .researchPlan:
                        ResearchPlanModeView(snapshot: snapshot)
                    case .writingDock:
                        WritingDockModeView(snapshot: snapshot)
                    }

                    ResearchWorkbenchLocalState(snapshot: snapshot)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var selectedMode: ResearchWorkbenchMode {
        ResearchWorkbenchMode(rawValue: selectedModeRawValue) ?? .noteBridge
    }

    private var selectedModeBinding: Binding<ResearchWorkbenchMode> {
        Binding(
            get: { selectedMode },
            set: { selectedModeRawValue = $0.rawValue }
        )
    }
}

enum ResearchWorkbenchMode: String, CaseIterable, Identifiable {
    case noteBridge
    case researchPlan
    case writingDock

    var id: Self { self }

    var title: String {
        switch self {
        case .noteBridge:
            return "Note Bridge"
        case .researchPlan:
            return "Research Plan"
        case .writingDock:
            return "Writing Dock"
        }
    }

    var systemImage: String {
        switch self {
        case .noteBridge:
            return "note.text"
        case .researchPlan:
            return "list.bullet.clipboard"
        case .writingDock:
            return "doc.richtext"
        }
    }
}

private struct ResearchWorkbenchHeader: View {
    var snapshot: ResearchWorkbenchSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Label("Research Workbench", systemImage: "square.and.pencil")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                WorkbenchStatusPill(
                    text: snapshot.researchAPIStatus,
                    systemImage: "externaldrive",
                    tint: snapshot.researchAPIStatusTint
                )
                Button {
                    Task {
                        await snapshot.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(snapshot.researchAPIBusy)
            }

            Text(snapshot.articleTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Label(snapshot.selectedBlockLabel, systemImage: "scope")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let backendLabel = snapshot.researchAPIHealthLabel {
                Label(backendLabel, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResearchWorkbenchModeTabs: View {
    @Binding var selection: ResearchWorkbenchMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ResearchWorkbenchMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                        Text(mode.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == mode ? Color.accentColor : Color.primary)
                .background(
                    selection == mode ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            selection == mode ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                }
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(10)
    }
}

private struct ResearchWorkbenchSetupPanel: View {
    var snapshot: ResearchWorkbenchSnapshot

    var body: some View {
        WorkbenchPanel(
            title: "Setup",
            status: snapshot.setupStatusLabel,
            systemImage: "checklist"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.setupItems) { item in
                    ResearchWorkbenchSetupRow(item: item, snapshot: snapshot)
                }
            }
        }
    }
}

private struct ResearchWorkbenchSetupRow: View {
    var item: ResearchWorkbenchSetupItem
    var snapshot: ResearchWorkbenchSnapshot
    @State private var pendingEnableSkill: ResearchSkill?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let action = item.action {
                    Button {
                        request(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .controlSize(.small)
                    .disabled(snapshot.researchAPIBusy && action.requiresIdleResearchAction)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.tint.opacity(0.08))
        .confirmationDialog(
            pendingEnableSkill.map {
                ResearchWorkbenchSetupAction.enableResearchSkill($0).confirmationTitle ?? "Enable Skill?"
            } ?? "Enable Skill?",
            isPresented: Binding(
                get: { pendingEnableSkill != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingEnableSkill = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingEnableSkill {
                Button("Enable Skill") {
                    confirmEnableSkill(pendingEnableSkill)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingEnableSkill = nil
            }
        } message: {
            if let pendingEnableSkill {
                Text(
                    ResearchWorkbenchSetupAction.enableResearchSkill(pendingEnableSkill)
                        .confirmationMessage ?? pendingEnableSkill.enableConfirmationMessage
                )
            }
        }
    }

    private func request(_ action: ResearchWorkbenchSetupAction) {
        switch action {
        case .enableResearchSkill(let skill):
            pendingEnableSkill = skill
        case .refreshAPI,
             .refreshWorkbench,
             .indexResearchSkills,
             .detectLocalApps,
             .chooseBilinLibrary,
             .chooseZoteroLibrary,
             .useDetectedWorkspacePath,
             .chooseObsidianVault,
             .chooseWritingProject:
            perform(action)
        }
    }

    private func confirmEnableSkill(_ skill: ResearchSkill) {
        pendingEnableSkill = nil
        Task {
            await snapshot.enableSkill(skill)
        }
    }

    private func perform(_ action: ResearchWorkbenchSetupAction) {
        switch action {
        case .refreshAPI:
            Task {
                await snapshot.refresh()
            }
        case .refreshWorkbench:
            Task {
                await snapshot.refresh()
            }
        case .indexResearchSkills:
            Task {
                await snapshot.indexSkills()
            }
        case .enableResearchSkill(let skill):
            confirmEnableSkill(skill)
        case .detectLocalApps:
            snapshot.detectWorkspacePaths()
        case .chooseBilinLibrary:
            Task {
                await snapshot.chooseBilinLibrary()
            }
        case .chooseZoteroLibrary:
            Task {
                await snapshot.chooseZoteroLibrary()
            }
        case .useDetectedWorkspacePath(let record):
            Task {
                await snapshot.useDetectedWorkspacePath(record)
            }
        case .chooseObsidianVault:
            snapshot.chooseObsidianVault()
        case .chooseWritingProject:
            snapshot.chooseWritingProject()
        }
    }
}

private struct NoteBridgeModeView: View {
    var snapshot: ResearchWorkbenchSnapshot

    var body: some View {
        WorkbenchPanel(
            title: "Note Bridge",
            status: snapshot.noteBridge?.status.displayName ?? "Select block",
            systemImage: "note.text"
        ) {
            if let bridge = snapshot.noteBridge {
                let sourceScope = WorkbenchSourceScope.resolve(bridge)
                KeyValueRows {
                    KeyValueRow(label: "Vault", value: bridge.targetVault.name)
                    KeyValueRow(label: "Vault path", value: bridge.targetVault.rootPath, monospaced: true)
                    KeyValueRow(label: "Target note", value: bridge.targetNotePath, monospaced: true)
                    KeyValueRow(label: "Heading", value: bridge.headingPath.joined(separator: " / "))
                    KeyValueRow(label: "Block anchor", value: bridge.blockAnchor, monospaced: true)
                    KeyValueRow(label: "Source scope", value: sourceScope.displayName)
                    if let selectionHash = sourceScope.selectionHash {
                        KeyValueRow(label: "Selection hash", value: selectionHash, monospaced: true)
                    }
                }

                WorkbenchPreviewBlock(
                    title: sourceScope.previewTitle,
                    value: bridge.sourcePayload.markdown
                )

                if let translation = bridge.translationPayload {
                    WorkbenchPreviewBlock(
                        title: "Translation payload",
                        value: translation.markdown
                    )
                }

                if let patch = bridge.pendingPatch {
                    PatchPreviewRow(patch: patch)
                }

                WorkbenchActionReadinessRow(readiness: snapshot.noteActionReadiness)

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await snapshot.prepareNoteActionPlan()
                        }
                    } label: {
                        Label("Prepare Note Patch", systemImage: "plus")
                    }
                    .disabled(!snapshot.noteActionReadiness.isReady || snapshot.researchAPIBusy)

                    Button {
                        Task {
                            await snapshot.indexSkills()
                        }
                    } label: {
                        Label("Index Skills", systemImage: "shippingbox")
                    }
                    .disabled(snapshot.researchAPIBusy)
                }

                if !snapshot.noteActionPlans.isEmpty {
                    ActionPlansSection(
                        title: "Action Plans",
                        actionPlans: snapshot.noteActionPlans,
                        snapshot: snapshot
                    )
                }

                if snapshot.selectedObsidianVault?.status != .available {
                    if let detectedVault = snapshot.uniqueAvailableDetectedObsidianVault {
                        WorkbenchPreviewBlock(
                            title: "Detected Obsidian vault",
                            value: detectedVault.path,
                            monospaced: true,
                            maxLines: 2
                        )
                        Button {
                            Task {
                                await snapshot.useDetectedWorkspacePath(detectedVault)
                            }
                        } label: {
                            Label(
                                WorkspacePathCommandLabels.useDetectedTitle(for: detectedVault.kind),
                                systemImage: "checkmark"
                            )
                        }
                        .disabled(snapshot.researchAPIBusy)
                        .help("Configure the detected Obsidian vault before preparing Note Bridge patches")
                    }
                    Button {
                        snapshot.chooseObsidianVault()
                    } label: {
                        Label("Choose Obsidian Vault", systemImage: "folder")
                    }
                }
            } else {
                WorkbenchEmptyState(
                    systemImage: "cursorarrow.click",
                    title: "No source block",
                    text: "Anchor, note path, and patch preview unavailable."
                )
            }
        }
    }
}

enum WorkbenchSourceScope: Hashable {
    case selectedExcerpt(hash: String)
    case wholeBlock

    var displayName: String {
        switch self {
        case .selectedExcerpt:
            return "Selected excerpt"
        case .wholeBlock:
            return "Whole block"
        }
    }

    var previewTitle: String {
        switch self {
        case .selectedExcerpt:
            return "Selected excerpt payload"
        case .wholeBlock:
            return "Source block payload"
        }
    }

    var selectionHash: String? {
        switch self {
        case .selectedExcerpt(let hash):
            return hash
        case .wholeBlock:
            return nil
        }
    }

    static func resolve(_ bridge: NoteBridge) -> WorkbenchSourceScope {
        resolve(bridge.provenance)
    }

    static func resolve(_ patch: PendingFilePatch) -> WorkbenchSourceScope? {
        patch.provenance.first.map(resolve)
    }

    static func resolve(_ provenance: SourceBlockProvenance) -> WorkbenchSourceScope {
        guard let selectedTextHash = provenance.selectedTextHash,
              !selectedTextHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .wholeBlock }
        return .selectedExcerpt(hash: selectedTextHash)
    }
}

private struct ResearchPlanModeView: View {
    var snapshot: ResearchWorkbenchSnapshot

    var body: some View {
        WorkbenchPanel(
            title: "Research Plan",
            status: snapshot.outline.status.displayName,
            systemImage: "list.bullet.clipboard"
        ) {
            Text(snapshot.outline.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !snapshot.outline.summary.isEmpty {
                WorkbenchPreviewBlock(
                    title: "Reading focus",
                    value: snapshot.outline.summary,
                    maxLines: 6
                )
            }

            WorkbenchActionReadinessRow(readiness: snapshot.researchPlanActionReadiness)

            Button {
                Task {
                    await snapshot.prepareResearchPlanActionPlan()
                }
            } label: {
                Label("Prepare Reading Outline", systemImage: "wand.and.stars")
            }
            .disabled(!snapshot.researchPlanActionReadiness.isReady || snapshot.researchAPIBusy)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.outline.items) { item in
                    OutlineItemRow(item: item)
                }
            }

            ForEach(Array(snapshot.outline.paperMasteryOutlines.enumerated()), id: \.offset) { _, mastery in
                PaperMasteryOutlineRow(outline: mastery)
            }

            if !snapshot.outline.questions.isEmpty {
                WorkbenchPreviewBlock(
                    title: "Open questions",
                    value: snapshot.outline.questions.joined(separator: "\n"),
                    maxLines: 8
                )
            }

            if !snapshot.researchPlanActionPlans.isEmpty {
                ActionPlansSection(
                    title: "Reading Outline Actions",
                    actionPlans: snapshot.researchPlanActionPlans,
                    snapshot: snapshot,
                    supportsLocalApply: false,
                    supportsRemoteRun: true
                )
            }

            if snapshot.outline.items.isEmpty {
                WorkbenchEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No outline source",
                    text: "Parsed paper structure unavailable."
                )
            }
        }
    }
}

private struct PaperMasteryOutlineRow: View {
    var outline: ResearchPaperMasteryOutline

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(outline.paperTitle.isEmpty ? "Paper mastery outline" : outline.paperTitle, systemImage: "graduationcap")
                .font(.caption.weight(.semibold))

            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                if !group.items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(group.title, systemImage: group.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.items.prefix(4), id: \.self) { item in
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 18)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var groups: [(title: String, systemImage: String, items: [String])] {
        [
            ("Claims", "checkmark.seal", outline.claim),
            ("Method", "gearshape.2", outline.method),
            ("Equations", "function", outline.equation),
            ("Evidence", "chart.bar.doc.horizontal", outline.evidence),
            ("Limits", "exclamationmark.triangle", outline.limitation),
            ("Next steps", "arrow.triangle.branch", outline.followUp)
        ]
    }
}

private struct WritingDockModeView: View {
    var snapshot: ResearchWorkbenchSnapshot

    var body: some View {
        WorkbenchPanel(
            title: "Writing Dock",
            status: snapshot.writingProject.status.displayName,
            systemImage: "doc.richtext"
        ) {
            let writingSourceScope = snapshot.writingProject.pendingPatches.first.flatMap {
                WorkbenchSourceScope.resolve($0)
            }
            KeyValueRows {
                KeyValueRow(label: "Project", value: snapshot.writingProject.name)
                KeyValueRow(label: "Kind", value: snapshot.writingProject.kind.displayName)
                KeyValueRow(label: "Root", value: snapshot.writingProject.rootPath, monospaced: true)
                KeyValueRow(
                    label: "Main file",
                    value: snapshot.writingProject.mainFilePath ?? "Needs selection",
                    monospaced: snapshot.writingProject.mainFilePath != nil
                )
                KeyValueRow(
                    label: "Bibliography",
                    value: snapshot.writingProject.bibliographyFilePaths.isEmpty
                        ? "Not detected"
                        : snapshot.writingProject.bibliographyFilePaths.joined(separator: ", "),
                    monospaced: !snapshot.writingProject.bibliographyFilePaths.isEmpty
                )
                if let writingSourceScope {
                    KeyValueRow(label: "Source scope", value: writingSourceScope.displayName)
                    if let selectionHash = writingSourceScope.selectionHash {
                        KeyValueRow(label: "Selection hash", value: selectionHash, monospaced: true)
                    }
                }
            }

            Picker("Target section", selection: writingTargetSectionBinding) {
                ForEach(snapshot.writingTargetSectionOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .disabled(snapshot.writingTargetSectionOptions.count <= 1 || snapshot.researchAPIBusy)
            .help("Choose where the next Writing Dock patch should be inserted in the linked manuscript")

            ForEach(snapshot.writingProject.pendingPatches) { patch in
                PatchPreviewRow(patch: patch)
            }

            if let actionPlan = snapshot.actionPlan {
                AgentActionPlanRow(actionPlan: actionPlan)
            }

            WorkbenchActionReadinessRow(readiness: snapshot.writingActionReadiness)

            Button {
                snapshot.chooseWritingProject()
            } label: {
                Label("Choose Writing Project", systemImage: "folder")
            }

            Button {
                Task {
                    await snapshot.prepareWritingActionPlan()
                }
            } label: {
                Label("Prepare Writing Patch", systemImage: "plus")
            }
            .disabled(!snapshot.writingActionReadiness.isReady || snapshot.researchAPIBusy)

            if !snapshot.writingActionPlans.isEmpty {
                ActionPlansSection(
                    title: "Action Plans",
                    actionPlans: snapshot.writingActionPlans,
                    snapshot: snapshot
                )
            } else {
                WorkbenchEmptyState(
                    systemImage: "text.badge.plus",
                    title: "No manuscript patch",
                    text: "Source provenance unavailable."
                )
            }
        }
    }

    private var writingTargetSectionBinding: Binding<String> {
        Binding(
            get: { snapshot.writingTargetSection },
            set: { snapshot.selectWritingTargetSection($0) }
        )
    }
}

private struct ActionPlansSection: View {
    var title: String
    var actionPlans: [AgentActionPlan]
    var snapshot: ResearchWorkbenchSnapshot
    var supportsLocalApply = true
    var supportsRemoteRun = false
    var supportsRecovery = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(actionPlans) { actionPlan in
                AgentActionPlanRow(
                    actionPlan: actionPlan,
                    isResearchActionBusy: snapshot.researchAPIBusy,
                    onApprove: {
                        Task<Void, Never> {
                            await snapshot.approve(actionPlan)
                        }
                    },
                    onReject: {
                        Task<Void, Never> {
                            await snapshot.reject(actionPlan)
                        }
                    },
                    onApply: supportsLocalApply ? {
                        Task<Void, Never> {
                            await snapshot.apply(actionPlan)
                        }
                    } : nil,
                    onRun: supportsRemoteRun ? {
                        Task<Void, Never> {
                            await snapshot.run(actionPlan)
                        }
                    } : nil,
                    onRecover: supportsRecovery ? { recoveryAction in
                        switch recoveryAction {
                        case .regenerate:
                            Task<Void, Never> {
                                await snapshot.regenerate(actionPlan)
                            }
                        case .viewDiff:
                            break
                        case .abandonLocalWrite:
                            snapshot.dismiss(actionPlan)
                        }
                    } : nil
                )
            }
        }
    }
}

private struct ResearchWorkbenchLocalState: View {
    var snapshot: ResearchWorkbenchSnapshot

    var body: some View {
        WorkbenchPanel(
            title: "Local State",
            status: "\(snapshot.taskSummaries.count) tasks",
            systemImage: "internaldrive"
        ) {
            HStack(spacing: 8) {
                WorkbenchStatusPill(
                    text: "\(snapshot.savedNoteCount) Bilin notes",
                    systemImage: "note.text",
                    tint: .secondary
                )
                WorkbenchStatusPill(
                    text: "\(snapshot.translationCount) translations",
                    systemImage: "character.bubble",
                    tint: .secondary
                )
            }

            if let translation = snapshot.currentTranslationMarkdown {
                WorkbenchPreviewBlock(title: "Selected translation", value: translation)
            }

            if !snapshot.researchSkills.isEmpty {
                KeyValueRow(
                    label: "Research skills",
                    value: snapshot.researchSkills.prefix(4).map(\.slug).joined(separator: ", ")
                )
            }

            KeyValueRow(label: "API endpoint", value: snapshot.researchAPIBaseURL, monospaced: true)

            if let backendLabel = snapshot.researchAPIHealthLabel {
                KeyValueRow(label: "API health", value: backendLabel)
            }

            KeyValueRow(label: "Workbench status", value: snapshot.researchWorkbenchStatus)

            HStack(spacing: 8) {
                Button {
                    snapshot.detectWorkspacePaths()
                } label: {
                    Label("Detect Local Apps", systemImage: "magnifyingglass")
                }
            }

            if !snapshot.detectedWorkspacePaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected Apps")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(snapshot.detectedWorkspacePaths) { record in
                        DetectedWorkspacePathRow(
                            record: record,
                            isConfigured: snapshot.isConfigured(record),
                            onUse: {
                                Task {
                                    await snapshot.useDetectedWorkspacePath(record)
                                }
                            }
                        )
                    }
                }
            }

            if let researchAPIError = snapshot.researchAPIError {
                WorkbenchPreviewBlock(title: "Research API", value: researchAPIError)
            }

            if let researchWorkbenchError = snapshot.researchWorkbenchError {
                WorkbenchPreviewBlock(title: "Research workbench", value: researchWorkbenchError)
            }

            if let workspaceConfigurationError = snapshot.workspaceConfigurationError {
                WorkbenchPreviewBlock(title: "Workspace config", value: workspaceConfigurationError)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(snapshot.taskSummaries, id: \.self) { task in
                    Label(task, systemImage: "circle.dotted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct WorkbenchPanel<Content: View>: View {
    var title: String
    var status: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                WorkbenchStatusPill(text: status, systemImage: "circle.fill", tint: .accentColor)
            }

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct KeyValueRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KeyValueRow: View {
    var label: String
    var value: String
    var monospaced = false

    var body: some View {
        let valuePresentation = WorkbenchValuePresentation.metadata(value: value)
        let copyAction = WorkbenchCopyAction.value(label: label, value: valuePresentation.value)
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(valuePresentation.value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .foregroundStyle(.primary)
                .lineLimit(valuePresentation.lineLimit)
                .textSelection(.enabled)
                .help(valuePresentation.hoverHelp)
                .contextMenu {
                    Button {
                        WorkbenchClipboard.copy(copyAction.value)
                    } label: {
                        Label(copyAction.title, systemImage: copyAction.systemImage)
                    }
                    .help(copyAction.help)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkbenchPreviewBlock: View {
    var title: String
    var value: String
    var monospaced = false
    var maxLines: Int? = 7

    var body: some View {
        let copyAction = WorkbenchCopyAction.preview(title: title, value: value)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
                .lineSpacing(2)
                .lineLimit(maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .contextMenu {
                    Button {
                        WorkbenchClipboard.copy(copyAction.value)
                    } label: {
                        Label(copyAction.title, systemImage: copyAction.systemImage)
                    }
                    .help(copyAction.help)
                }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }
}

struct WorkbenchValuePresentation: Equatable {
    var value: String
    var lineLimit: Int? = 2
    var hoverHelp: String

    static func metadata(value: String) -> WorkbenchValuePresentation {
        WorkbenchValuePresentation(
            value: value,
            hoverHelp: value
        )
    }
}

struct WorkbenchCopyAction: Equatable {
    var title: String
    var help: String
    var systemImage = "doc.on.doc"
    var value: String

    static func value(label: String, value: String) -> WorkbenchCopyAction {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = normalizedLabel.isEmpty ? "Copy Value" : "Copy \(normalizedLabel)"
        let help = normalizedLabel.isEmpty ? "Copy value" : "Copy \(normalizedLabel) value"
        return WorkbenchCopyAction(
            title: title,
            help: help,
            value: value
        )
    }

    static func preview(title: String, value: String) -> WorkbenchCopyAction {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = normalizedTitle.isEmpty ? "Copy Preview" : "Copy \(normalizedTitle)"
        return WorkbenchCopyAction(
            title: title,
            help: "Copy preview text",
            value: value
        )
    }
}

enum WorkbenchClipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct WorkbenchEmptyState: View {
    var systemImage: String
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }
}

struct WorkbenchActionReadiness: Hashable {
    var title: String
    var detail: String
    var systemImage: String
    var tintRole: TintRole
    var isReady: Bool

    enum TintRole: Hashable {
        case accent
        case secondary
        case warning
    }

    static let noteReady = WorkbenchActionReadiness(
        title: "Ready to prepare",
        detail: "Bilin will create an auditable Obsidian patch plan before writing.",
        systemImage: "checkmark.circle",
        tintRole: .accent,
        isReady: true
    )

    static let writingReady = WorkbenchActionReadiness(
        title: "Ready to prepare",
        detail: "Bilin will create an auditable Typst or TeX patch plan before writing.",
        systemImage: "checkmark.circle",
        tintRole: .accent,
        isReady: true
    )

    static let researchPlanReady = WorkbenchActionReadiness(
        title: "Ready to prepare",
        detail: "Bilin will create an auditable reading-outline action before generation.",
        systemImage: "checkmark.circle",
        tintRole: .accent,
        isReady: true
    )
}

struct ResearchWorkbenchSetupItem: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var systemImage: String
    var tintRole: WorkbenchActionReadiness.TintRole
    var action: ResearchWorkbenchSetupAction?

    var isReady: Bool {
        action == nil && tintRole == .accent
    }
}

enum ResearchWorkbenchSetupAction: Hashable {
    case refreshAPI
    case refreshWorkbench
    case indexResearchSkills
    case enableResearchSkill(ResearchSkill)
    case detectLocalApps
    case chooseBilinLibrary
    case chooseZoteroLibrary
    case useDetectedWorkspacePath(WorkspacePathRecord)
    case chooseObsidianVault
    case chooseWritingProject

    var title: String {
        switch self {
        case .refreshAPI:
            return "Check API"
        case .refreshWorkbench:
            return "Refresh Workbench"
        case .indexResearchSkills:
            return "Index Skills"
        case .enableResearchSkill:
            return "Enable Skill"
        case .detectLocalApps:
            return "Detect Local Apps"
        case .chooseBilinLibrary:
            return "Choose Library"
        case .chooseZoteroLibrary:
            return "Choose Zotero"
        case .useDetectedWorkspacePath(let record):
            switch record.kind {
            case .bilinLibrary:
                return "Use Detected Library"
            case .zoteroLibrary:
                return "Use Detected Zotero"
            case .obsidianVault:
                return "Use Detected Vault"
            case .writingProjectRoot:
                return "Use Detected Project"
            }
        case .chooseObsidianVault:
            return "Choose Vault"
        case .chooseWritingProject:
            return "Choose Project"
        }
    }

    var systemImage: String {
        switch self {
        case .refreshAPI, .refreshWorkbench, .indexResearchSkills:
            return "arrow.clockwise"
        case .enableResearchSkill:
            return "checkmark.seal"
        case .detectLocalApps:
            return "magnifyingglass"
        case .useDetectedWorkspacePath:
            return "checkmark"
        case .chooseBilinLibrary, .chooseZoteroLibrary, .chooseObsidianVault, .chooseWritingProject:
            return "folder"
        }
    }

    var requiresIdleResearchAction: Bool {
        switch self {
        case .refreshAPI, .refreshWorkbench, .indexResearchSkills, .enableResearchSkill:
            return true
        case .detectLocalApps,
             .chooseBilinLibrary,
             .chooseZoteroLibrary,
             .useDetectedWorkspacePath,
             .chooseObsidianVault,
             .chooseWritingProject:
            return false
        }
    }

    var confirmationTitle: String? {
        switch self {
        case .enableResearchSkill(let skill):
            return "Enable \(skill.title)?"
        case .refreshAPI,
             .refreshWorkbench,
             .indexResearchSkills,
             .detectLocalApps,
             .chooseBilinLibrary,
             .chooseZoteroLibrary,
             .useDetectedWorkspacePath,
             .chooseObsidianVault,
             .chooseWritingProject:
            return nil
        }
    }

    var confirmationMessage: String? {
        switch self {
        case .enableResearchSkill(let skill):
            return skill.enableConfirmationMessage
        case .refreshAPI,
             .refreshWorkbench,
             .indexResearchSkills,
             .detectLocalApps,
             .chooseBilinLibrary,
             .chooseZoteroLibrary,
             .useDetectedWorkspacePath,
             .chooseObsidianVault,
             .chooseWritingProject:
            return nil
        }
    }
}

private struct WorkbenchActionReadinessRow: View {
    var readiness: WorkbenchActionReadiness

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: readiness.systemImage)
                .foregroundStyle(readiness.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(readiness.title)
                    .font(.caption.weight(.semibold))
                Text(readiness.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(readiness.tint.opacity(0.08))
    }
}

private extension WorkbenchActionReadiness {
    var tint: Color {
        tintRole.color
    }
}

private extension ResearchWorkbenchSetupItem {
    var tint: Color {
        tintRole.color
    }
}

private extension WorkbenchActionReadiness.TintRole {
    var color: Color {
        switch self {
        case .accent:
            return .accentColor
        case .secondary:
            return .secondary
        case .warning:
            return .orange
        }
    }
}

struct WorkbenchStatusPill: View {
    var text: String
    var systemImage: String
    var tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .foregroundStyle(tint)
            .background(tint.opacity(0.11), in: Capsule())
    }
}

private struct PatchPreviewRow: View {
    var patch: PendingFilePatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(patch.kind.displayName, systemImage: "doc.badge.gearshape")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                WorkbenchStatusPill(
                    text: patch.status.displayName,
                    systemImage: "circle.fill",
                    tint: patch.status.tint
                )
            }

            KeyValueRow(label: "Target", value: patch.targetPath, monospaced: true)

            if let targetAnchor = patch.targetAnchor {
                KeyValueRow(label: "Anchor", value: targetAnchor, monospaced: true)
            }

            if let baseFileHash = patch.baseFileHash {
                KeyValueRow(label: "Base hash", value: baseFileHash, monospaced: true)
            }

            if let appliedFileHash = patch.appliedFileHash {
                KeyValueRow(label: "Applied hash", value: appliedFileHash, monospaced: true)
            }

            if let conflict = patch.conflict {
                WorkbenchPreviewBlock(
                    title: "Conflict",
                    value: [
                        conflict.message,
                        conflict.expectedHash.map { "Expected: \($0)" },
                        conflict.observedHash.map { "Observed: \($0)" }
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n"),
                    monospaced: true,
                    maxLines: 8
                )
            }

            Text(patch.previewMarkdown ?? patch.patchText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(5)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct OutlineItemRow: View {
    var item: ReadingOutlineItem

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.importance == .high ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    WorkbenchStatusPill(
                        text: item.kind.displayName,
                        systemImage: "circle.fill",
                        tint: item.importance == .high ? .accentColor : .secondary
                    )
                }

                Text(item.summaryMarkdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }
}

private struct AgentActionPlanRow: View {
    var actionPlan: AgentActionPlan
    var isResearchActionBusy = false
    var onApprove: (() -> Void)?
    var onReject: (() -> Void)?
    var onApply: (() -> Void)?
    var onRun: (() -> Void)?
    var onRecover: ((AgentActionPlanRecoveryAction) -> Void)?
    @State private var showsDiffPreview = false

    var body: some View {
        let targetFreshness = AgentActionPlanTargetFreshness.evaluate(actionPlan)
        let availableActions = AgentActionPlanRowActions.resolve(
            actionPlan,
            targetFreshness: targetFreshness,
            hasApprove: onApprove != nil,
            hasReject: onReject != nil,
            hasApply: onApply != nil,
            hasRun: onRun != nil,
            hasRecover: onRecover != nil,
            isResearchActionBusy: isResearchActionBusy
        )
        let statusPresentation = AgentActionPlanStatusPresentation.resolve(actionPlan.status)
        let recoveryPresentation = AgentActionPlanRecoveryPresentation.resolve(
            actionPlan,
            targetFreshness: targetFreshness
        )
        let recoveryFileActions = AgentActionPlanRecoveryFileActions.resolve(
            actionPlan,
            targetFreshness: targetFreshness
        )
        let targetFreshnessPreview = AgentActionPlanTargetFreshnessPreview.resolve(
            actionPlan,
            targetFreshness: targetFreshness
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(actionPlan.title, systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                WorkbenchStatusPill(
                    text: actionPlan.status.displayName,
                    systemImage: statusPresentation.systemImage,
                    tint: statusPresentation.tint
                )
            }

            Text(actionPlan.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(actionPlan.steps) { step in
                    Label(step.title, systemImage: step.kind.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if let auditMetadata = AgentActionPlanAuditMetadata.resolve(actionPlan) {
                KeyValueRows {
                    ForEach(auditMetadata.rows) { row in
                        KeyValueRow(label: row.label, value: row.value, monospaced: row.monospaced)
                    }
                }
            }

            if let resultMetadata = AgentActionPlanResultMetadata.resolve(actionPlan) {
                KeyValueRows {
                    ForEach(resultMetadata.rows) { row in
                        KeyValueRow(label: row.label, value: row.value, monospaced: row.monospaced)
                    }
                }
            }

            let resultActions = AgentActionPlanResultFileActions.resolve(actionPlan)
            if !resultActions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(resultActions) { resultAction in
                        Button {
                            resultAction.perform()
                        } label: {
                            Label(resultAction.title, systemImage: resultAction.systemImage)
                        }
                        .help(resultAction.help)
                    }
                }
            }

            if let errorMessage = actionPlan.errorMessage, !errorMessage.isEmpty {
                WorkbenchPreviewBlock(title: "Error", value: errorMessage)
            }

            if let recoverySummary = actionPlan.preview?["recovery_summary"], !recoverySummary.isEmpty {
                WorkbenchPreviewBlock(title: "Recovery", value: recoverySummary)
            }

            if let auditPreview = AgentActionPlanAuditPreview.resolve(actionPlan) {
                WorkbenchPreviewBlock(
                    title: auditPreview.title,
                    value: auditPreview.value,
                    monospaced: true,
                    maxLines: auditPreview.maxLines
                )
            }

            if let targetFreshnessPreview {
                WorkbenchPreviewBlock(
                    title: targetFreshnessPreview.title,
                    value: targetFreshnessPreview.value,
                    monospaced: true,
                    maxLines: 8
                )
            }

            if let recoveryPresentation {
                Text(recoveryPresentation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !recoveryFileActions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(recoveryFileActions) { recoveryFileAction in
                            Button {
                                recoveryFileAction.perform()
                            } label: {
                                Label(recoveryFileAction.title, systemImage: recoveryFileAction.systemImage)
                            }
                            .help(recoveryFileAction.help)
                        }
                    }
                }

                HStack(spacing: 8) {
                    if availableActions.showsRegenerate, let onRecover {
                        Button {
                            onRecover(.regenerate)
                        } label: {
                            Label(recoveryPresentation.regenerateTitle, systemImage: "arrow.clockwise")
                        }
                    }
                    if availableActions.showsContextPreview {
                        Button {
                            showsDiffPreview.toggle()
                            onRecover?(.viewDiff)
                        } label: {
                            Label(
                                recoveryPresentation.contextPreviewToggleTitle(isExpanded: showsDiffPreview),
                                systemImage: recoveryPresentation.contextPreviewToggleSystemImage(isExpanded: showsDiffPreview)
                            )
                        }
                        .help(recoveryPresentation.contextPreviewToggleHelp(isExpanded: showsDiffPreview))
                    }
                    if availableActions.showsAbandon, let onRecover {
                        Button {
                            onRecover(.abandonLocalWrite)
                        } label: {
                            Label(recoveryPresentation.abandonTitle, systemImage: "xmark.circle")
                        }
                    }
                }
            }

            if showsDiffPreview, let recoveryPresentation {
                WorkbenchPreviewBlock(
                    title: recoveryPresentation.contextPreviewTitle,
                    value: Self.contextPreview(
                        for: actionPlan,
                        kind: recoveryPresentation.contextPreviewKind
                    ),
                    monospaced: true,
                    maxLines: 28
                )
            }

            if availableActions.showsApprove || availableActions.showsReject {
                HStack(spacing: 8) {
                    if availableActions.showsApprove, let onApprove {
                        Button {
                            onApprove()
                        } label: {
                            Label(
                                AgentActionPlanApprovalPolicy.approveButtonTitle(for: actionPlan),
                                systemImage: "checkmark"
                            )
                        }
                        .help(AgentActionPlanApprovalPolicy.approveButtonHelp(for: actionPlan))
                    }
                    if availableActions.showsReject, let onReject {
                        Button {
                            onReject()
                        } label: {
                            Label(
                                AgentActionPlanApprovalPolicy.rejectButtonTitle(for: actionPlan),
                                systemImage: "xmark"
                            )
                        }
                        .help(AgentActionPlanApprovalPolicy.rejectButtonHelp(for: actionPlan))
                    }
                }
            }
            if availableActions.showsApply,
               let onApply,
               let applyButtonTitle = AgentActionPlanLocalExecutionPolicy.applyButtonTitle(for: actionPlan) {
                Button {
                    onApply()
                } label: {
                    Label(applyButtonTitle, systemImage: "square.and.pencil")
                }
                .help(AgentActionPlanLocalExecutionPolicy.applyButtonHelp(for: actionPlan) ?? applyButtonTitle)
            }
            if availableActions.showsRun,
               let onRun,
               let runButtonTitle = AgentActionPlanRemoteExecutionPolicy.runButtonTitle(for: actionPlan) {
                Button {
                    onRun()
                } label: {
                    Label(runButtonTitle, systemImage: "play.circle")
                }
                .help(AgentActionPlanRemoteExecutionPolicy.runButtonHelp(for: actionPlan) ?? runButtonTitle)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private static func contextPreview(
        for actionPlan: AgentActionPlan,
        kind: AgentActionPlanRecoveryPresentation.ContextPreviewKind
    ) -> String {
        switch kind {
        case .actionContext:
            return actionContextPreview(for: actionPlan)
        case .diff:
            return diffPreview(for: actionPlan)
        }
    }

    private static func actionContextPreview(for actionPlan: AgentActionPlan) -> String {
        let sections = [
            keyValuePreview(title: "Payload", values: actionPlan.payload),
            keyValuePreview(title: "Preview", values: actionPlan.preview),
            keyValuePreview(title: "Result", values: actionPlan.result),
            keyValuePreview(title: "Error", values: actionPlan.error)
        ].flatMap { $0 }
        guard !sections.isEmpty else {
            return "No action context recorded."
        }
        return sections.joined(separator: "\n")
    }

    private static func keyValuePreview(title: String, values: [String: String]?) -> [String] {
        guard let values, !values.isEmpty else {
            return []
        }
        return ["[\(title)]"] + values
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
    }

    private static func diffPreview(for actionPlan: AgentActionPlan) -> String {
        AgentActionPlanDiffPreview.render(actionPlan)
    }
}

struct AgentActionPlanDiffPreview: Equatable {
    static func render(
        _ actionPlan: AgentActionPlan,
        fileReader: (String) -> String? = readFileText
    ) -> String {
        let targetPath = actionPlan.targetFilePath
        let currentText = targetPath.flatMap(fileReader) ?? ""
        let observedHash = LocalFilePatchExecutor.contentHash(for: currentText)
        let expectedHash = actionPlan.expectedBaseFileHash ?? "not recorded"
        let patch = plannedPatch(for: actionPlan)
        let marker = markerPreview(for: actionPlan, targetPath: targetPath)
        let targetLabel = targetPath
            ?? actionPlan.payload["target_note"]
            ?? actionPlan.payload["targetNote"]
            ?? "not recorded"

        return [
            "Target: \(targetLabel)",
            "Expected base hash: \(expectedHash)",
            "Observed current hash: \(observedHash)",
            "Current file length: \(currentText.utf8.count) bytes",
            "",
            "--- Current target context",
            currentContext(for: currentText, actionPlan: actionPlan, patch: patch),
            "",
            "+++ Planned local write",
            marker.start,
            patch,
            marker.end
        ].joined(separator: "\n")
    }

    private static func readFileText(_ path: String) -> String? {
        try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    private static func plannedPatch(for actionPlan: AgentActionPlan) -> String {
        actionPlan.preview?["patch"]
            ?? actionPlan.payload["patch"]
            ?? actionPlan.payload["preview_markdown"]
            ?? actionPlan.payload["previewMarkdown"]
            ?? "No patch preview recorded."
    }

    private static func currentContext(
        for currentText: String,
        actionPlan: AgentActionPlan,
        patch: String
    ) -> String {
        guard !currentText.isEmpty else {
            return "(target file is empty or unavailable)"
        }

        let lines = currentText.components(separatedBy: .newlines)
        let focusLineIndex = focusLineIndex(
            in: lines,
            searchTerms: searchTerms(for: actionPlan, patch: patch)
        )
        let window = contextWindow(lineCount: lines.count, focusLineIndex: focusLineIndex)
        return numberedLines(lines, in: window)
    }

    private static func searchTerms(for actionPlan: AgentActionPlan, patch: String) -> [String] {
        let payloadTerms = [
            actionPlan.payload["target_anchor"],
            actionPlan.payload["targetAnchor"],
            actionPlan.payload["block_anchor"],
            actionPlan.payload["blockAnchor"]
        ]
        .compactMap(trimmed)

        let patchTerms = patch
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.count >= 8 else { return nil }
                guard !line.hasPrefix("<!--"), !line.hasPrefix("//"), !line.hasPrefix("%") else {
                    return nil
                }
                return String(line.prefix(80))
            }

        return payloadTerms + patchTerms
    }

    private static func focusLineIndex(in lines: [String], searchTerms: [String]) -> Int? {
        for term in searchTerms {
            if let index = lines.firstIndex(where: { line in
                line.localizedCaseInsensitiveContains(term)
            }) {
                return index
            }
        }
        return nil
    }

    private static func contextWindow(lineCount: Int, focusLineIndex: Int?) -> Range<Int> {
        guard lineCount > 0 else { return 0..<0 }
        let maxVisibleLines = 14
        guard lineCount > maxVisibleLines else {
            return 0..<lineCount
        }
        let focus = focusLineIndex ?? max(0, lineCount - 1)
        let lower = max(0, focus - 6)
        let upper = min(lineCount, lower + maxVisibleLines)
        return lower..<upper
    }

    private static func numberedLines(_ lines: [String], in range: Range<Int>) -> String {
        range
            .map { index in
                let number = String(index + 1).leftPadded(to: 4)
                return "\(number) | \(lines[index])"
            }
            .joined(separator: "\n")
    }

    private static func markerPreview(
        for actionPlan: AgentActionPlan,
        targetPath: String?
    ) -> (start: String, end: String) {
        let pathExtension = targetPath
            .map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
            ?? ""
        switch pathExtension {
        case "tex":
            return (
                "% ilios-action-plan:\(actionPlan.id)",
                "% /ilios-action-plan:\(actionPlan.id)"
            )
        case "typ":
            return (
                "// ilios-action-plan:\(actionPlan.id)",
                "// /ilios-action-plan:\(actionPlan.id)"
            )
        default:
            return (
                "<!-- ilios-action-plan:\(actionPlan.id) -->",
                "<!-- /ilios-action-plan:\(actionPlan.id) -->"
            )
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        guard count < width else { return self }
        return String(repeating: " ", count: width - count) + self
    }
}

struct AgentActionPlanStatusPresentation: Equatable {
    var systemImage: String
    var tintRole: WorkbenchActionReadiness.TintRole

    var tint: Color {
        tintRole.color
    }

    static func resolve(_ status: AgentActionStatus) -> AgentActionPlanStatusPresentation {
        switch status {
        case .draft:
            return AgentActionPlanStatusPresentation(systemImage: "circle.dashed", tintRole: .secondary)
        case .pendingApproval:
            return AgentActionPlanStatusPresentation(systemImage: "exclamationmark.shield", tintRole: .accent)
        case .approved:
            return AgentActionPlanStatusPresentation(systemImage: "checkmark.shield", tintRole: .accent)
        case .queued:
            return AgentActionPlanStatusPresentation(systemImage: "clock", tintRole: .accent)
        case .rejected:
            return AgentActionPlanStatusPresentation(systemImage: "xmark.circle", tintRole: .warning)
        case .cancelled:
            return AgentActionPlanStatusPresentation(systemImage: "pause.circle", tintRole: .warning)
        case .running:
            return AgentActionPlanStatusPresentation(systemImage: "play.circle", tintRole: .accent)
        case .succeeded:
            return AgentActionPlanStatusPresentation(systemImage: "checkmark.circle.fill", tintRole: .accent)
        case .failed:
            return AgentActionPlanStatusPresentation(systemImage: "exclamationmark.triangle.fill", tintRole: .warning)
        }
    }
}

struct AgentActionPlanRecoveryPresentation: Equatable {
    enum ContextPreviewKind: Equatable {
        case actionContext
        case diff
    }

    var message: String
    var regenerateTitle: String
    var contextPreviewButtonTitle: String
    var contextPreviewTitle: String
    var contextPreviewKind: ContextPreviewKind
    var abandonTitle: String

    func contextPreviewToggleTitle(isExpanded: Bool) -> String {
        guard isExpanded else { return contextPreviewButtonTitle }
        if contextPreviewButtonTitle.hasPrefix("View ") {
            return "Hide " + String(contextPreviewButtonTitle.dropFirst("View ".count))
        }
        return "Hide Preview"
    }

    func contextPreviewToggleSystemImage(isExpanded: Bool) -> String {
        isExpanded ? "chevron.up.square" : "doc.text.magnifyingglass"
    }

    func contextPreviewToggleHelp(isExpanded: Bool) -> String {
        if isExpanded {
            return "Hide the recovery context preview."
        }
        switch contextPreviewKind {
        case .actionContext:
            return "Inspect the recorded action payload before deciding whether to regenerate or dismiss this attempt."
        case .diff:
            return "Compare the current target file context with the planned local write before regenerating or abandoning this attempt."
        }
    }

    static func resolve(
        _ actionPlan: AgentActionPlan,
        targetFreshness: AgentActionPlanTargetFreshness = .notTracked
    ) -> AgentActionPlanRecoveryPresentation? {
        guard actionPlan.status == .failed || targetFreshness.blocksLocalWrite(for: actionPlan.status) else {
            return nil
        }

        if isFileConflict(actionPlan, targetFreshness: targetFreshness) {
            return AgentActionPlanRecoveryPresentation(
                message: "The target file changed after preview. Regenerate the patch, inspect the current diff, or abandon this local write attempt.",
                regenerateTitle: "Regenerate Patch",
                contextPreviewButtonTitle: "View Current Diff",
                contextPreviewTitle: "Diff Preview",
                contextPreviewKind: .diff,
                abandonTitle: "Abandon Write"
            )
        }

        switch actionPlan.kind {
        case .generateResearchOutline:
            return AgentActionPlanRecoveryPresentation(
                message: "The outline action did not finish. Regenerate the outline, inspect the action payload, or dismiss this attempt.",
                regenerateTitle: "Regenerate Outline",
                contextPreviewButtonTitle: "View Payload",
                contextPreviewTitle: "Action Payload",
                contextPreviewKind: .actionContext,
                abandonTitle: "Dismiss Action"
            )
        case .downloadPaper, .importLibrary:
            return AgentActionPlanRecoveryPresentation(
                message: "The import did not finish. Regenerate the import plan, inspect the action payload, or dismiss this attempt.",
                regenerateTitle: "Regenerate Import Plan",
                contextPreviewButtonTitle: "View Payload",
                contextPreviewTitle: "Action Payload",
                contextPreviewKind: .actionContext,
                abandonTitle: "Dismiss Action"
            )
        case .writeObsidian, .notePatch, .editManuscript, .writingPatch:
            return AgentActionPlanRecoveryPresentation(
                message: "The write did not finish. Regenerate the patch if the source context changed, inspect the target file, or abandon this local write attempt.",
                regenerateTitle: "Regenerate Patch",
                contextPreviewButtonTitle: "View Current Diff",
                contextPreviewTitle: "Diff Preview",
                contextPreviewKind: .diff,
                abandonTitle: "Abandon Write"
            )
        case .installSkill, .enableSkill, .runExternalTool, .providerCall, .writeLibraryBundle, .exportArticle, .custom:
            return AgentActionPlanRecoveryPresentation(
                message: "The action did not finish. Regenerate the action plan, inspect the action payload, or dismiss this attempt.",
                regenerateTitle: "Regenerate Action",
                contextPreviewButtonTitle: "View Payload",
                contextPreviewTitle: "Action Payload",
                contextPreviewKind: .actionContext,
                abandonTitle: "Dismiss Action"
            )
        }
    }

    private static func isFileConflict(
        _ actionPlan: AgentActionPlan,
        targetFreshness: AgentActionPlanTargetFreshness
    ) -> Bool {
        if targetFreshness.blocksLocalWrite(for: actionPlan.status) {
            return true
        }
        if actionPlan.error?["code"] == "file_changed_since_preview" {
            return true
        }
        if actionPlan.error?["expected_base_file_hash"] != nil || actionPlan.error?["observed_file_hash"] != nil {
            return true
        }
        let message = [
            actionPlan.errorMessage,
            actionPlan.error?["message"],
            actionPlan.error?["code"]
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        return message.localizedCaseInsensitiveContains("changed since preview")
            || message.localizedCaseInsensitiveContains("base hash")
    }
}

struct AgentActionPlanAuditMetadata: Equatable {
    struct Row: Equatable, Identifiable {
        var label: String
        var value: String
        var monospaced = false

        var id: String { label }
    }

    var rows: [Row]

    static func resolve(_ actionPlan: AgentActionPlan) -> AgentActionPlanAuditMetadata? {
        var rows: [Row] = []

        if !actionPlan.requestedPermissions.isEmpty {
            rows.append(Row(
                label: "Requested permissions",
                value: actionPlan.requestedPermissions.displayListLabel
            ))
        }

        if let targetPath = trimmed(actionPlan.targetFilePath) {
            rows.append(Row(label: "Target file", value: targetPath, monospaced: true))
        } else if let targetNote = firstValue(keys: ["target_note", "targetNote"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Target note", value: targetNote))
        }

        if let zoteroItemId = firstValue(keys: ["zotero_item_id", "zoteroItemId"], sources: [actionPlan.payload]) {
            let zoteroKey = firstValue(keys: ["zotero_key", "zoteroKey"], sources: [actionPlan.payload])
            let label = zoteroKey.map { "\(zoteroItemId) · \($0)" } ?? zoteroItemId
            rows.append(Row(label: "Zotero item", value: label, monospaced: true))
        }

        if let arxivIdentifier = firstValue(keys: ["arxiv_id", "arxivId"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "arXiv", value: arxivIdentifier, monospaced: true))
        }

        if let libraryPath = firstValue(keys: ["local_library_path", "target_library_path"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Target library", value: libraryPath, monospaced: true))
        }

        if let baseHash = trimmed(actionPlan.expectedBaseFileHash) {
            rows.append(Row(label: "Base hash", value: baseHash, monospaced: true))
        }

        if actionPlan.kind == .writeObsidian || actionPlan.kind == .notePatch {
            rows.append(contentsOf: noteBridgeRows(actionPlan))
        }

        if actionPlan.kind == .editManuscript || actionPlan.kind == .writingPatch {
            rows.append(contentsOf: writingPatchRows(actionPlan))
        }

        if actionPlan.kind == .generateResearchOutline {
            rows.append(contentsOf: researchOutlineRows(actionPlan))
        }

        if let recoveryFrom = firstValue(
            keys: ["recovering_from_action_plan_id", "recoveringFromActionPlanId"],
            sources: [actionPlan.payload, actionPlan.preview]
        ) {
            rows.append(Row(label: "Recovery from", value: recoveryFrom, monospaced: true))
        }

        if let strategy = firstValue(
            keys: ["recovery_patch_strategy", "recoveryPatchStrategy"],
            sources: [actionPlan.payload, actionPlan.preview]
        ) {
            rows.append(Row(label: "Recovery strategy", value: recoveryStrategyLabel(strategy)))
        }

        if let previousBaseHash = firstValue(
            keys: ["previous_base_file_hash", "previousBaseFileHash"],
            sources: [actionPlan.payload, actionPlan.preview]
        ) {
            rows.append(Row(label: "Previous base hash", value: previousBaseHash, monospaced: true))
        }

        if let observedHash = firstValue(
            keys: ["observed_file_hash", "observedFileHash"],
            sources: [actionPlan.payload, actionPlan.preview]
        ) {
            rows.append(Row(label: "Observed file hash", value: observedHash, monospaced: true))
        }

        if let recoveryTarget = firstValue(
            keys: ["recovery_target_path", "recovery_target_note", "recoveryTargetPath", "recoveryTargetNote"],
            sources: [actionPlan.payload, actionPlan.preview]
        ) {
            rows.append(Row(label: "Recovery target", value: recoveryTarget, monospaced: true))
        }

        if let recoveredAt = firstValue(
            keys: ["recovered_at", "recoveredAt"],
            sources: [actionPlan.payload, actionPlan.preview]
        ) {
            rows.append(Row(label: "Recovered at", value: recoveredAt))
        }

        guard !rows.isEmpty else {
            return nil
        }
        return AgentActionPlanAuditMetadata(rows: rows)
    }

    private static func noteBridgeRows(_ actionPlan: AgentActionPlan) -> [Row] {
        var rows: [Row] = []

        if let articleRevision = firstValue(
            keys: ["article_revision_id", "articleRevisionId"],
            sources: [actionPlan.payload]
        ) {
            rows.append(Row(label: "Article revision", value: articleRevision, monospaced: true))
        }

        if let blockUid = firstValue(keys: ["block_uid", "blockUid"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Source block", value: blockUid, monospaced: true))
        }

        if let blockAnchor = firstValue(keys: ["block_anchor", "blockAnchor"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Block anchor", value: blockAnchor, monospaced: true))
        }

        if let targetNote = firstValue(keys: ["target_note", "targetNote"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Markdown note", value: targetNote, monospaced: true))
        }

        if let vaultPath = firstValue(keys: ["target_vault_path", "vault_path", "targetVaultPath", "vaultPath"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Obsidian vault", value: vaultPath, monospaced: true))
        }

        if let selectedTextHash = firstValue(
            keys: ["selected_text_hash", "selectedTextHash"],
            sources: [actionPlan.payload]
        ) {
            rows.append(Row(label: "Source scope", value: "Selected excerpt"))
            rows.append(Row(label: "Selection hash", value: selectedTextHash, monospaced: true))
        } else if firstValue(keys: ["source_markdown", "sourceMarkdown"], sources: [actionPlan.payload]) != nil {
            rows.append(Row(label: "Source scope", value: "Whole block"))
        }

        if firstValue(keys: ["translation_markdown", "translationMarkdown"], sources: [actionPlan.payload]) != nil {
            rows.append(Row(label: "Translation", value: "Included"))
        }

        if let calloutType = firstValue(keys: ["callout_type", "calloutType"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Callout", value: calloutType))
        }

        return rows
    }

    private static func recoveryStrategyLabel(_ value: String) -> String {
        switch value {
        case "rebase_on_current_target":
            return "Rebase on current target"
        default:
            let words = value
                .replacingOccurrences(of: "-", with: "_")
                .split(separator: "_")
                .map(String.init)
            guard !words.isEmpty else { return value }
            return words.enumerated().map { index, word in
                index == 0 ? word.capitalized : word
            }.joined(separator: " ")
        }
    }

    private static func writingPatchRows(_ actionPlan: AgentActionPlan) -> [Row] {
        var rows: [Row] = []

        if let articleRevision = firstValue(
            keys: ["article_revision_id", "articleRevisionId"],
            sources: [actionPlan.payload]
        ) {
            rows.append(Row(label: "Article revision", value: articleRevision, monospaced: true))
        }

        if let blockUid = firstValue(keys: ["block_uid", "blockUid"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Source block", value: blockUid, monospaced: true))
        }

        if let selectedTextHash = firstValue(
            keys: ["selected_text_hash", "selectedTextHash"],
            sources: [actionPlan.payload]
        ) {
            rows.append(Row(label: "Source scope", value: "Selected excerpt"))
            rows.append(Row(label: "Selection hash", value: selectedTextHash, monospaced: true))
        } else if firstValue(keys: ["source_markdown", "sourceMarkdown"], sources: [actionPlan.payload]) != nil {
            rows.append(Row(label: "Source scope", value: "Whole block"))
        }

        if let sectionPath = jsonStringList(actionPlan.payload["target_section_path"]), !sectionPath.isEmpty {
            rows.append(Row(label: "Target section", value: sectionPath.joined(separator: " > ")))
        }

        if let targetAnchor = firstValue(keys: ["target_anchor", "targetAnchor"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Target anchor", value: targetAnchor, monospaced: true))
        }

        if let insertionMode = firstValue(keys: ["insertion_mode", "insertionMode"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Insertion mode", value: insertionMode))
        }

        if let insertionLine = firstValue(keys: ["insertion_line", "insertionLine"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Insertion line", value: insertionLine, monospaced: true))
        }

        if let bibliographyPaths = jsonStringList(actionPlan.payload["bibliography_paths"]), !bibliographyPaths.isEmpty {
            rows.append(Row(label: "Bibliography", value: bibliographyPaths.joined(separator: "\n"), monospaced: true))
        }

        return rows
    }

    private static func researchOutlineRows(_ actionPlan: AgentActionPlan) -> [Row] {
        var rows: [Row] = []

        if let articleRevision = firstValue(
            keys: ["article_revision_id", "articleRevisionId"],
            sources: [actionPlan.payload]
        ) {
            rows.append(Row(label: "Article revision", value: articleRevision, monospaced: true))
        }

        if let topic = firstValue(keys: ["topic"], sources: [actionPlan.payload]) {
            rows.append(Row(label: "Topic", value: topic))
        }

        if let skillProvenance = jsonObject(actionPlan.payload["skill_provenance"]) {
            let skillSlug = trimmed(skillProvenance["skill_slug"] as? String)
                ?? trimmed(skillProvenance["skillSlug"] as? String)
            let version = trimmed(skillProvenance["version"] as? String)
            let source = trimmed(skillProvenance["source"] as? String)
            let label = [skillSlug, version].compactMap { $0 }.joined(separator: " ")
            if !label.isEmpty {
                rows.append(Row(label: "Research skill", value: label, monospaced: true))
            }
            if let source {
                rows.append(Row(label: "Skill source", value: source, monospaced: true))
            }
        } else if let skillSlug = firstValue(
            keys: ["skill_slug", "skillSlug"],
            sources: [actionPlan.payload]
        ) {
            rows.append(Row(label: "Research skill", value: skillSlug, monospaced: true))
        }

        if let candidatePapers = jsonArray(actionPlan.payload["candidate_papers"]) {
            rows.append(Row(label: "Candidate papers", value: String(candidatePapers.count)))
            let titles = candidatePapers
                .compactMap { $0 as? [String: Any] }
                .compactMap { candidateTitle($0) }
                .prefix(3)
            let summary = titles.joined(separator: "\n")
            if !summary.isEmpty {
                rows.append(Row(label: "Candidate titles", value: summary))
            }
        }

        if let payload = jsonObject(actionPlan.payload["payload"]) {
            if let visibleBlocks = payload["visible_blocks"] as? [Any] {
                rows.append(Row(label: "Reader blocks", value: String(visibleBlocks.count)))
            }
            if let selectedBlock = trimmed(payload["selected_block_uid"] as? String) {
                rows.append(Row(label: "Selected block", value: selectedBlock, monospaced: true))
            }
        }

        return rows
    }

    private static func firstValue(
        keys: [String],
        sources: [[String: String]?]
    ) -> String? {
        for source in sources {
            guard let source else { continue }
            for key in keys {
                if let value = trimmed(source[key]) {
                    return value
                }
            }
        }
        return nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func jsonObject(_ value: String?) -> [String: Any]? {
        guard let value = trimmed(value),
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func jsonArray(_ value: String?) -> [Any]? {
        guard let value = trimmed(value),
              let data = value.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return nil
        }
        return array
    }

    private static func jsonStringList(_ value: String?) -> [String]? {
        jsonArray(value)?.compactMap { item in
            trimmed(item as? String)
        }
    }

    private static func candidateTitle(_ candidate: [String: Any]) -> String? {
        if let metadata = candidate["metadata"] as? [String: Any],
           let title = trimmed(metadata["title"] as? String) {
            return title
        }
        return trimmed(candidate["title"] as? String)
            ?? trimmed(candidate["paper_title"] as? String)
            ?? trimmed(candidate["paperTitle"] as? String)
    }
}

struct AgentActionPlanResultMetadata: Equatable {
    struct Row: Equatable, Identifiable {
        var label: String
        var value: String
        var monospaced = false

        var id: String { label }
    }

    var rows: [Row]

    static func resolve(_ actionPlan: AgentActionPlan) -> AgentActionPlanResultMetadata? {
        guard let result = actionPlan.result else {
            return nil
        }

        var rows: [Row] = []

        if let targetPath = trimmed(result["target_path"]) {
            rows.append(Row(label: "Applied file", value: targetPath, monospaced: true))
        }
        if let bundlePath = trimmed(result["bundle_path"]) {
            rows.append(Row(label: "Import bundle", value: bundlePath, monospaced: true))
        }
        if let metadataPath = trimmed(result["metadata_path"]) {
            rows.append(Row(label: "Metadata file", value: metadataPath, monospaced: true))
        }
        if let bytes = trimmed(result["bytes"]) {
            rows.append(Row(label: "Bytes", value: bytes))
        }
        if let copiedAttachments = trimmed(result["copied_attachment_count"]) {
            rows.append(Row(label: "Copied attachments", value: copiedAttachments))
        }
        if let missingAttachments = trimmed(result["missing_attachment_count"]) {
            rows.append(Row(label: "Missing attachments", value: missingAttachments))
        }
        if let alreadyPresent = trimmed(result["already_present"]) {
            rows.append(Row(label: "Already present", value: alreadyPresent))
        }
        if let baseFileHash = trimmed(result["base_file_hash"]) {
            rows.append(Row(label: "Base file hash", value: baseFileHash, monospaced: true))
        }
        if let appliedFileHash = trimmed(result["applied_file_hash"]) {
            rows.append(Row(label: "Applied file hash", value: appliedFileHash, monospaced: true))
        }

        guard !rows.isEmpty else {
            return nil
        }
        return AgentActionPlanResultMetadata(rows: rows)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct AgentActionPlanResultFileAction: Hashable, Identifiable {
    enum Kind: String, Hashable {
        case openFile
        case revealInFinder
    }

    var kind: Kind
    var title: String
    var systemImage: String
    var path: String

    var id: String {
        "\(kind.rawValue):\(path)"
    }

    var help: String {
        switch kind {
        case .openFile:
            return "Open \(path)"
        case .revealInFinder:
            return "Reveal \(path) in Finder"
        }
    }

    func perform() {
        switch kind {
        case .openFile:
            WorkbenchFileTargetActions.open(path: path)
        case .revealInFinder:
            WorkbenchFileTargetActions.reveal(path: path)
        }
    }
}

struct AgentActionPlanResultFileActions: Equatable {
    static func resolve(_ actionPlan: AgentActionPlan) -> [AgentActionPlanResultFileAction] {
        guard actionPlan.status == .succeeded else {
            return []
        }
        guard let result = actionPlan.result else {
            return []
        }

        switch actionPlan.kind {
        case .writeObsidian, .notePatch, .editManuscript, .writingPatch:
            guard let targetPath = trimmed(result["target_path"]) else {
                return []
            }
            return [
                AgentActionPlanResultFileAction(
                    kind: .openFile,
                    title: "Open File",
                    systemImage: "doc.text.magnifyingglass",
                    path: targetPath
                ),
                AgentActionPlanResultFileAction(
                    kind: .revealInFinder,
                    title: "Reveal in Finder",
                    systemImage: "folder",
                    path: targetPath
                )
            ]
        case .downloadPaper, .importLibrary:
            guard let bundlePath = trimmed(result["bundle_path"]) else {
                return []
            }
            return [
                AgentActionPlanResultFileAction(
                    kind: .revealInFinder,
                    title: "Reveal Bundle",
                    systemImage: "folder",
                    path: bundlePath
                )
            ]
        case .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .generateResearchOutline,
             .custom:
            return []
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct AgentActionPlanRecoveryFileActions: Equatable {
    static func resolve(
        _ actionPlan: AgentActionPlan,
        targetFreshness: AgentActionPlanTargetFreshness = .notTracked
    ) -> [AgentActionPlanResultFileAction] {
        guard actionPlan.status == .failed || targetFreshness.blocksLocalWrite(for: actionPlan.status) else {
            return []
        }
        guard isLocalFilePatch(actionPlan.kind), let targetPath = trimmed(actionPlan.targetFilePath) else {
            return []
        }

        return [
            AgentActionPlanResultFileAction(
                kind: .openFile,
                title: "Open Target",
                systemImage: "doc.text.magnifyingglass",
                path: targetPath
            ),
            AgentActionPlanResultFileAction(
                kind: .revealInFinder,
                title: "Reveal Target",
                systemImage: "folder",
                path: targetPath
            )
        ]
    }

    private static func isLocalFilePatch(_ kind: AgentActionKind) -> Bool {
        switch kind {
        case .writeObsidian, .notePatch, .editManuscript, .writingPatch:
            return true
        case .downloadPaper,
             .importLibrary,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .generateResearchOutline,
             .custom:
            return false
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

enum WorkbenchFileTargetActions {
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

struct AgentActionPlanAuditPreview: Hashable {
    var title: String
    var value: String
    var maxLines: Int? = 12

    static func resolve(_ actionPlan: AgentActionPlan) -> AgentActionPlanAuditPreview? {
        if let patch = firstValue(
            keys: ["patch", "preview_markdown", "previewMarkdown"],
            sources: [actionPlan.preview, actionPlan.payload]
        ) {
            return AgentActionPlanAuditPreview(
                title: patchTitle(for: actionPlan),
                value: patchPreviewValue(for: actionPlan, patch: patch),
                maxLines: nil
            )
        }

        if let outline = firstValue(
            keys: ["reading_outline", "readingOutline", "outline", "reading_outline_json"],
            sources: [actionPlan.preview, actionPlan.payload, actionPlan.result]
        ) {
            return AgentActionPlanAuditPreview(title: "Outline Preview", value: outline)
        }

        if let candidateSummary = firstValue(
            keys: ["candidate_summary", "import_summary"],
            sources: [actionPlan.preview, actionPlan.payload]
        ) {
            let importSummary = firstValue(keys: ["import_summary"], sources: [actionPlan.preview, actionPlan.payload])
            var parts = [candidateSummary]
            if let importSummary, importSummary != candidateSummary {
                parts.append(importSummary)
            }
            let value = parts.joined(separator: "\n\n")
            return AgentActionPlanAuditPreview(title: "Zotero Import Preview", value: value)
        }

        return nil
    }

    private static func firstValue(
        keys: [String],
        sources: [[String: String]?]
    ) -> String? {
        for source in sources {
            guard let source else { continue }
            for key in keys {
                if let value = source[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func patchTitle(for actionPlan: AgentActionPlan) -> String {
        switch actionPlan.kind {
        case .writeObsidian, .notePatch:
            return "Note Patch Preview"
        case .editManuscript, .writingPatch:
            return "Writing Patch Preview"
        default:
            return "Patch Preview"
        }
    }

    private static func patchPreviewValue(for actionPlan: AgentActionPlan, patch: String) -> String {
        var header: [String] = []
        if let targetPath = trimmed(actionPlan.targetFilePath) {
            header.append("Target: \(targetPath)")
        }
        if let targetAnchor = firstValue(
            keys: ["target_anchor", "targetAnchor"],
            sources: [actionPlan.payload, actionPlan.preview]
        ) {
            header.append("Anchor: \(targetAnchor)")
        }
        if let blockUid = firstValue(keys: ["block_uid", "blockUid"], sources: [actionPlan.payload]) {
            header.append("Source block: \(blockUid)")
        }
        if let baseHash = trimmed(actionPlan.expectedBaseFileHash) {
            header.append("Base hash: \(baseHash)")
        }

        guard !header.isEmpty else {
            return patch
        }
        return (header + ["", patch]).joined(separator: "\n")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

enum AgentActionPlanTargetFreshness: Equatable {
    case notTracked
    case current
    case stale(expectedHash: String, observedHash: String)

    static func evaluate(
        _ actionPlan: AgentActionPlan,
        fileReader: (String) -> String? = AgentActionPlanTargetFreshness.readFileText
    ) -> AgentActionPlanTargetFreshness {
        guard let expectedHash = actionPlan.expectedBaseFileHash,
              let targetPath = actionPlan.targetFilePath
        else {
            return .notTracked
        }

        let currentText = fileReader(targetPath) ?? ""
        let observedHash = LocalFilePatchExecutor.contentHash(for: currentText)
        if expectedHash == observedHash {
            return .current
        }
        return .stale(expectedHash: expectedHash, observedHash: observedHash)
    }

    func blocksLocalWrite(for status: AgentActionStatus) -> Bool {
        switch self {
        case .stale:
            return status == .pendingApproval || status == .approved
        case .notTracked, .current:
            return false
        }
    }

    private static func readFileText(path: String) -> String? {
        try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }
}

struct AgentActionPlanTargetFreshnessPreview: Equatable {
    var title: String
    var value: String

    static func resolve(
        _ actionPlan: AgentActionPlan,
        targetFreshness: AgentActionPlanTargetFreshness
    ) -> AgentActionPlanTargetFreshnessPreview? {
        switch targetFreshness {
        case .current:
            guard actionPlan.status == .pendingApproval || actionPlan.status == .approved,
                  let targetPath = trimmed(actionPlan.targetFilePath),
                  let baseHash = trimmed(actionPlan.expectedBaseFileHash)
            else {
                return nil
            }
            return AgentActionPlanTargetFreshnessPreview(
                title: "Target verified",
                value: [
                    "Target file matches the preview base hash.",
                    "Target: \(targetPath)",
                    "Base hash: \(baseHash)"
                ].joined(separator: "\n")
            )
        case .stale(let expectedHash, let observedHash):
            guard targetFreshness.blocksLocalWrite(for: actionPlan.status) else {
                return nil
            }
            return AgentActionPlanTargetFreshnessPreview(
                title: "Target changed",
                value: [
                    "Target file changed since preview.",
                    "Expected base hash: \(expectedHash)",
                    "Observed current hash: \(observedHash)"
                ].joined(separator: "\n")
            )
        case .notTracked:
            return nil
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct AgentActionPlanRowActions: Equatable {
    var showsRecovery: Bool
    var showsRegenerate: Bool
    var showsContextPreview: Bool
    var showsAbandon: Bool
    var showsApprove: Bool
    var showsReject: Bool
    var showsApply: Bool
    var showsRun: Bool

    static func resolve(
        _ actionPlan: AgentActionPlan,
        targetFreshness: AgentActionPlanTargetFreshness,
        hasApprove: Bool,
        hasReject: Bool,
        hasApply: Bool,
        hasRun: Bool,
        hasRecover: Bool,
        isResearchActionBusy: Bool = false
    ) -> AgentActionPlanRowActions {
        let blocksLocalWrite = targetFreshness.blocksLocalWrite(for: actionPlan.status)
        let showsRecovery = actionPlan.status == .failed || blocksLocalWrite
        let canApproveOrReject = actionPlan.status == .pendingApproval && !blocksLocalWrite
        let canApply = actionPlan.status == .approved
            && !blocksLocalWrite
            && AgentActionPlanLocalExecutionPolicy.supportsLocalApply(actionPlan)
        let canRun = actionPlan.status == .approved
            && AgentActionPlanRemoteExecutionPolicy.supportsRemoteRun(actionPlan)
        let canMutateActionPlan = !isResearchActionBusy

        return AgentActionPlanRowActions(
            showsRecovery: showsRecovery,
            showsRegenerate: showsRecovery && hasRecover && canMutateActionPlan,
            showsContextPreview: showsRecovery,
            showsAbandon: showsRecovery && hasRecover,
            showsApprove: canApproveOrReject && hasApprove && canMutateActionPlan,
            showsReject: canApproveOrReject && hasReject && canMutateActionPlan,
            showsApply: canApply && hasApply && canMutateActionPlan,
            showsRun: canRun && hasRun && canMutateActionPlan
        )
    }
}

enum AgentActionPlanApprovalPolicy {
    static func approveButtonTitle(for actionPlan: AgentActionPlan) -> String {
        approveButtonTitle(for: actionPlan.kind)
    }

    static func rejectButtonTitle(for actionPlan: AgentActionPlan) -> String {
        rejectButtonTitle(for: actionPlan.kind)
    }

    static func approveButtonHelp(for actionPlan: AgentActionPlan) -> String {
        approveButtonHelp(for: actionPlan.kind)
    }

    static func rejectButtonHelp(for actionPlan: AgentActionPlan) -> String {
        rejectButtonHelp(for: actionPlan.kind)
    }

    static func approveButtonTitle(for kind: AgentActionKind) -> String {
        switch kind {
        case .writeObsidian, .notePatch:
            return "Approve Note Patch"
        case .editManuscript, .writingPatch:
            return "Approve Writing Patch"
        case .downloadPaper, .importLibrary:
            return "Approve Import"
        case .generateResearchOutline:
            return "Approve Outline"
        case .installSkill:
            return "Approve Skill Install"
        case .enableSkill:
            return "Approve Skill Enable"
        case .runExternalTool:
            return "Approve Tool Run"
        case .providerCall:
            return "Approve Provider Call"
        case .writeLibraryBundle:
            return "Approve Library Write"
        case .exportArticle:
            return "Approve Export"
        case .custom:
            return "Approve Action"
        }
    }

    static func rejectButtonTitle(for kind: AgentActionKind) -> String {
        switch kind {
        case .writeObsidian, .notePatch:
            return "Reject Note Patch"
        case .editManuscript, .writingPatch:
            return "Reject Writing Patch"
        case .downloadPaper, .importLibrary:
            return "Reject Import"
        case .generateResearchOutline:
            return "Reject Outline"
        case .installSkill:
            return "Reject Skill Install"
        case .enableSkill:
            return "Reject Skill Enable"
        case .runExternalTool:
            return "Reject Tool Run"
        case .providerCall:
            return "Reject Provider Call"
        case .writeLibraryBundle:
            return "Reject Library Write"
        case .exportArticle:
            return "Reject Export"
        case .custom:
            return "Reject Action"
        }
    }

    static func approveButtonHelp(for kind: AgentActionKind) -> String {
        switch kind {
        case .writeObsidian, .notePatch:
            return "Approve this Note Bridge patch before any local Markdown write runs."
        case .editManuscript, .writingPatch:
            return "Approve this Writing Dock patch before any Typst or TeX write runs."
        case .downloadPaper, .importLibrary:
            return "Approve this import plan before any local library bundle is written."
        case .generateResearchOutline:
            return "Approve this Research Plan outline action before provider execution."
        case .installSkill:
            return "Approve this skill install after reviewing its source and permissions."
        case .enableSkill:
            return "Approve enabling this skill after reviewing its source and permissions."
        case .runExternalTool:
            return "Approve this external tool run after reviewing its command and inputs."
        case .providerCall:
            return "Approve this provider call before any model request is sent."
        case .writeLibraryBundle:
            return "Approve this local library bundle write."
        case .exportArticle:
            return "Approve this article export."
        case .custom:
            return "Approve this action after reviewing its payload."
        }
    }

    static func rejectButtonHelp(for kind: AgentActionKind) -> String {
        switch kind {
        case .writeObsidian, .notePatch:
            return "Reject this Note Bridge patch without writing local Markdown."
        case .editManuscript, .writingPatch:
            return "Reject this Writing Dock patch without writing Typst or TeX."
        case .downloadPaper, .importLibrary:
            return "Reject this import plan without writing a local library bundle."
        case .generateResearchOutline:
            return "Reject this Research Plan outline action without provider execution."
        case .installSkill:
            return "Reject this skill install."
        case .enableSkill:
            return "Reject enabling this skill."
        case .runExternalTool:
            return "Reject this external tool run."
        case .providerCall:
            return "Reject this provider call without sending a model request."
        case .writeLibraryBundle:
            return "Reject this local library bundle write."
        case .exportArticle:
            return "Reject this article export."
        case .custom:
            return "Reject this action."
        }
    }
}

enum AgentActionPlanLocalExecutionPolicy {
    static func supportsLocalApply(_ actionPlan: AgentActionPlan) -> Bool {
        applyButtonTitle(for: actionPlan) != nil
    }

    static func applyButtonTitle(for actionPlan: AgentActionPlan) -> String? {
        applyButtonTitle(for: actionPlan.kind)
    }

    static func applyButtonHelp(for actionPlan: AgentActionPlan) -> String? {
        applyButtonHelp(for: actionPlan.kind)
    }

    static func applyButtonTitle(for kind: AgentActionKind) -> String? {
        switch kind {
        case .writeObsidian, .notePatch:
            return "Apply Note Patch"
        case .editManuscript, .writingPatch:
            return "Apply Writing Patch"
        case .downloadPaper, .importLibrary:
            return "Write Import Bundle"
        case .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .generateResearchOutline,
             .custom:
            return nil
        }
    }

    static func applyButtonHelp(for kind: AgentActionKind) -> String? {
        switch kind {
        case .writeObsidian, .notePatch:
            return "Write the approved Note Bridge patch to the target Markdown file."
        case .editManuscript, .writingPatch:
            return "Write the approved Writing Dock patch to the target Typst or TeX file."
        case .downloadPaper, .importLibrary:
            return "Write the approved import bundle into the local Bilin library."
        case .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .generateResearchOutline,
             .custom:
            return nil
        }
    }
}

enum AgentActionPlanRemoteExecutionPolicy {
    static func supportsRemoteRun(_ actionPlan: AgentActionPlan) -> Bool {
        runButtonTitle(for: actionPlan) != nil
    }

    static func runButtonTitle(for actionPlan: AgentActionPlan) -> String? {
        runButtonTitle(for: actionPlan.kind)
    }

    static func runButtonHelp(for actionPlan: AgentActionPlan) -> String? {
        runButtonHelp(for: actionPlan.kind)
    }

    static func runButtonTitle(for kind: AgentActionKind) -> String? {
        switch kind {
        case .generateResearchOutline:
            return "Generate Outline"
        case .writeObsidian,
             .notePatch,
             .editManuscript,
             .writingPatch,
             .downloadPaper,
             .importLibrary,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .custom:
            return nil
        }
    }

    static func runButtonHelp(for kind: AgentActionKind) -> String? {
        switch kind {
        case .generateResearchOutline:
            return "Run the approved outline action through the Research API."
        case .writeObsidian,
             .notePatch,
             .editManuscript,
             .writingPatch,
             .downloadPaper,
             .importLibrary,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .custom:
            return nil
        }
    }
}

private enum AgentActionPlanRecoveryAction {
    case regenerate
    case viewDiff
    case abandonLocalWrite
}

private struct DetectedWorkspacePathRow: View {
    var record: WorkspacePathRecord
    var isConfigured: Bool
    var onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(record.kind.displayName, systemImage: record.kind.systemImage)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                WorkbenchStatusPill(
                    text: isConfigured && record.status == .available ? "Configured" : record.status.displayName,
                    systemImage: "circle.fill",
                    tint: record.status == .available ? .accentColor : .orange
                )
            }

            KeyValueRow(label: record.name, value: record.path, monospaced: true)
            if record.status != .available {
                Text(record.status.recoveryHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isConfigured {
                Button {
                    onUse()
                } label: {
                    Label(WorkspacePathCommandLabels.useDetectedTitle(for: record.kind), systemImage: "checkmark")
                }
                .disabled(record.status != .available)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }
}

struct ResearchWorkbenchSnapshotKey: Hashable {
    var sessionID: UUID
    var article: Article?
    var selectedZoteroItem: ZoteroItem?
    var selectedBlock: DocumentBlock?
    var selectedReaderTextHash: String?
    var selectedWritingTargetSection: String?
    var selectedTranslation: ReaderTranslation?
    var noteCount: Int
    var translationCount: Int
    var taskSummaries: [String]
    var researchAPIStatus: String
    var researchAPIError: String?
    var researchAPIHealth: BilinAPIHealth?
    var researchAPIBaseURL: String
    var researchWorkbenchStatus: String
    var researchWorkbenchError: String?
    var researchAPIBusy: Bool
    var configuredBilinLibraryRecovery: ConfiguredBilinLibraryRecovery?
    var researchSkills: [ResearchSkill]
    var researchPlans: [ResearchPlan]
    var remoteActionPlans: [AgentActionPlan]
    var detectedWorkspacePaths: [WorkspacePathRecord]
    var workspaceConfiguration: WorkspaceConfiguration
    var workspaceConfigurationError: String?
    var writingProjectLocation: WritingProjectLocation
    var outlineBlockFingerprints: [String]

    @MainActor
    init(
        session: ReaderWorkbenchSession,
        workspaceDefaults: WorkspaceDefaultsModel? = nil
    ) {
        let workspaceDefaults = workspaceDefaults ?? session.workspaceDefaults
        let selectedBlock = session.selectedBlock
        sessionID = session.sessionID
        article = session.selectedArticle
        selectedZoteroItem = session.selectedZoteroItem
        self.selectedBlock = selectedBlock
        selectedReaderTextHash = session.selectedReaderText.map(ReaderSelectionSnapshot.sha256TextHash(for:))
        selectedWritingTargetSection = session.selectedWritingTargetSection
        selectedTranslation = session.selectedBlockTranslation
        noteCount = session.notes.count
        translationCount = session.translations.count
        taskSummaries = session.tasks.map { task in
            task.message ?? task.stage ?? task.status.rawValue
        }
        researchAPIStatus = session.researchAPIStatus
        researchAPIError = session.researchAPIError
        researchAPIHealth = session.researchAPIHealth
        researchAPIBaseURL = session.researchAPIClient.baseURL.absoluteString
        researchWorkbenchStatus = session.researchWorkbenchStatus
        researchWorkbenchError = session.researchWorkbenchError
        researchAPIBusy = session.researchAPIBusy
        configuredBilinLibraryRecovery = session.configuredBilinLibraryRecovery
        researchSkills = session.researchSkills
        researchPlans = session.researchPlans
        remoteActionPlans = session.researchActionPlans
        detectedWorkspacePaths = workspaceDefaults.detectedWorkspacePaths
        workspaceConfiguration = workspaceDefaults.workspaceConfiguration
        workspaceConfigurationError = workspaceDefaults.workspaceConfigurationError
        writingProjectLocation = workspaceDefaults.writingProjectLocation
        outlineBlockFingerprints = Self.outlineBlockFingerprints(
            from: session.blocks,
            selectedBlockUid: selectedBlock?.blockUid
        )
    }

    private static func outlineBlockFingerprints(
        from blocks: [DocumentBlock],
        selectedBlockUid: String?
    ) -> [String] {
        blocks
            .filter { block in
                switch block.blockType {
                case .abstract, .section, .subsection, .paragraph, .equation, .figure, .table:
                    return true
                case .title, .algorithm, .list, .bibliography, .unknown:
                    return false
                }
            }
            .prefix(5)
            .map { block in
                [
                    block.id,
                    block.blockUid,
                    block.blockType.rawValue,
                    block.contentHash,
                    block.sourceLatex ?? "",
                    block.metadata["equation_number"] ?? "",
                    block.blockUid == selectedBlockUid ? "selected" : "idle"
                ]
                .joined(separator: "\u{1f}")
            }
    }
}

@MainActor
final class ResearchWorkbenchSnapshotCache {
    private var cachedKey: ResearchWorkbenchSnapshotKey?
    private var cachedSnapshot: ResearchWorkbenchSnapshot?

    func snapshot(
        for key: ResearchWorkbenchSnapshotKey,
        build: () -> ResearchWorkbenchSnapshot
    ) -> ResearchWorkbenchSnapshot {
        if let cachedSnapshot, cachedKey == key {
            return cachedSnapshot
        }
        let snapshot = build()
        cachedKey = key
        cachedSnapshot = snapshot
        return snapshot
    }

    func invalidate() {
        cachedKey = nil
        cachedSnapshot = nil
    }
}

struct ResearchWorkbenchSnapshot {
    var articleTitle: String
    var selectedBlockLabel: String
    var selectedBlockUid: String?
    var selectedZoteroItemId: Int64?
    var savedNoteCount: Int
    var translationCount: Int
    var taskSummaries: [String]
    var currentTranslationMarkdown: String?
    var researchAPIStatus: String
    var researchAPIError: String?
    var researchAPIHealth: BilinAPIHealth?
    var researchAPIBaseURL: String
    var researchWorkbenchStatus: String
    var researchWorkbenchError: String?
    var researchAPIBusy: Bool
    var configuredBilinLibraryRecovery: ConfiguredBilinLibraryRecovery?
    var researchSkills: [ResearchSkill]
    var researchPlans: [ResearchPlan]
    var remoteActionPlans: [AgentActionPlan]
    var detectedWorkspacePaths: [WorkspacePathRecord]
    var selectedObsidianVault: WorkspacePathRecord?
    var selectedWritingProjectRoot: WorkspacePathRecord?
    var selectedZoteroLibrary: WorkspacePathRecord?
    var workspaceConfigurationError: String?
    var setupItems: [ResearchWorkbenchSetupItem]
    var noteBridge: NoteBridge?
    var noteActionReadiness: WorkbenchActionReadiness
    var outline: ReadingOutline
    var researchPlanActionReadiness: WorkbenchActionReadiness
    var writingProject: WritingProject
    var writingTargetSection: String
    var writingTargetSectionOptions: [String]
    var writingActionReadiness: WorkbenchActionReadiness
    var actionPlan: AgentActionPlan?
    var refresh: @MainActor () async -> Void
    var indexSkills: @MainActor () async -> Void
    var enableSkill: @MainActor (ResearchSkill) async -> Void
    var detectWorkspacePaths: @MainActor () -> Void
    var useDetectedWorkspacePath: @MainActor (WorkspacePathRecord) async -> Void
    var prepareNoteActionPlan: @MainActor () async -> Void
    var prepareResearchPlanActionPlan: @MainActor () async -> Void
    var prepareWritingActionPlan: @MainActor () async -> Void
    var approve: @MainActor (AgentActionPlan) async -> Void
    var reject: @MainActor (AgentActionPlan) async -> Void
    var apply: @MainActor (AgentActionPlan) async -> Void
    var run: @MainActor (AgentActionPlan) async -> Void
    var regenerate: @MainActor (AgentActionPlan) async -> Void
    var dismiss: @MainActor (AgentActionPlan) -> Void
    var selectWritingTargetSection: @MainActor (String) -> Void
    var chooseBilinLibrary: @MainActor () async -> Void
    var chooseZoteroLibrary: @MainActor () async -> Void
    var chooseObsidianVault: @MainActor () -> Void
    var chooseWritingProject: @MainActor () -> Void

    var setupStatusLabel: String {
        let blockingActionCount = setupItems.filter {
            $0.tintRole == .warning
        }.count
        if blockingActionCount > 0 {
            return blockingActionCount == 1 ? "1 action" : "\(blockingActionCount) actions"
        }

        let suggestionCount = setupItems.filter { $0.action != nil }.count
        guard suggestionCount > 0 else { return "Ready" }
        return suggestionCount == 1 ? "Ready · 1 suggestion" : "Ready · \(suggestionCount) suggestions"
    }

    var researchAPIHealthLabel: String? {
        guard let researchAPIHealth else { return nil }
        if let version = researchAPIHealth.version, !version.isEmpty {
            return "\(researchAPIHealth.app) \(version) · \(researchAPIHealth.status)"
        }
        return "\(researchAPIHealth.app) · \(researchAPIHealth.status)"
    }

    var researchAPIStatusTint: Color {
        if researchAPIError != nil {
            return .orange
        }
        if researchAPIHealth != nil {
            return .accentColor
        }
        return .secondary
    }

    var uniqueAvailableDetectedObsidianVault: WorkspacePathRecord? {
        let matches = detectedWorkspacePaths.filter { record in
            record.kind == .obsidianVault
                && record.status == .available
                && !isConfigured(record)
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    var noteActionPlans: [AgentActionPlan] {
        remoteActionPlans.filter {
            $0.belongsToNoteBridge
                && $0.belongsToSelectedBlock(selectedBlockUid)
                && $0.targetsFile(noteActionTargetPath)
        }
    }

    var writingActionPlans: [AgentActionPlan] {
        remoteActionPlans.filter {
            $0.belongsToWritingDock
                && $0.belongsToSelectedBlock(selectedBlockUid)
                && $0.targetsFile(writingActionTargetPath)
        }
    }

    var researchPlanActionPlans: [AgentActionPlan] {
        remoteActionPlans.filter {
            $0.belongsToResearchPlan
                && (
                    $0.targetsArticleRevision(outline.articleRevisionId)
                        || $0.targetsZoteroItem(selectedZoteroItemId)
                )
        }
    }

    private var noteActionTargetPath: String? {
        guard let noteBridge, let vaultPath = selectedObsidianVault?.path else {
            return nil
        }
        return Self.absoluteTargetPath(
            rootPath: vaultPath,
            targetPath: noteBridge.targetNotePath
        )
    }

    private var writingActionTargetPath: String? {
        writingProject.mainFilePath
    }

    @MainActor
    init(
        session: ReaderWorkbenchSession,
        workspaceDefaults: WorkspaceDefaultsModel? = nil
    ) {
        let workspaceDefaults = workspaceDefaults ?? session.workspaceDefaults
        let now = Date()
        let article = session.selectedArticle
        let selectedBlock = session.selectedBlock
        let selectedTranslation = session.selectedBlockTranslation
        let selectedReaderText = session.selectedReaderText
        let selectedReaderTextHash = selectedReaderText.map(ReaderSelectionSnapshot.sha256TextHash(for:))
        let revisionId = selectedBlock?.articleRevisionId ?? article?.activeRevisionId ?? "unselected-revision"
        let articleName = article?.title ?? session.selectedZoteroItem?.title ?? "No paper selected"
        let configuredVault = workspaceDefaults.workspaceConfiguration.selectedObsidianVault
        let configuredWritingProjectRoot = workspaceDefaults.workspaceConfiguration.writingProjectRoots.first

        articleTitle = articleName
        selectedBlockLabel = selectedBlock.map { "\($0.blockUid) · \($0.blockType.rawValue)" } ?? "No reader block selected"
        selectedBlockUid = selectedBlock?.blockUid
        selectedZoteroItemId = session.selectedZoteroItem?.id
        savedNoteCount = session.notes.count
        translationCount = session.translations.count
        currentTranslationMarkdown = selectedTranslation?.rawMarkdown
        researchAPIStatus = session.researchAPIStatus
        researchAPIError = session.researchAPIError
        researchAPIHealth = session.researchAPIHealth
        researchAPIBaseURL = session.researchAPIClient.baseURL.absoluteString
        researchWorkbenchStatus = session.researchWorkbenchStatus
        researchWorkbenchError = session.researchWorkbenchError
        researchAPIBusy = session.researchAPIBusy
        configuredBilinLibraryRecovery = session.configuredBilinLibraryRecovery
        researchSkills = session.researchSkills
        researchPlans = session.researchPlans
        remoteActionPlans = session.researchActionPlans
        detectedWorkspacePaths = workspaceDefaults.detectedWorkspacePaths
        selectedObsidianVault = configuredVault
        selectedWritingProjectRoot = configuredWritingProjectRoot
        selectedZoteroLibrary = workspaceDefaults.workspaceConfiguration.selectedZoteroLibrary
        workspaceConfigurationError = workspaceDefaults.workspaceConfigurationError
        noteActionReadiness = Self.noteActionReadiness(
            selectedBlock: selectedBlock,
            selectedObsidianVault: configuredVault,
            isAPIAvailable: session.isResearchAPIReady,
            isBusy: session.researchAPIBusy
        )
        refresh = { await session.refreshResearchWorkbench() }
        indexSkills = { await session.indexLocalResearchSkills() }
        enableSkill = { skill in await session.enableResearchSkill(skill) }
        detectWorkspacePaths = { workspaceDefaults.detectWorkspacePaths() }
        useDetectedWorkspacePath = { record in await session.useDetectedWorkspacePath(record) }
        prepareNoteActionPlan = { await session.prepareSelectedBlockNoteActionPlan() }
        prepareResearchPlanActionPlan = { await session.prepareSelectedArticleReadingOutlineActionPlan() }
        prepareWritingActionPlan = { await session.prepareSelectedBlockWritingActionPlan() }
        approve = { actionPlan in await session.approveResearchActionPlan(actionPlan) }
        reject = { actionPlan in await session.rejectResearchActionPlan(actionPlan) }
        apply = { actionPlan in await session.applyResearchActionPlan(actionPlan) }
        run = { actionPlan in await session.runResearchOutlineActionPlan(actionPlan) }
        regenerate = { actionPlan in await session.regenerateResearchActionPlan(actionPlan) }
        dismiss = { actionPlan in session.dismissResearchActionPlan(actionPlan) }
        selectWritingTargetSection = { section in
            session.selectedWritingTargetSection = section
        }
        chooseBilinLibrary = { await session.openLibraryFromPanel() }
        chooseZoteroLibrary = { await session.openZoteroLibraryFromPanel() }
        chooseObsidianVault = { workspaceDefaults.chooseObsidianVaultFromPanel() }
        chooseWritingProject = { workspaceDefaults.chooseWritingProjectFromPanel() }
        taskSummaries = session.tasks.map { task in
            task.message ?? task.stage ?? task.status.rawValue
        }

        let selectedProvenance = selectedBlock.map {
            Self.provenance(
                for: $0,
                article: article,
                translation: selectedTranslation,
                selectedText: selectedReaderText,
                capturedAt: now
            )
        }

        if let selectedBlock, let provenance = selectedProvenance {
            let vaultRecord = configuredVault
            let sourceMarkdown = selectedReaderText ?? Self.semanticSourceMarkdown(for: selectedBlock)
            let noteDraft = NoteActionPlanBuilder().build(
                articleTitle: articleName,
                articleRevisionId: revisionId,
                blockUid: selectedBlock.blockUid,
                sourceMarkdown: sourceMarkdown,
                translationMarkdown: selectedTranslation?.rawMarkdown,
                selectedTextHash: selectedReaderTextHash,
                vaultPath: vaultRecord?.path
            )
            let notePath = noteDraft.targetNotePath
            let blockAnchor = noteDraft.blockAnchor
            let vaultRootPath = vaultRecord?.path ?? "Choose an Obsidian vault"
            let targetPath = noteDraft.targetPath ?? notePath
            let translationPayload = selectedTranslation.map {
                NoteBridgePayload(
                    blockUid: selectedBlock.blockUid,
                    language: $0.targetLanguage,
                    markdown: $0.rawMarkdown,
                    contentHash: "translation-\($0.id)"
                )
            }
            let patch = PendingFilePatch(
                id: "note-patch-\(selectedBlock.id)",
                kind: .obsidianMarkdown,
                format: .markdown,
                status: .previewReady,
                targetPath: targetPath,
                targetAnchor: blockAnchor,
                targetSectionPath: ["Papers", articleName],
                patchText: noteDraft.patchText,
                previewMarkdown: noteDraft.patchText,
                baseFileHash: nil,
                provenance: [provenance],
                createdAt: now,
                updatedAt: now
            )

            noteBridge = NoteBridge(
                id: "note-bridge-\(selectedBlock.id)",
                articleRevisionId: revisionId,
                status: .previewReady,
                targetVault: NoteBridgeVault(
                    id: vaultRecord?.id ?? "obsidian-vault-unselected",
                    name: vaultRecord?.name ?? "No vault selected",
                    rootPath: vaultRootPath,
                    status: vaultRecord?.status ?? .permissionRequired
                ),
                targetNotePath: notePath,
                headingPath: ["Papers", articleName],
                blockAnchor: blockAnchor,
                calloutType: selectedBlock.blockType == .equation ? .important : .note,
                tags: ["#bilin/source-block"],
                sourcePayload: NoteBridgePayload(
                    blockUid: selectedBlock.blockUid,
                    language: "en",
                    markdown: sourceMarkdown,
                    contentHash: selectedReaderTextHash ?? selectedBlock.contentHash
                ),
                translationPayload: translationPayload,
                pendingPatch: patch,
                provenance: provenance,
                createdAt: now,
                updatedAt: now
            )
        } else {
            noteBridge = nil
        }

        let outlineItems = Self.outlineItems(
            from: session.blocks,
            article: article,
            selectedBlockUid: selectedBlock?.blockUid,
            capturedAt: now
        )
        let fallbackOutline = ReadingOutline(
            id: "outline-\(revisionId)",
            articleRevisionId: revisionId,
            title: article == nil ? "No paper" : "Master \(articleName)",
            status: article == nil ? .draft : .ready,
            items: outlineItems,
            sourceProvenance: outlineItems.flatMap(\.sourceProvenance),
            generatedAt: now,
            updatedAt: now
        )
        outline = Self.generatedReadingOutline(
            from: session.researchPlans,
            articleRevisionId: revisionId,
            fallbackTitle: articleName,
            capturedAt: now
        ) ?? Self.generatedReadingOutline(
            from: session.researchActionPlans,
            articleRevisionId: revisionId,
            fallbackTitle: articleName,
            capturedAt: now
        ) ?? fallbackOutline
        researchPlanActionReadiness = Self.researchPlanActionReadiness(
            selectedArticle: article,
            researchSkills: session.researchSkills,
            isAPIAvailable: session.isResearchAPIReady,
            isBusy: session.researchAPIBusy
        )

        let writingProjectInfo = workspaceDefaults.writingProjectLocation
        let selectedWritingTargetSection = session.selectedWritingTargetSection
        writingTargetSection = WritingTargetSectionResolver.displayName(
            for: writingProjectInfo,
            selectedTitle: selectedWritingTargetSection
        )
        writingTargetSectionOptions = WritingTargetSectionResolver.options(for: writingProjectInfo)
        let writingPatch = selectedProvenance.map { provenance in
            Self.writingPatch(
                from: selectedBlock,
                revisionId: revisionId,
                location: writingProjectInfo,
                provenance: provenance,
                selectedText: selectedReaderText,
                selectedTargetSection: selectedWritingTargetSection,
                now: now
            )
        }
        writingProject = WritingProject(
            id: configuredWritingProjectRoot?.id ?? "writing-project-unselected",
            name: configuredWritingProjectRoot?.name ?? "No writing project",
            rootPath: writingProjectInfo.rootPath,
            kind: writingProjectInfo.kind,
            status: writingProjectInfo.status,
            mainFilePath: writingProjectInfo.mainFilePath,
            bibliographyFilePaths: writingProjectInfo.bibliographyFilePaths,
            detectedFilePaths: writingProjectInfo.detectedFilePaths,
            pendingPatches: writingPatch.map { [$0] } ?? [],
            sourceProvenance: selectedProvenance.map { [$0] } ?? [],
            createdAt: now,
            updatedAt: now
        )
        writingActionReadiness = Self.writingActionReadiness(
            selectedBlock: selectedBlock,
            writingProject: writingProject,
            selectedWritingProjectRoot: configuredWritingProjectRoot,
            isAPIAvailable: session.isResearchAPIReady,
            isBusy: session.researchAPIBusy
        )
        setupItems = Self.setupItems(
            configuredBilinLibraryRecovery: session.configuredBilinLibraryRecovery,
            selectedObsidianVault: configuredVault,
            selectedWritingProjectRoot: configuredWritingProjectRoot,
            selectedZoteroLibrary: selectedZoteroLibrary,
            writingProject: writingProject,
            isAPIAvailable: session.isResearchAPIReady,
            researchAPIStatus: session.researchAPIStatus,
            researchAPIError: session.researchAPIError,
            researchWorkbenchStatus: session.researchWorkbenchStatus,
            researchWorkbenchError: session.researchWorkbenchError,
            detectedWorkspacePaths: workspaceDefaults.detectedWorkspacePaths,
            researchSkills: session.researchSkills
        )

        if let writingPatch {
            actionPlan = AgentActionPlan(
                id: "action-plan-\(writingPatch.id)",
                kind: .editManuscript,
                status: .pendingApproval,
                title: "Prepare manuscript insertion",
                summary: "Manuscript insertion preview from the selected source block.",
                requestedPermissions: [.providerCall, .editManuscript],
                steps: [
                    AgentActionStep(
                        id: "step-draft-\(writingPatch.id)",
                        kind: .callProvider,
                        title: "Draft insertion with source provenance",
                        permission: .providerCall
                    ),
                    AgentActionStep(
                        id: "step-preview-\(writingPatch.id)",
                        kind: .previewPatch,
                        title: "Preview Typst patch",
                        targetPath: writingPatch.targetPath
                    ),
                    AgentActionStep(
                        id: "step-apply-\(writingPatch.id)",
                        kind: .writeFile,
                        title: "Apply patch after approval",
                        targetPath: writingPatch.targetPath,
                        permission: .editManuscript
                    )
                ],
                payloadHash: "payload-\(writingPatch.id)",
                relatedPatchIds: [writingPatch.id],
                createdAt: now,
                updatedAt: now
            )
        } else {
            actionPlan = nil
        }
    }

    static func setupItems(
        configuredBilinLibraryRecovery: ConfiguredBilinLibraryRecovery?,
        selectedObsidianVault: WorkspacePathRecord?,
        selectedWritingProjectRoot: WorkspacePathRecord?,
        selectedZoteroLibrary: WorkspacePathRecord?,
        writingProject: WritingProject,
        isAPIAvailable: Bool,
        researchAPIStatus: String,
        researchAPIError: String?,
        researchWorkbenchStatus: String,
        researchWorkbenchError: String?,
        detectedWorkspacePaths: [WorkspacePathRecord],
        researchSkills: [ResearchSkill] = []
    ) -> [ResearchWorkbenchSetupItem] {
        var items: [ResearchWorkbenchSetupItem] = []

        if let recovery = configuredBilinLibraryRecovery {
            items.append(
                ResearchWorkbenchSetupItem(
                    id: "bilin-library-recovery",
                    title: "Previous library needs attention",
                    detail: "\(recovery.message) Choose the library again before relying on its paper list.",
                    systemImage: "books.vertical",
                    tintRole: .warning,
                    action: .chooseBilinLibrary
                )
            )
        }

        if let apiItem = setupItemForResearchAPI(
            isAvailable: isAPIAvailable,
            status: researchAPIStatus,
            error: researchAPIError
        ) {
            items.append(apiItem)
        }

        if let workbenchIssue = setupItemForWorkbenchIssue(
            status: researchWorkbenchStatus,
            error: researchWorkbenchError
        ) {
            items.append(workbenchIssue)
        }

        if isAPIAvailable, let skillItem = setupItemForReadingOutlineSkill(researchSkills) {
            items.append(skillItem)
        }

        if let selectedObsidianVault {
            if selectedObsidianVault.status != .available {
                items.append(
                    ResearchWorkbenchSetupItem(
                        id: "obsidian-vault-permission",
                        title: "Obsidian vault needs permission",
                        detail: selectedObsidianVault.status.recoveryHint,
                        systemImage: "lock",
                        tintRole: .warning,
                        action: .chooseObsidianVault
                    )
                )
            }
        } else {
            let detectedVaults = Self.availableDetectedPaths(
                kind: .obsidianVault,
                detectedWorkspacePaths: detectedWorkspacePaths
            )
            let detail = detectedVaults.count == 1
                ? "Detected \(detectedVaults[0].name). Choose a Markdown vault so Note Bridge can prepare auditable patches."
                : "Choose a Markdown vault so Note Bridge can prepare auditable patches."
            items.append(
                ResearchWorkbenchSetupItem(
                    id: "obsidian-vault",
                    title: "Obsidian vault not configured",
                    detail: detail,
                    systemImage: "note.text",
                    tintRole: .warning,
                    action: detectedVaults.count == 1
                        ? .useDetectedWorkspacePath(detectedVaults[0])
                        : .chooseObsidianVault
                )
            )
        }

        if let selectedWritingProjectRoot {
            if selectedWritingProjectRoot.status != .available {
                items.append(
                    ResearchWorkbenchSetupItem(
                        id: "writing-project-permission",
                        title: "Writing project needs permission",
                        detail: selectedWritingProjectRoot.status.recoveryHint,
                        systemImage: "lock",
                        tintRole: .warning,
                        action: .chooseWritingProject
                    )
                )
            } else if writingProject.mainFilePath == nil {
                items.append(
                    ResearchWorkbenchSetupItem(
                        id: "writing-project-main-file",
                        title: "Writing project has no main file",
                        detail: "Choose a Typst or TeX project that contains a main manuscript file before preparing writing patches.",
                        systemImage: "doc.badge.gearshape",
                        tintRole: .warning,
                        action: .chooseWritingProject
                    )
                )
            }
        } else {
            items.append(
                ResearchWorkbenchSetupItem(
                    id: "writing-project",
                    title: "Writing project not configured",
                    detail: "Choose a Typst or TeX project root so selected reading blocks can become manuscript patches.",
                    systemImage: "doc.richtext",
                    tintRole: .warning,
                    action: .chooseWritingProject
                )
            )
        }

        let hasDetectedLocalApps = detectedWorkspacePaths.contains { record in
            switch record.kind {
            case .zoteroLibrary, .obsidianVault:
                return true
            case .bilinLibrary, .writingProjectRoot:
                return false
            }
        }
        if !hasDetectedLocalApps {
            items.append(
                ResearchWorkbenchSetupItem(
                    id: "detect-local-apps",
                    title: "Local apps not detected",
                    detail: "Detect Zotero and Obsidian locations to reduce manual setup.",
                    systemImage: "magnifyingglass",
                    tintRole: .secondary,
                    action: .detectLocalApps
                )
            )
        }

        let detectedZoteroLibraries = Self.availableDetectedPaths(
            kind: .zoteroLibrary,
            detectedWorkspacePaths: detectedWorkspacePaths
        )
        if selectedZoteroLibrary == nil, detectedZoteroLibraries.count == 1 {
            let zotero = detectedZoteroLibraries[0]
            items.append(
                ResearchWorkbenchSetupItem(
                    id: "zotero-library-detected",
                    title: "Zotero library detected",
                    detail: "Use \(zotero.name) if you want the reader to open local Zotero metadata on launch.",
                    systemImage: "tray.full",
                    tintRole: .secondary,
                    action: .useDetectedWorkspacePath(zotero)
                )
            )
        }

        if items.isEmpty {
            items.append(
                ResearchWorkbenchSetupItem(
                    id: "ready",
                    title: "Research workflow ready",
                    detail: "API, Note Bridge, and Writing Dock have the local paths needed for confirmed Agent actions.",
                    systemImage: "checkmark.circle",
                    tintRole: .accent,
                    action: nil
                )
            )
        }

        return items
    }

    private static func absoluteTargetPath(rootPath: String, targetPath: String) -> String {
        if targetPath.hasPrefix("/") {
            return normalizedFilePath(targetPath)
        }
        return normalizedFilePath(
            (rootPath as NSString).appendingPathComponent(targetPath)
        )
    }

    private static func normalizedFilePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func setupItemForWorkbenchIssue(
        status: String,
        error: String?
    ) -> ResearchWorkbenchSetupItem? {
        let trimmedError = error?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = trimmedError?.isEmpty == false
            ? trimmedError!
            : "Review the local workbench state before preparing another research action."

        switch status {
        case "Location unavailable":
            return ResearchWorkbenchSetupItem(
                id: "workbench-location-unavailable",
                title: "Local location unavailable",
                detail: detail,
                systemImage: "folder.badge.questionmark",
                tintRole: .warning,
                action: .detectLocalApps
            )
        case "Zotero unavailable":
            return ResearchWorkbenchSetupItem(
                id: "workbench-zotero-unavailable",
                title: "Zotero library unavailable",
                detail: detail,
                systemImage: "tray.full",
                tintRole: .warning,
                action: .chooseZoteroLibrary
            )
        case "Workbench unavailable":
            return ResearchWorkbenchSetupItem(
                id: "workbench-unavailable",
                title: "Research workbench unavailable",
                detail: detail,
                systemImage: "exclamationmark.triangle",
                tintRole: .warning,
                action: .refreshWorkbench
            )
        case "Cannot read main file":
            return ResearchWorkbenchSetupItem(
                id: "workbench-main-file-unreadable",
                title: "Main manuscript file is unreadable",
                detail: detail,
                systemImage: "doc.badge.gearshape",
                tintRole: .warning,
                action: .chooseWritingProject
            )
        default:
            return nil
        }
    }

    private static func setupItemForReadingOutlineSkill(
        _ researchSkills: [ResearchSkill]
    ) -> ResearchWorkbenchSetupItem? {
        let requiredSlug = "paper-outline"
        guard let skill = researchSkills.first(where: { $0.slug == requiredSlug }) else {
            return ResearchWorkbenchSetupItem(
                id: "paper-outline-skill-missing",
                title: "Reading outline skill not indexed",
                detail: "Index local research skills before preparing paper-specific reading outline actions.",
                systemImage: "shippingbox",
                tintRole: .warning,
                action: .indexResearchSkills
            )
        }
        guard skill.supportsPaperReading else {
            return ResearchWorkbenchSetupItem(
                id: "paper-outline-skill-task",
                title: "Reading outline skill task mismatch",
                detail: "\(skill.title) is indexed but does not declare paper reading support.",
                systemImage: "exclamationmark.triangle",
                tintRole: .warning,
                action: .indexResearchSkills
            )
        }
        guard skill.isEnabled else {
            return ResearchWorkbenchSetupItem(
                id: "paper-outline-skill-disabled",
                title: "Reading outline skill disabled",
                detail: skill.enableAuditSummary,
                systemImage: "checkmark.seal",
                tintRole: .warning,
                action: .enableResearchSkill(skill)
            )
        }
        return nil
    }

    private static func setupItemForResearchAPI(
        isAvailable: Bool,
        status: String,
        error: String?
    ) -> ResearchWorkbenchSetupItem? {
        guard !isAvailable else { return nil }

        let trimmedError = error?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedError, !trimmedError.isEmpty {
            return ResearchWorkbenchSetupItem(
                id: "research-api",
                title: "Research API unavailable",
                detail: trimmedError,
                systemImage: "externaldrive.badge.questionmark",
                tintRole: .warning,
                action: .refreshAPI
            )
        }

        if normalizedStatus == "Checking API" {
            return ResearchWorkbenchSetupItem(
                id: "research-api",
                title: "Checking Research API",
                detail: "Bilin is checking the local research backend before preparing AgentActionPlans.",
                systemImage: "externaldrive.badge.icloud",
                tintRole: .warning,
                action: .refreshAPI
            )
        }

        return ResearchWorkbenchSetupItem(
            id: "research-api",
            title: "Research API not checked",
            detail: "Check the local research backend before preparing AgentActionPlans.",
            systemImage: "externaldrive.badge.questionmark",
            tintRole: .warning,
            action: .refreshAPI
        )
    }

    private static func availableDetectedPaths(
        kind: WorkspacePathKind,
        detectedWorkspacePaths: [WorkspacePathRecord]
    ) -> [WorkspacePathRecord] {
        detectedWorkspacePaths.filter { record in
            record.kind == kind && record.status == .available
        }
    }

    static func noteActionReadiness(
        selectedBlock: DocumentBlock?,
        selectedObsidianVault: WorkspacePathRecord?,
        isAPIAvailable: Bool,
        isBusy: Bool
    ) -> WorkbenchActionReadiness {
        guard selectedBlock != nil else {
            return WorkbenchActionReadiness(
                title: "Select a source block",
                detail: "Choose text or a block in the reader before preparing a note patch.",
                systemImage: "cursorarrow.click",
                tintRole: .secondary,
                isReady: false
            )
        }
        guard selectedObsidianVault != nil else {
            return WorkbenchActionReadiness(
                title: "Choose an Obsidian vault",
                detail: "Bilin needs a local Markdown vault before it can prepare an auditable note patch.",
                systemImage: "folder.badge.questionmark",
                tintRole: .warning,
                isReady: false
            )
        }
        guard selectedObsidianVault?.status == .available else {
            return WorkbenchActionReadiness(
                title: "Reauthorize Obsidian vault",
                detail: "The configured vault is not readable. Choose it again from Settings or Note Bridge.",
                systemImage: "lock",
                tintRole: .warning,
                isReady: false
            )
        }
        guard isAPIAvailable else {
            return WorkbenchActionReadiness(
                title: "Check Research API",
                detail: "Connect the local research backend before preparing an AgentActionPlan.",
                systemImage: "externaldrive.badge.questionmark",
                tintRole: .warning,
                isReady: false
            )
        }
        guard !isBusy else {
            return WorkbenchActionReadiness(
                title: "Research action in progress",
                detail: "Wait for the current Agent action to finish before preparing another patch.",
                systemImage: "hourglass",
                tintRole: .secondary,
                isReady: false
            )
        }
        return .noteReady
    }

    static func researchPlanActionReadiness(
        selectedArticle: Article?,
        researchSkills: [ResearchSkill],
        isAPIAvailable: Bool,
        isBusy: Bool
    ) -> WorkbenchActionReadiness {
        guard selectedArticle != nil else {
            return WorkbenchActionReadiness(
                title: "Select a paper",
                detail: "Choose a library paper before preparing a paper-specific reading outline.",
                systemImage: "doc.text.magnifyingglass",
                tintRole: .secondary,
                isReady: false
            )
        }
        guard isAPIAvailable else {
            return WorkbenchActionReadiness(
                title: "Check Research API",
                detail: "Connect the local research backend before preparing an AgentActionPlan.",
                systemImage: "externaldrive.badge.questionmark",
                tintRole: .warning,
                isReady: false
            )
        }
        if let skillReadiness = readingOutlineSkillReadiness(researchSkills) {
            return skillReadiness
        }
        guard !isBusy else {
            return WorkbenchActionReadiness(
                title: "Research action in progress",
                detail: "Wait for the current Agent action to finish before preparing another outline.",
                systemImage: "hourglass",
                tintRole: .secondary,
                isReady: false
            )
        }
        return .researchPlanReady
    }

    private static func readingOutlineSkillReadiness(
        _ researchSkills: [ResearchSkill]
    ) -> WorkbenchActionReadiness? {
        let requiredSlug = "paper-outline"
        guard let skill = researchSkills.first(where: { $0.slug == requiredSlug }) else {
            return WorkbenchActionReadiness(
                title: "Index paper-outline skill",
                detail: "Bilin needs the paper-outline research skill before preparing a reading outline action.",
                systemImage: "shippingbox",
                tintRole: .warning,
                isReady: false
            )
        }
        guard skill.supportsPaperReading else {
            return WorkbenchActionReadiness(
                title: "Paper outline skill mismatch",
                detail: "\(skill.title) is indexed but does not declare paper reading support.",
                systemImage: "exclamationmark.triangle",
                tintRole: .warning,
                isReady: false
            )
        }
        guard skill.isEnabled else {
            return WorkbenchActionReadiness(
                title: "Enable paper-outline skill",
                detail: "\(skill.title) is indexed but disabled. Enable it before preparing outline actions.",
                systemImage: "checkmark.seal",
                tintRole: .warning,
                isReady: false
            )
        }
        return nil
    }

    static func writingActionReadiness(
        selectedBlock: DocumentBlock?,
        writingProject: WritingProject,
        selectedWritingProjectRoot: WorkspacePathRecord?,
        isAPIAvailable: Bool,
        isBusy: Bool
    ) -> WorkbenchActionReadiness {
        guard selectedBlock != nil else {
            return WorkbenchActionReadiness(
                title: "Select a source block",
                detail: "Choose text or a block in the reader before preparing a manuscript patch.",
                systemImage: "cursorarrow.click",
                tintRole: .secondary,
                isReady: false
            )
        }
        guard selectedWritingProjectRoot != nil else {
            return WorkbenchActionReadiness(
                title: "Choose a writing project",
                detail: "Bilin needs a local Typst or TeX project before it can prepare a manuscript patch.",
                systemImage: "folder.badge.questionmark",
                tintRole: .warning,
                isReady: false
            )
        }
        guard selectedWritingProjectRoot?.status == .available else {
            return WorkbenchActionReadiness(
                title: "Reauthorize writing project",
                detail: "The configured Typst or TeX project is not readable. Choose it again before preparing a patch.",
                systemImage: "lock",
                tintRole: .warning,
                isReady: false
            )
        }
        guard writingProject.mainFilePath != nil else {
            return WorkbenchActionReadiness(
                title: "Select a project with a main file",
                detail: "The linked project does not expose a main Typst or TeX file yet.",
                systemImage: "doc.badge.gearshape",
                tintRole: .warning,
                isReady: false
            )
        }
        guard isAPIAvailable else {
            return WorkbenchActionReadiness(
                title: "Check Research API",
                detail: "Connect the local research backend before preparing an AgentActionPlan.",
                systemImage: "externaldrive.badge.questionmark",
                tintRole: .warning,
                isReady: false
            )
        }
        guard !isBusy else {
            return WorkbenchActionReadiness(
                title: "Research action in progress",
                detail: "Wait for the current Agent action to finish before preparing another patch.",
                systemImage: "hourglass",
                tintRole: .secondary,
                isReady: false
            )
        }
        return .writingReady
    }

    func isConfigured(_ record: WorkspacePathRecord) -> Bool {
        switch record.kind {
        case .obsidianVault:
            return selectedObsidianVault?.path == record.path
        case .zoteroLibrary:
            return selectedZoteroLibrary?.path == record.path
        case .writingProjectRoot:
            return selectedWritingProjectRoot?.path == record.path
        case .bilinLibrary:
            return false
        }
    }

    private static func provenance(
        for block: DocumentBlock,
        article: Article?,
        translation: ReaderTranslation?,
        selectedText: String?,
        capturedAt: Date
    ) -> SourceBlockProvenance {
        ReaderSelectionSnapshot(
            block: block,
            translation: translation,
            article: article,
            sourceLanguage: "en",
            selectedText: selectedText,
            capturedAt: capturedAt
        )
        .sourceBlockProvenance
    }

    private static func outlineItems(
        from blocks: [DocumentBlock],
        article: Article?,
        selectedBlockUid: String?,
        capturedAt: Date
    ) -> [ReadingOutlineItem] {
        blocks
            .filter { block in
                switch block.blockType {
                case .abstract, .section, .subsection, .paragraph, .equation, .figure, .table:
                    return true
                case .title, .algorithm, .list, .bibliography, .unknown:
                    return false
                }
            }
            .prefix(5)
            .map { block in
                let importance: ReadingOutlineImportance = block.blockUid == selectedBlockUid ? .high : .medium
                return ReadingOutlineItem(
                    id: "outline-item-\(block.id)",
                    kind: Self.outlineKind(for: block.blockType),
                    title: Self.outlineTitle(for: block),
                    summaryMarkdown: Self.outlineSummary(for: block),
                    importance: importance,
                    sourceProvenance: [
                        Self.provenance(
                            for: block,
                            article: article,
                            translation: nil,
                            selectedText: nil,
                            capturedAt: capturedAt
                        )
                    ]
                )
            }
    }

    private static func generatedReadingOutline(
        from researchPlans: [ResearchPlan],
        articleRevisionId: String,
        fallbackTitle: String,
        capturedAt: Date
    ) -> ReadingOutline? {
        let candidates = researchPlans
            .filter { plan in
                plan.kind == .paperReading
                    && plan.matchesArticleRevision(articleRevisionId)
                    && plan.readingOutline != nil
            }
            .sorted {
                generatedOutlineRank($0.status) == generatedOutlineRank($1.status)
                    ? $0.updatedAt > $1.updatedAt
                    : generatedOutlineRank($0.status) > generatedOutlineRank($1.status)
            }

        guard let plan = candidates.first,
              var outline = plan.readingOutline
        else {
            return nil
        }
        if outline.id.isEmpty {
            outline.id = "outline-\(plan.id)"
        }
        if outline.articleRevisionId.isEmpty {
            outline.articleRevisionId = plan.articleRevisionId ?? articleRevisionId
        }
        if outline.title.isEmpty {
            outline.title = fallbackTitle
        }
        if outline.status == .draft {
            outline.status = plan.status.readingOutlineStatus
        }
        if outline.generatedAt == Date(timeIntervalSince1970: 0) {
            outline.generatedAt = plan.createdAt
        }
        if outline.updatedAt == Date(timeIntervalSince1970: 0) {
            outline.updatedAt = plan.updatedAt > outline.generatedAt ? plan.updatedAt : capturedAt
        }
        return outline
    }

    private static func generatedReadingOutline(
        from actionPlans: [AgentActionPlan],
        articleRevisionId: String,
        fallbackTitle: String,
        capturedAt: Date
    ) -> ReadingOutline? {
        let candidates = actionPlans
            .filter {
                $0.belongsToResearchPlan
                    && $0.targetsArticleRevision(articleRevisionId)
            }
            .sorted {
                generatedOutlineRank($0.status) == generatedOutlineRank($1.status)
                    ? $0.updatedAt > $1.updatedAt
                    : generatedOutlineRank($0.status) > generatedOutlineRank($1.status)
            }

        for actionPlan in candidates {
            if let outline = decodedReadingOutline(from: actionPlan, fallbackTitle: fallbackTitle, capturedAt: capturedAt) {
                return outline
            }
        }
        return nil
    }

    private static func decodedReadingOutline(
        from actionPlan: AgentActionPlan,
        fallbackTitle: String,
        capturedAt: Date
    ) -> ReadingOutline? {
        let sources = [
            actionPlan.result,
            actionPlan.preview,
            actionPlan.payload
        ]
        let keys = [
            "reading_outline",
            "readingOutline",
            "outline",
            "reading_outline_json"
        ]
        for source in sources {
            guard let source else { continue }
            for key in keys {
                guard let json = source[key],
                      var outline = decodedReadingOutline(fromJSONString: json)
                else { continue }
                if outline.id.isEmpty {
                    outline.id = "outline-\(actionPlan.id)"
                }
                if outline.articleRevisionId.isEmpty,
                   let articleRevisionId = actionPlan.payload["article_revision_id"] ?? actionPlan.payload["articleRevisionId"] {
                    outline.articleRevisionId = articleRevisionId
                }
                if outline.title.isEmpty {
                    outline.title = fallbackTitle
                }
                if outline.status == .draft, actionPlan.status == .succeeded {
                    outline.status = .ready
                }
                if outline.generatedAt == Date(timeIntervalSince1970: 0) {
                    outline.generatedAt = actionPlan.completedAt ?? actionPlan.updatedAt
                }
                if outline.updatedAt == Date(timeIntervalSince1970: 0) {
                    outline.updatedAt = actionPlan.updatedAt > outline.generatedAt ? actionPlan.updatedAt : capturedAt
                }
                return outline
            }
        }
        return nil
    }

    private static func decodedReadingOutline(fromJSONString json: String) -> ReadingOutline? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ReadingOutline.self, from: data)
    }

    private static func generatedOutlineRank(_ status: AgentActionStatus) -> Int {
        switch status {
        case .succeeded:
            return 4
        case .running, .queued:
            return 3
        case .approved:
            return 2
        case .pendingApproval, .draft:
            return 1
        case .failed, .rejected, .cancelled:
            return 0
        }
    }

    private static func generatedOutlineRank(_ status: ResearchPlanStatus) -> Int {
        switch status {
        case .completed:
            return 5
        case .active:
            return 4
        case .draft:
            return 2
        case .failed, .archived:
            return 0
        }
    }

    private static func outlineKind(for blockType: DocumentBlockKind) -> ReadingOutlineItemKind {
        switch blockType {
        case .equation:
            return .equation
        case .abstract, .paragraph:
            return .evidence
        case .section, .subsection:
            return .claim
        case .figure, .table:
            return .method
        case .title, .algorithm, .list, .bibliography, .unknown:
            return .followUpQuestion
        }
    }

    private static func outlineTitle(for block: DocumentBlock) -> String {
        switch block.blockType {
        case .abstract:
            return "Paper claim surface"
        case .equation:
            return block.metadata["equation_number"].map { "Equation \($0)" } ?? "Equation"
        case .section, .subsection:
            return semanticSourceMarkdown(for: block)
        case .paragraph:
            return "Evidence from \(block.structuralPath)"
        case .figure:
            return "Figure evidence"
        case .table:
            return "Table evidence"
        case .title, .algorithm, .list, .bibliography, .unknown:
            return block.blockUid
        }
    }

    private static func outlineSummary(for block: DocumentBlock) -> String {
        let markdown = semanticSourceMarkdown(for: block).trimmingCharacters(in: .whitespacesAndNewlines)
        if markdown.isEmpty {
            return "No extracted text."
        }
        return String(markdown.prefix(150))
    }

    private static func writingPatch(
        from block: DocumentBlock?,
        revisionId: String,
        location: WritingProjectLocation,
        provenance: SourceBlockProvenance,
        selectedText: String?,
        selectedTargetSection: String?,
        now: Date
    ) -> PendingFilePatch {
        let targetPath = location.mainFilePath ?? location.rootPath
        let mainFileText = WritingProjectLocator().mainFileText(for: location) ?? ""
        let targetSectionPreference = WritingTargetSectionResolver.targetPreference(
            for: location,
            selectedTitle: selectedTargetSection
        )
        guard let block else {
            return WritingPatchPlanner()
                .planInsertion(
                    sourceBlock: "Select a source block before preparing an insertion.",
                    targetSectionPreference: targetSectionPreference,
                    mainFileText: mainFileText,
                    fileExtension: URL(fileURLWithPath: targetPath).pathExtension,
                    targetPath: targetPath,
                    patchId: "writing-patch-\(provenance.blockUid)",
                    now: now
                )
                .pendingPatch
        }

        let sourceBlock = selectedText ?? semanticWritingSource(for: block)
        var patch = WritingPatchPlanner()
            .planInsertion(
                sourceBlock: sourceBlock,
                targetSectionPreference: targetSectionPreference,
                mainFileText: mainFileText,
                fileExtension: URL(fileURLWithPath: targetPath).pathExtension,
                targetPath: targetPath,
                patchId: "writing-patch-\(provenance.blockUid)",
                now: now
            )
            .pendingPatch
        patch.provenance = [provenance]
        return patch
    }

    private static func semanticSourceMarkdown(for block: DocumentBlock) -> String {
        ReaderSemanticCopyFormatter.blockMarkdown(markdown: block.sourceMarkdown)
    }

    private static func semanticWritingSource(for block: DocumentBlock) -> String {
        if let latex = block.sourceLatex?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latex.isEmpty {
            return latex
        }
        return semanticSourceMarkdown(for: block)
    }
}

private extension ReadingOutlineStatus {
    var displayName: String {
        switch self {
        case .draft:
            return "Draft"
        case .ready:
            return "Ready"
        case .stale:
            return "Stale"
        }
    }
}

private extension WorkspacePathKind {
    var displayName: String {
        switch self {
        case .bilinLibrary:
            return "Bilin Library"
        case .zoteroLibrary:
            return "Zotero"
        case .obsidianVault:
            return "Obsidian Vault"
        case .writingProjectRoot:
            return "Writing Project"
        }
    }

    var systemImage: String {
        switch self {
        case .bilinLibrary:
            return "books.vertical"
        case .zoteroLibrary:
            return "tray.full"
        case .obsidianVault:
            return "note.text"
        case .writingProjectRoot:
            return "doc.richtext"
        }
    }
}

private extension ExternalFileTargetStatus {
    var displayName: String {
        switch self {
        case .available:
            return "Available"
        case .missing:
            return "Missing"
        case .permissionRequired:
            return "Permission"
        case .unsupported:
            return "Unsupported"
        }
    }

    var recoveryHint: String {
        switch self {
        case .available:
            return "Ready to use."
        case .missing:
            return "The path is no longer present. Choose the location again."
        case .permissionRequired:
            return "macOS denied access. Choose this location again to refresh permission."
        case .unsupported:
            return "The location exists but is not a supported Bilin workspace target."
        }
    }
}

private extension NoteBridgeStatus {
    var displayName: String {
        switch self {
        case .draft:
            return "Draft"
        case .previewReady:
            return "Preview ready"
        case .pendingApproval:
            return "Pending approval"
        case .accepted:
            return "Accepted"
        case .rejected:
            return "Rejected"
        case .conflicted:
            return "Conflicted"
        }
    }
}

private extension AgentActionPlan {
    var belongsToNoteBridge: Bool {
        switch kind {
        case .writeObsidian, .notePatch:
            return true
        case .editManuscript,
             .writingPatch,
             .downloadPaper,
             .importLibrary,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .generateResearchOutline,
             .custom:
            return false
        }
    }

    var belongsToWritingDock: Bool {
        switch kind {
        case .editManuscript, .writingPatch:
            return true
        case .writeObsidian,
             .notePatch,
             .downloadPaper,
             .importLibrary,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .generateResearchOutline,
             .custom:
            return false
        }
    }

    var belongsToResearchPlan: Bool {
        switch kind {
        case .downloadPaper, .importLibrary, .generateResearchOutline:
            return true
        case .writeObsidian,
             .notePatch,
             .editManuscript,
             .writingPatch,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .custom:
            return false
        }
    }

    func belongsToSelectedBlock(_ selectedBlockUid: String?) -> Bool {
        guard let selectedBlockUid else { return false }
        return payload["block_uid"] == selectedBlockUid
    }

    func targetsArticleRevision(_ articleRevisionId: String?) -> Bool {
        guard let articleRevisionId else { return false }
        return payload["article_revision_id"] == articleRevisionId
            || payload["articleRevisionId"] == articleRevisionId
    }

    func targetsZoteroItem(_ zoteroItemId: Int64?) -> Bool {
        guard let zoteroItemId, let payloadItemId = payload["zotero_item_id"] else {
            return false
        }
        return payloadItemId == String(zoteroItemId)
    }

    func targetsFile(_ targetPath: String?) -> Bool {
        guard let targetPath,
              let actionTargetPath = targetFilePath
        else {
            return false
        }
        return Self.normalizedFilePath(actionTargetPath) == Self.normalizedFilePath(targetPath)
    }

    var targetFilePath: String? {
        if let targetPath = Self.firstNonEmptyValue(
            keys: ["target_path", "targetPath"],
            sources: [payload]
        ) {
            return targetPath
        }
        if let stepTargetPath = steps.compactMap(\.targetPath).first(where: { !$0.isEmpty }) {
            return stepTargetPath
        }
        return Self.firstNonEmptyValue(
            keys: [
                "recovery_target_path",
                "recoveryTargetPath",
                "target_path",
                "targetPath"
            ],
            sources: [payload, preview, result, error]
        )
    }

    var expectedBaseFileHash: String? {
        payload["base_file_hash"]
            ?? payload["base_hash"]
            ?? payload["target_content_hash"]
    }

    private static func firstNonEmptyValue(
        keys: [String],
        sources: [[String: String]?]
    ) -> String? {
        for source in sources {
            guard let source else { continue }
            for key in keys {
                if let value = source[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func normalizedFilePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

private extension ResearchPlan {
    func matchesArticleRevision(_ articleRevisionId: String) -> Bool {
        self.articleRevisionId == articleRevisionId
            || readingOutline?.articleRevisionId == articleRevisionId
    }
}

extension ResearchSkill {
    var supportsPaperReading: Bool {
        supportedTasks.isEmpty || supportedTasks.contains(.paperReading)
    }

    var enableAuditSummary: String {
        [
            "\(title) is indexed but disabled. Review its permissions and source before enabling it for reading-outline actions.",
            "Permissions: \(permissions.auditListLabel).",
            "Source: \(sourcePath ?? source.identifier).",
            "Digest: \(shortDigest)."
        ].joined(separator: " ")
    }

    var enableConfirmationMessage: String {
        [
            enableAuditSummary,
            "Bilin will send this digest and permission list to the research backend, then allow the skill to prepare Research Plan outline actions."
        ].joined(separator: " ")
    }

    private var shortDigest: String {
        let normalized = digest.hasPrefix("sha256:") ? String(digest.dropFirst("sha256:".count)) : digest
        guard normalized.count == 64 else { return digest }
        return "sha256:\(normalized.prefix(12))"
    }
}

private extension Array where Element == AgentActionPermission {
    var auditListLabel: String {
        if isEmpty {
            return "none"
        }
        return map(\.auditLabel).joined(separator: ", ")
    }

    var displayListLabel: String {
        if isEmpty {
            return "none"
        }
        return map(\.displayLabel).joined(separator: ", ")
    }
}

private extension AgentActionPermission {
    var auditLabel: String {
        switch self {
        case .network:
            return "network"
        case .providerCall:
            return "provider_call"
        case .downloadPaper:
            return "download_paper"
        case .importLibrary:
            return "import_library"
        case .writeLibraryBundle:
            return "write_library_bundle"
        case .writeObsidian:
            return "write_obsidian"
        case .editManuscript:
            return "edit_manuscript"
        case .runExternalTool:
            return "run_external_tool"
        case .installSkill:
            return "install_skill"
        case .enableSkill:
            return "enable_skill"
        }
    }

    var displayLabel: String {
        switch self {
        case .network:
            return "Network"
        case .providerCall:
            return "Provider call"
        case .downloadPaper:
            return "Download paper"
        case .importLibrary:
            return "Import library"
        case .writeLibraryBundle:
            return "Write library bundle"
        case .writeObsidian:
            return "Write Obsidian"
        case .editManuscript:
            return "Edit manuscript"
        case .runExternalTool:
            return "Run external tool"
        case .installSkill:
            return "Install skill"
        case .enableSkill:
            return "Enable skill"
        }
    }
}

private extension ResearchPlanStatus {
    var readingOutlineStatus: ReadingOutlineStatus {
        switch self {
        case .completed, .active:
            return .ready
        case .draft:
            return .draft
        case .failed, .archived:
            return .stale
        }
    }
}

private extension WritingProjectStatus {
    var displayName: String {
        switch self {
        case .linked:
            return "Linked"
        case .missing:
            return "Missing"
        case .needsMainFile:
            return "Needs main file"
        case .unsupported:
            return "Unsupported"
        }
    }
}

private extension WritingProjectKind {
    var displayName: String {
        switch self {
        case .typst:
            return "Typst"
        case .tex:
            return "TeX"
        case .mixed:
            return "Mixed"
        case .unknown:
            return "Unknown"
        }
    }
}

private extension PendingFilePatchStatus {
    var displayName: String {
        switch self {
        case .draft:
            return "Draft"
        case .previewReady:
            return "Preview ready"
        case .pendingApproval:
            return "Pending approval"
        case .approved:
            return "Approved"
        case .rejected:
            return "Rejected"
        case .applying:
            return "Applying"
        case .applied:
            return "Applied"
        case .conflicted:
            return "Conflicted"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var tint: Color {
        switch self {
        case .previewReady, .approved, .applied:
            return .accentColor
        case .conflicted, .failed:
            return .orange
        case .rejected, .cancelled:
            return .secondary
        case .draft, .pendingApproval, .applying:
            return .secondary
        }
    }
}

private extension PendingFilePatchKind {
    var displayName: String {
        switch self {
        case .obsidianMarkdown:
            return "Obsidian Markdown"
        case .typstInsertion:
            return "Typst insertion"
        case .texInsertion:
            return "TeX insertion"
        case .bibliographyUpdate:
            return "Bibliography update"
        case .libraryNote:
            return "Library note"
        case .exportArtifact:
            return "Export artifact"
        }
    }
}

private extension ReadingOutlineItemKind {
    var displayName: String {
        switch self {
        case .definition:
            return "Definition"
        case .assumption:
            return "Assumption"
        case .method:
            return "Method"
        case .equation:
            return "Equation"
        case .evidence:
            return "Evidence"
        case .limitation:
            return "Limitation"
        case .followUpQuestion:
            return "Question"
        case .claim:
            return "Claim"
        }
    }

    var systemImage: String {
        switch self {
        case .definition:
            return "text.book.closed"
        case .assumption:
            return "line.3.horizontal.decrease.circle"
        case .method:
            return "flowchart"
        case .equation:
            return "function"
        case .evidence:
            return "quote.bubble"
        case .limitation:
            return "exclamationmark.triangle"
        case .followUpQuestion:
            return "questionmark.circle"
        case .claim:
            return "checkmark.seal"
        }
    }
}

private extension AgentActionStatus {
    var displayName: String {
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

private extension AgentActionStepKind {
    var systemImage: String {
        switch self {
        case .previewPatch:
            return "doc.text.magnifyingglass"
        case .writeFile:
            return "square.and.pencil"
        case .download:
            return "arrow.down.doc"
        case .importItem:
            return "square.and.arrow.down"
        case .installSkill:
            return "shippingbox"
        case .enableSkill:
            return "checkmark.seal"
        case .runTool:
            return "terminal"
        case .callProvider:
            return "network"
        case .notify:
            return "bell"
        }
    }
}
