import SwiftUI
import AppKit
import BilinWorkspaceKit

@MainActor
final class WorkspaceDefaultsModel: ObservableObject {
    @Published var workspaceConfiguration: WorkspaceConfiguration
    @Published var workspaceConfigurationError: String?
    @Published var detectedWorkspacePaths: [WorkspacePathRecord]
    @Published var writingProjectLocation: WritingProjectLocation

    private let workspaceConfigurationCoordinator: WorkspaceConfigurationCoordinator

    init(
        workspaceConfigurationCoordinator: WorkspaceConfigurationCoordinator = .defaultCoordinator()
    ) {
        self.workspaceConfigurationCoordinator = workspaceConfigurationCoordinator
        do {
            workspaceConfiguration = try workspaceConfigurationCoordinator.refreshConfiguredPathStatuses()
            workspaceConfigurationError = nil
        } catch {
            workspaceConfiguration = WorkspaceConfiguration()
            workspaceConfigurationError = error.localizedDescription
        }
        detectedWorkspacePaths = workspaceConfigurationCoordinator.detectPathRecords()
        writingProjectLocation = Self.unconfiguredWritingProjectLocation()
        refreshWritingProjectLocation()
    }

    func chooseBilinLibraryFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Default Bilin Library"
        panel.message = "Choose the Bilin library folder future reader windows should open by default."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        persistWorkspacePath(url: url, kind: .bilinLibrary)
    }

    func chooseZoteroLibraryFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Default Zotero Library"
        panel.message = "Choose the Zotero data directory or zotero.sqlite future reader windows should use by default."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        persistWorkspacePath(url: url, kind: .zoteroLibrary)
    }

    func chooseObsidianVaultFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Obsidian Vault"
        panel.message = "Choose the Markdown vault Ilios should prepare note patches for."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        persistWorkspacePath(url: url, kind: .obsidianVault)
    }

    func chooseWritingProjectFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Writing Project"
        panel.message = "Choose the Typst or TeX project root for manuscript patch previews."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        persistWorkspacePath(url: url, kind: .writingProjectRoot)
    }

    func detectWorkspacePaths() {
        do {
            workspaceConfiguration = try workspaceConfigurationCoordinator.refreshConfiguredPathStatuses()
            detectedWorkspacePaths = workspaceConfigurationCoordinator.detectPathRecords()
            workspaceConfigurationError = nil
            refreshWritingProjectLocation()
        } catch {
            workspaceConfigurationError = error.localizedDescription
        }
    }

    func uniqueAvailableDetectedWorkspacePath(kind: WorkspacePathKind) -> WorkspacePathRecord? {
        let matches = detectedWorkspacePaths.filter { record in
            record.kind == kind && record.status == .available
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    func useDetectedWorkspacePath(_ record: WorkspacePathRecord) {
        guard record.status == .available else {
            workspaceConfigurationError = "\(record.path) is not available."
            return
        }
        persistDetectedWorkspacePath(record)
    }

    func forgetWorkspacePath(_ record: WorkspacePathRecord) {
        do {
            workspaceConfiguration = try workspaceConfigurationCoordinator.removePathRecord(record)
            workspaceConfigurationError = nil
            detectedWorkspacePaths = workspaceConfigurationCoordinator.detectPathRecords()
            refreshWritingProjectLocation()
        } catch {
            workspaceConfigurationError = error.localizedDescription
        }
    }

    func persistWorkspacePath(url: URL, kind: WorkspacePathKind) {
        do {
            workspaceConfiguration = try workspaceConfigurationCoordinator.persistPath(url: url, kind: kind)
            workspaceConfigurationError = nil
            detectedWorkspacePaths = workspaceConfigurationCoordinator.detectPathRecords()
            refreshWritingProjectLocation()
        } catch {
            workspaceConfigurationError = error.localizedDescription
        }
    }

    private func persistDetectedWorkspacePath(_ record: WorkspacePathRecord) {
        do {
            workspaceConfiguration = try workspaceConfigurationCoordinator.persistDetectedPathRecord(record)
            workspaceConfigurationError = nil
            detectedWorkspacePaths = workspaceConfigurationCoordinator.detectPathRecords()
            refreshWritingProjectLocation()
        } catch {
            workspaceConfigurationError = error.localizedDescription
        }
    }

    private func refreshWritingProjectLocation() {
        guard let root = workspaceConfiguration.writingProjectRoots.first else {
            writingProjectLocation = Self.unconfiguredWritingProjectLocation()
            return
        }
        writingProjectLocation = WritingProjectLocator().locate(rootPath: root.path)
    }

    private static func unconfiguredWritingProjectLocation() -> WritingProjectLocation {
        WritingProjectLocation(
            rootPath: "Choose a writing project",
            kind: .unknown,
            status: .missing,
            mainFilePath: nil,
            bibliographyFilePaths: [],
            detectedFilePaths: []
        )
    }
}
