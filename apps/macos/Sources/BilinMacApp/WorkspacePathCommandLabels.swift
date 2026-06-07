import BilinWorkspaceKit

enum WorkspacePathCommandLabels {
    static func useDetectedTitle(for kind: WorkspacePathKind) -> String {
        switch kind {
        case .bilinLibrary:
            return "Use Bilin Library"
        case .zoteroLibrary:
            return "Use Zotero Library"
        case .obsidianVault:
            return "Use Obsidian Vault"
        case .writingProjectRoot:
            return "Use Writing Project"
        }
    }
}
