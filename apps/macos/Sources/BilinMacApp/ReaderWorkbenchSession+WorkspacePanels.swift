import AppKit
import BilinWorkspaceKit

@MainActor
extension ReaderWorkbenchSession {
    func openEquationEditor() {
        equationEditorPresented = true
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

    func chooseObsidianVaultFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Obsidian Vault"
        panel.message = "Choose the Markdown vault Ilios should prepare note patches for."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspaceDefaults.persistWorkspacePath(url: url, kind: .obsidianVault)
    }

    func chooseWritingProjectFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Writing Project"
        panel.message = "Choose the Typst or TeX project root for manuscript patch previews."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspaceDefaults.persistWorkspacePath(url: url, kind: .writingProjectRoot)
    }

    func detectWorkspacePaths() {
        workspaceDefaults.detectWorkspacePaths()
        researchWorkbenchStatus = workspaceDefaults.detectedWorkspacePaths.isEmpty
            ? "No local apps found"
            : "Local apps detected"
        researchWorkbenchError = nil
    }

    func useDetectedWorkspacePath(_ record: WorkspacePathRecord) async {
        guard record.status == .available else {
            workspaceDefaults.useDetectedWorkspacePath(record)
            researchWorkbenchStatus = "Location unavailable"
            researchWorkbenchError = Self.unavailableDetectedWorkspacePathMessage(record)
            return
        }

        switch record.kind {
        case .zoteroLibrary:
            await openZoteroLibrary(at: URL(fileURLWithPath: record.path, isDirectory: true))
        case .bilinLibrary:
            await openLibrary(at: URL(fileURLWithPath: record.path, isDirectory: true))
        case .obsidianVault, .writingProjectRoot:
            workspaceDefaults.useDetectedWorkspacePath(record)
            researchWorkbenchStatus = "Location configured"
            researchWorkbenchError = nil
        }
    }

    private static func unavailableDetectedWorkspacePathMessage(_ record: WorkspacePathRecord) -> String {
        "\(record.name) is \(record.status.recoveryLabel): \(record.path)"
    }
}

private extension ExternalFileTargetStatus {
    var recoveryLabel: String {
        switch self {
        case .available:
            return "available"
        case .missing:
            return "missing"
        case .permissionRequired:
            return "not readable"
        case .unsupported:
            return "unsupported"
        }
    }
}
