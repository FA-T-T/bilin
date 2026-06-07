import CryptoKit
import Foundation
import BilinWorkspaceKit

public struct ReaderSelectionSnapshot: Codable, Hashable, Sendable {
    public var libraryId: String?
    public var articleId: String?
    public var articleRevisionId: String
    public var blockUid: String
    public var structuralPath: String
    public var contentHash: String
    public var contextHash: String?
    public var sourceLanguage: String?
    public var translationId: String?
    public var translationLanguage: String?
    public var translationHash: String?
    public var selectedTextHash: String?
    public var capturedAt: Date

    public init(
        block: DocumentBlock,
        translation: Translation? = nil,
        article: Article? = nil,
        revision: ArticleRevision? = nil,
        library: Library? = nil,
        sourceLanguage: String? = nil,
        selectedText: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.libraryId = library?.id ?? article?.libraryId
        self.articleId = article?.id ?? revision?.articleId
        self.articleRevisionId = block.articleRevisionId
        self.blockUid = block.blockUid
        self.structuralPath = block.structuralPath
        self.contentHash = block.contentHash
        self.contextHash = block.contextHash
        self.sourceLanguage = Self.resolveSourceLanguage(sourceLanguage, metadata: block.metadata)
        self.translationId = translation?.id
        self.translationLanguage = translation?.targetLanguage
        self.translationHash = translation.map { Self.sha256TextHash(for: $0.rawMarkdown) }
        self.selectedTextHash = Self.sha256TextHash(for: selectedText ?? block.sourceLatex ?? block.sourceMarkdown)
        self.capturedAt = capturedAt
    }

    public var sourceBlockProvenance: SourceBlockProvenance {
        SourceBlockProvenance(
            libraryId: libraryId,
            articleId: articleId,
            articleRevisionId: articleRevisionId,
            blockUid: blockUid,
            structuralPath: structuralPath,
            contentHash: contentHash,
            contextHash: contextHash,
            sourceLanguage: sourceLanguage,
            translationId: translationId,
            translationLanguage: translationLanguage,
            translationHash: translationHash,
            selectedTextHash: selectedTextHash,
            capturedAt: capturedAt
        )
    }

    public func makeSourceBlockProvenance() -> SourceBlockProvenance {
        sourceBlockProvenance
    }

    public static func sha256TextHash(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    private static func resolveSourceLanguage(_ explicit: String?, metadata: [String: String]) -> String? {
        explicit
            ?? metadata["source_language"]
            ?? metadata["sourceLanguage"]
            ?? metadata["language"]
    }
}
