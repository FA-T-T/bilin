import SwiftUI

@main
struct BilinMacApp: App {
    @StateObject private var workspaceDefaults = WorkspaceDefaultsModel()

    var body: some Scene {
        WindowGroup {
            WorkbenchWindowRoot(workspaceDefaults: workspaceDefaults)
        }
        .commands {
            BilinWorkbenchCommands()
        }
        Settings {
            WorkspaceSettingsView()
                .environmentObject(workspaceDefaults)
        }
    }
}
private struct WorkbenchWindowRoot: View {
    private let workspaceDefaults: WorkspaceDefaultsModel
    @StateObject private var session: ReaderWorkbenchSession

    init(workspaceDefaults: WorkspaceDefaultsModel) {
        self.workspaceDefaults = workspaceDefaults
        _session = StateObject(wrappedValue: ReaderWorkbenchSession(workspaceDefaults: workspaceDefaults))
    }

    var body: some View {
        WorkbenchView()
            .environmentObject(session)
            .environmentObject(workspaceDefaults)
            .focusedObject(session)
            .task {
                await session.loadInitialWorkbench()
            }
    }
}

private struct ReaderInspectorPresentedFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct ResearchWorkbenchModeRawValueFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<String>
}

extension FocusedValues {
    var readerInspectorPresented: Binding<Bool>? {
        get { self[ReaderInspectorPresentedFocusedValueKey.self] }
        set { self[ReaderInspectorPresentedFocusedValueKey.self] = newValue }
    }

    var researchWorkbenchModeRawValue: Binding<String>? {
        get { self[ResearchWorkbenchModeRawValueFocusedValueKey.self] }
        set { self[ResearchWorkbenchModeRawValueFocusedValueKey.self] = newValue }
    }
}

private struct BilinWorkbenchCommands: Commands {
    @FocusedObject private var session: ReaderWorkbenchSession?
    @FocusedValue(\.readerInspectorPresented) private var readerInspectorPresented: Binding<Bool>?
    @FocusedValue(\.researchWorkbenchModeRawValue) private var researchWorkbenchModeRawValue: Binding<String>?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Library...") {
                guard let session else { return }
                Task {
                    await session.openLibraryFromPanel()
                }
            }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(session == nil)
            Button("Open Zotero Library...") {
                guard let session else { return }
                Task {
                    await session.openZoteroLibraryFromPanel()
                }
            }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(session == nil)
        }
        CommandMenu("Reader") {
            Button("Check Research API") {
                guard let session else { return }
                showResearchWorkbenchMode(.researchPlan)
                Task {
                    await session.refreshResearchWorkbench()
                }
            }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(session == nil || (session?.researchAPIBusy ?? false))
                .help("Check the local research backend and refresh workbench state.")
            Button("Equation Editor...") {
                session?.openEquationEditor()
            }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(session == nil)
            Divider()
            Button("Show Note Bridge") {
                showResearchWorkbenchMode(.noteBridge)
            }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(!canShowResearchWorkbenchMode)
                .help("Open the research tools rail and show Note Bridge.")
            Button("Show Research Plan") {
                showResearchWorkbenchMode(.researchPlan)
            }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(!canShowResearchWorkbenchMode)
                .help("Open the research tools rail and show Research Plan.")
            Button("Show Writing Dock") {
                showResearchWorkbenchMode(.writingDock)
            }
                .keyboardShortcut("3", modifiers: [.command, .option])
                .disabled(!canShowResearchWorkbenchMode)
                .help("Open the research tools rail and show Writing Dock.")
            Divider()
            Button("Copy Reader Selection as Markdown") {
                guard
                    let text = session?.selectedReaderText,
                    !text.isEmpty
                else { return }
                ReaderClipboard.copy(text)
            }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled((session?.selectedReaderText ?? "").isEmpty)
                .help("Copy the selected reader text with inline math and citations preserved as Markdown.")
            Button("Copy Selected Block Markdown") {
                guard let block = session?.selectedBlock else { return }
                ReaderClipboard.copy(ReaderBlockClipboardPayload.sourceText(for: block))
            }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(session?.selectedBlock == nil)
                .help("Copy the selected reader block as semantic Markdown.")
            Divider()
            Button("Prepare Obsidian Note Patch...") {
                guard let session else { return }
                showResearchWorkbenchMode(.noteBridge)
                Task {
                    await session.prepareSelectedBlockNoteActionPlan()
                }
            }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!(session?.canPrepareSelectedBlockNoteActionPlan ?? false))
                .help("Prepare a confirmable AgentActionPlan before writing to Obsidian.")
            Button("Prepare Writing Patch...") {
                guard let session else { return }
                showResearchWorkbenchMode(.writingDock)
                Task {
                    await session.prepareSelectedBlockWritingActionPlan()
                }
            }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!(session?.canPrepareSelectedBlockWritingActionPlan ?? false))
                .help("Prepare a confirmable AgentActionPlan before editing the linked Typst or TeX project.")
            Button("Prepare Reading Outline...") {
                guard let session else { return }
                showResearchWorkbenchMode(.researchPlan)
                Task {
                    await session.prepareSelectedArticleReadingOutlineActionPlan()
                }
            }
                .disabled(!(session?.canPrepareSelectedArticleReadingOutlineActionPlan ?? false))
                .help("Prepare a confirmable AgentActionPlan for a paper-specific reading outline.")
        }
    }

    private var canShowResearchWorkbenchMode: Bool {
        guard let session else { return false }
        return readerInspectorPresented != nil
            && researchWorkbenchModeRawValue != nil
            && (
                session.selectedZoteroItem != nil
                    || session.selectedArticle != nil
                    || !session.blocks.isEmpty
            )
    }

    private func showResearchWorkbenchMode(_ mode: ResearchWorkbenchMode) {
        researchWorkbenchModeRawValue?.wrappedValue = mode.rawValue
        readerInspectorPresented?.wrappedValue = true
    }
}
