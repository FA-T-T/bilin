import SwiftUI
import AppKit
import BilinWorkspaceKit

struct WorkspaceSettingsView: View {
    @EnvironmentObject private var defaults: WorkspaceDefaultsModel

    var body: some View {
        TabView {
            WorkspaceLocationsSettingsTab()
                .environmentObject(defaults)
                .tabItem {
                    Label("Locations", systemImage: "folder")
                }
        }
        .frame(width: 700, height: 560)
    }
}

private struct WorkspaceLocationsSettingsTab: View {
    @EnvironmentObject private var defaults: WorkspaceDefaultsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("External Locations")
                    .font(.title2.weight(.semibold))
                Text("Manage local libraries, note vaults, Zotero metadata, and writing projects.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Form {
                Section("Configured") {
                    WorkspaceConfiguredLocationRow(
                        title: "Bilin Library",
                        record: defaults.workspaceConfiguration.selectedBilinLibrary,
                        emptyValue: "No library selected",
                        chooseLabel: "Set Default Library",
                        detectedSuggestion: nil,
                        onChoose: {
                            defaults.chooseBilinLibraryFromPanel()
                        },
                        onUseDetected: { record in
                            defaults.useDetectedWorkspacePath(record)
                        },
                        onForget: { record in
                            defaults.forgetWorkspacePath(record)
                        }
                    )

                    WorkspaceConfiguredLocationRow(
                        title: "Zotero Library",
                        record: defaults.workspaceConfiguration.selectedZoteroLibrary,
                        emptyValue: "No Zotero data directory selected",
                        chooseLabel: "Set Default Zotero",
                        detectedSuggestion: defaults.uniqueAvailableDetectedWorkspacePath(kind: .zoteroLibrary),
                        onChoose: {
                            defaults.chooseZoteroLibraryFromPanel()
                        },
                        onUseDetected: { record in
                            defaults.useDetectedWorkspacePath(record)
                        },
                        onForget: { record in
                            defaults.forgetWorkspacePath(record)
                        }
                    )

                    WorkspaceConfiguredLocationRow(
                        title: "Obsidian Vault",
                        record: defaults.workspaceConfiguration.selectedObsidianVault,
                        emptyValue: "No vault selected",
                        chooseLabel: "Choose Vault",
                        detectedSuggestion: defaults.uniqueAvailableDetectedWorkspacePath(kind: .obsidianVault),
                        onChoose: {
                            defaults.chooseObsidianVaultFromPanel()
                        },
                        onUseDetected: { record in
                            defaults.useDetectedWorkspacePath(record)
                        },
                        onForget: { record in
                            defaults.forgetWorkspacePath(record)
                        }
                    )

                    WorkspaceConfiguredLocationRow(
                        title: "Writing Project",
                        record: defaults.workspaceConfiguration.writingProjectRoots.first,
                        emptyValue: "No Typst or TeX project selected",
                        chooseLabel: "Choose Project",
                        detectedSuggestion: nil,
                        onChoose: {
                            defaults.chooseWritingProjectFromPanel()
                        },
                        onUseDetected: { record in
                            defaults.useDetectedWorkspacePath(record)
                        },
                        onForget: { record in
                            defaults.forgetWorkspacePath(record)
                        }
                    )
                }

                Section("Detected") {
                    HStack {
                        Text("Local Apps")
                        Spacer()
                        Button {
                            defaults.detectWorkspacePaths()
                        } label: {
                            Label("Detect Local Apps", systemImage: "magnifyingglass")
                        }
                    }

                    if defaults.detectedWorkspacePaths.isEmpty {
                        WorkspaceSettingsEmptyRow(text: "No Obsidian or Zotero locations detected yet.")
                    } else {
                        ForEach(defaults.detectedWorkspacePaths) { record in
                            WorkspaceDetectedLocationRow(
                                record: record,
                                isConfigured: isConfigured(record)
                            ) {
                                defaults.useDetectedWorkspacePath(record)
                            }
                        }
                    }
                }

                if let workspaceConfigurationError = defaults.workspaceConfigurationError {
                    Section("Configuration Error") {
                        Text(workspaceConfigurationError)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(24)
    }

    private func isConfigured(_ record: WorkspacePathRecord) -> Bool {
        switch record.kind {
        case .bilinLibrary:
            defaults.workspaceConfiguration.selectedBilinLibrary?.path == record.path
        case .zoteroLibrary:
            defaults.workspaceConfiguration.selectedZoteroLibrary?.path == record.path
        case .obsidianVault:
            defaults.workspaceConfiguration.selectedObsidianVault?.path == record.path
        case .writingProjectRoot:
            defaults.workspaceConfiguration.writingProjectRoots.contains { $0.path == record.path }
        }
    }
}

private struct WorkspaceConfiguredLocationRow: View {
    var title: String
    var record: WorkspacePathRecord?
    var emptyValue: String
    var chooseLabel: String
    var detectedSuggestion: WorkspacePathRecord?
    var onChoose: () -> Void
    var onUseDetected: (WorkspacePathRecord) -> Void
    var onForget: (WorkspacePathRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .frame(width: 128, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record?.name ?? emptyValue)
                        .foregroundStyle(record == nil ? .secondary : .primary)
                    if let record {
                        WorkspaceSelectablePathText(path: record.path)
                        if record.status != .available {
                            Text(record.status.recoveryHint)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if let detectedSuggestion {
                        Text("Detected \(detectedSuggestion.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        WorkspaceSelectablePathText(path: detectedSuggestion.path)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
                Spacer(minLength: 12)
                if let record {
                    WorkspaceStatusPill(record: record)
                    Button {
                        WorkspaceSettingsActions.reveal(record)
                    } label: {
                        Label("Show in Finder", systemImage: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                    .help("Show in Finder")
                    Button(role: .destructive) {
                        onForget(record)
                    } label: {
                        Label("Forget Location", systemImage: "minus.circle")
                    }
                    .labelStyle(.iconOnly)
                    .help("Forget this configured location without deleting any local files")
                }
                if record == nil, let detectedSuggestion {
                    Button {
                        onUseDetected(detectedSuggestion)
                    } label: {
                        Label(WorkspacePathCommandLabels.useDetectedTitle(for: detectedSuggestion.kind), systemImage: "checkmark")
                    }
                    .disabled(detectedSuggestion.status != .available)
                }
                Button(action: onChoose) {
                    Text(chooseLabel)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WorkspaceDetectedLocationRow: View {
    var record: WorkspacePathRecord
    var isConfigured: Bool
    var onUse: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label(record.kind.displayName, systemImage: record.kind.systemImage)
                .frame(width: 128, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.name)
                WorkspaceSelectablePathText(path: record.path)
                if record.status != .available {
                    Text(record.status.recoveryHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            Spacer(minLength: 12)
            WorkspaceStatusPill(record: record)
            Button {
                WorkspaceSettingsActions.reveal(record)
            } label: {
                Label("Show in Finder", systemImage: "magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help("Show in Finder")
            if isConfigured {
                Text("Configured")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button(WorkspacePathCommandLabels.useDetectedTitle(for: record.kind)) {
                    onUse()
                }
                .disabled(record.status != .available)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WorkspaceSettingsEmptyRow: View {
    var text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }
}

private struct WorkspaceSelectablePathText: View {
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

private struct WorkspaceStatusPill: View {
    var record: WorkspacePathRecord

    var body: some View {
        Label(record.status.displayName, systemImage: record.status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(record.status == .available ? Color.accentColor : Color.orange)
            .background(
                record.status == .available ? Color.accentColor.opacity(0.12) : Color.orange.opacity(0.12),
                in: Capsule()
            )
    }
}

private enum WorkspaceSettingsActions {
    static func reveal(_ record: WorkspacePathRecord) {
        let url = URL(fileURLWithPath: record.path)
        if FileManager.default.fileExists(atPath: record.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.selectFile(
                record.path,
                inFileViewerRootedAtPath: url.deletingLastPathComponent().path
            )
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

    var systemImage: String {
        switch self {
        case .available:
            return "checkmark.circle"
        case .missing:
            return "exclamationmark.triangle"
        case .permissionRequired:
            return "lock"
        case .unsupported:
            return "slash.circle"
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
