import Foundation

public enum ReaderLibrarySelection: Codable, Hashable, Sendable {
    case article(id: String)
    case zoteroItem(id: Int64)

    public var articleId: String? {
        guard case .article(let id) = self else { return nil }
        return id
    }

    public var zoteroItemId: Int64? {
        guard case .zoteroItem(let id) = self else { return nil }
        return id
    }
}
