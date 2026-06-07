import Foundation
import AppKit
import XCTest
import BilinReaderKit
import BilinRenderKit
import BilinWorkspaceKit
@testable import BilinMacApp

@MainActor
final class RatexRenderCacheStoreTests: XCTestCase {
    func testCoalescesConcurrentRequestsForSameKey() async {
        let store = RatexRenderCacheStore(maxConcurrentRenders: 4)
        let key = makeKey(latex: "x")
        let counter = LockedCounter()

        async let first = store.result(for: key) {
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return Self.svgResult(latex: "x")
        }
        async let second = store.result(for: key) {
            counter.increment()
            return Self.svgResult(latex: "x")
        }

        let results = await [first, second]

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(results.map(\.latex), ["x", "x"])
    }

    func testLimitsConcurrentRendersAcrossDistinctKeys() async {
        let store = RatexRenderCacheStore(maxConcurrentRenders: 1)
        let probe = RenderConcurrencyProbe()

        async let first = store.result(for: makeKey(latex: "x")) {
            probe.render(latex: "x")
        }
        async let second = store.result(for: makeKey(latex: "y")) {
            probe.render(latex: "y")
        }

        _ = await [first, second]

        XCTAssertEqual(probe.maximumRunningCount, 1)
    }

    func testCachesUnavailableResultUntilFailureTTLExpires() async {
        var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            failureCacheDuration: 5,
            now: { currentDate }
        )
        let key = makeKey(latex: "bad")
        let counter = LockedCounter()

        let first = await store.result(for: key) {
            counter.increment()
            return Self.unavailableResult(latex: "bad")
        }
        let second = await store.result(for: key) {
            counter.increment()
            return Self.svgResult(latex: "bad")
        }
        currentDate = currentDate.addingTimeInterval(6)
        let third = await store.result(for: key) {
            counter.increment()
            return Self.svgResult(latex: "bad")
        }

        XCTAssertEqual(counter.value, 2)
        guard case .unavailable = first.payload else {
            return XCTFail("Expected first render to be unavailable")
        }
        guard case .unavailable = second.payload else {
            return XCTFail("Expected cached failure before TTL expiry")
        }
        guard case .svg = third.payload else {
            return XCTFail("Expected render retry after TTL expiry")
        }
    }

    func testLoadsDiskCachedSVGWithoutRerenderingAfterMemoryCacheMiss() async {
        let key = makeKey(latex: "disk-cached")
        let diskCacheDirectoryURL = temporaryDirectory()
        let firstStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: diskCacheDirectoryURL.path))
        let firstRender = await firstStore.result(for: key) {
            Self.svgResult(latex: "disk-cached")
        }
        guard case .svg = firstRender.payload else {
            return XCTFail("Expected initial SVG render")
        }

        let diskProbeStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        guard let diskCachedResult = await waitForDiskCachedResult(in: diskProbeStore, for: key) else {
            return XCTFail("Expected SVG to be stored on disk")
        }
        XCTAssertEqual(diskCachedResult.latex, "disk-cached")
        let secondStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        XCTAssertNil(secondStore.cachedResidentResult(for: key))
        let rerenderCounter = LockedCounter()
        let secondRender = await secondStore.result(for: key) {
            rerenderCounter.increment()
            return Self.svgResult(latex: "rerendered")
        }

        XCTAssertEqual(rerenderCounter.value, 0)
        XCTAssertEqual(secondRender.latex, "disk-cached")
        XCTAssertEqual(secondStore.cachedResidentResult(for: key)?.latex, "disk-cached")
    }

    func testResidentCacheDoesNotSynchronouslyReadDiskCache() async {
        let key = makeKey(latex: "resident-cache")
        let diskCacheDirectoryURL = temporaryDirectory()
        let firstStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        _ = await firstStore.result(for: key) {
            Self.svgResult(latex: "resident-cache")
        }
        let diskProbeStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        guard await waitForDiskCachedResult(in: diskProbeStore, for: key) != nil else {
            return XCTFail("Expected SVG to be stored on disk")
        }

        let residentOnlyStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )

        XCTAssertNil(residentOnlyStore.cachedResidentResult(for: key))
        XCTAssertEqual(residentOnlyStore.cachedResult(for: key)?.latex, "resident-cache")
    }

    func testPersistedCacheLookupWarmsResidentCacheWithoutRendering() async {
        let key = makeKey(latex: "persisted-cache")
        let diskCacheDirectoryURL = temporaryDirectory()
        let firstStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        let firstRender = await firstStore.result(for: key) {
            Self.svgResult(latex: "persisted-cache")
        }
        guard case .svg = firstRender.payload else {
            return XCTFail("Expected initial SVG render")
        }
        let diskProbeStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        guard await waitForDiskCachedResult(in: diskProbeStore, for: key) != nil else {
            return XCTFail("Expected SVG to be stored on disk")
        }

        let reopenedStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )

        XCTAssertNil(reopenedStore.cachedResidentResult(for: key))
        let cachedResult = await reopenedStore.cachedPersistedResult(for: key)

        XCTAssertEqual(cachedResult?.latex, "persisted-cache")
        XCTAssertEqual(reopenedStore.cachedResidentResult(for: key)?.latex, "persisted-cache")
    }

    func testBatchPersistedCacheLookupWarmsResidentCacheWithoutRendering() async {
        let firstKey = makeKey(latex: "batch-persisted-first")
        let secondKey = makeKey(latex: "batch-persisted-second")
        let missingKey = makeKey(latex: "batch-persisted-missing")
        let diskCacheDirectoryURL = temporaryDirectory()
        let firstStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        _ = await firstStore.result(for: firstKey) {
            Self.svgResult(latex: "batch-persisted-first")
        }
        _ = await firstStore.result(for: secondKey) {
            Self.svgResult(latex: "batch-persisted-second")
        }
        let diskProbeStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        guard await waitForDiskCachedResult(in: diskProbeStore, for: firstKey) != nil,
              await waitForDiskCachedResult(in: diskProbeStore, for: secondKey) != nil
        else {
            return XCTFail("Expected SVGs to be stored on disk")
        }

        let reopenedStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        let cachedResults = await reopenedStore.cachedPersistedResults(
            for: [firstKey, secondKey, firstKey, missingKey]
        )

        XCTAssertEqual(Set(cachedResults.keys), Set([firstKey, secondKey]))
        XCTAssertEqual(cachedResults[firstKey]?.latex, "batch-persisted-first")
        XCTAssertEqual(cachedResults[secondKey]?.latex, "batch-persisted-second")
        XCTAssertNil(cachedResults[missingKey])
        XCTAssertEqual(reopenedStore.cachedResidentResult(for: firstKey)?.latex, "batch-persisted-first")
        XCTAssertEqual(reopenedStore.cachedResidentResult(for: secondKey)?.latex, "batch-persisted-second")

        let rerenderCounter = LockedCounter()
        _ = await reopenedStore.result(for: firstKey) {
            rerenderCounter.increment()
            return Self.svgResult(latex: "rerendered-first")
        }
        _ = await reopenedStore.result(for: secondKey) {
            rerenderCounter.increment()
            return Self.svgResult(latex: "rerendered-second")
        }

        XCTAssertEqual(rerenderCounter.value, 0)
    }

    func testConcurrentPersistedCacheLookupsCoalesceDiskReadsForSameKey() async {
        let key = makeKey(latex: "coalesced-persisted")
        let diskCacheDirectoryURL = temporaryDirectory()
        let firstStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        _ = await firstStore.result(for: key) {
            Self.svgResult(latex: "coalesced-persisted")
        }
        let diskProbeStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL
        )
        guard await waitForDiskCachedResult(in: diskProbeStore, for: key) != nil else {
            return XCTFail("Expected SVG to be stored on disk")
        }

        let readCounter = LockedCounter()
        let reopenedStore = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL,
            diskCacheReadObserverForTesting: { observedKey in
                guard observedKey == key else { return }
                readCounter.increment()
                Thread.sleep(forTimeInterval: 0.05)
            }
        )

        async let first = reopenedStore.cachedPersistedResult(for: key)
        async let second = reopenedStore.cachedPersistedResult(for: key)
        async let batch = reopenedStore.cachedPersistedResults(for: [key, key])
        let (firstResult, secondResult, batchResult) = await (first, second, batch)

        XCTAssertEqual(firstResult?.latex, "coalesced-persisted")
        XCTAssertEqual(secondResult?.latex, "coalesced-persisted")
        XCTAssertEqual(batchResult[key]?.latex, "coalesced-persisted")
        XCTAssertEqual(readCounter.value, 1)
        XCTAssertEqual(reopenedStore.cachedResidentResult(for: key)?.latex, "coalesced-persisted")
    }

    func testPersistedCacheMissReturnsResidentResultStoredDuringLookup() async {
        let key = makeKey(latex: "resident-during-miss")
        let diskCacheDirectoryURL = temporaryDirectory()
        let readCounter = LockedCounter()
        let store = RatexRenderCacheStore(
            maxConcurrentRenders: 1,
            diskCacheDirectoryURL: diskCacheDirectoryURL,
            diskCacheReadObserverForTesting: { observedKey in
                guard observedKey == key else { return }
                readCounter.increment()
                Thread.sleep(forTimeInterval: 0.05)
            }
        )

        async let lookup = store.cachedPersistedResult(for: key)
        try? await Task.sleep(nanoseconds: 10_000_000)
        store.store(Self.svgResult(latex: "resident-during-miss"), for: key)
        let result = await lookup

        XCTAssertEqual(result?.latex, "resident-during-miss")
        XCTAssertEqual(readCounter.value, 1)
        XCTAssertEqual(store.cachedResidentResult(for: key)?.latex, "resident-during-miss")
    }

    func testMemoryCacheEvictsLeastRecentlyUsedResult() async {
        let store = RatexRenderCacheStore(maxMemoryResults: 2, maxConcurrentRenders: 1)
        let firstKey = makeKey(latex: "first")
        let secondKey = makeKey(latex: "second")
        let thirdKey = makeKey(latex: "third")

        _ = await store.result(for: firstKey) {
            Self.svgResult(latex: "first")
        }
        _ = await store.result(for: secondKey) {
            Self.svgResult(latex: "second")
        }
        XCTAssertEqual(store.cachedMemoryResultForTesting(for: firstKey)?.latex, "first")
        _ = await store.result(for: thirdKey) {
            Self.svgResult(latex: "third")
        }

        XCTAssertEqual(store.cachedMemoryResultForTesting(for: firstKey)?.latex, "first")
        XCTAssertNil(store.cachedMemoryResultForTesting(for: secondKey))
        XCTAssertEqual(store.cachedMemoryResultForTesting(for: thirdKey)?.latex, "third")
    }

    func testCancelledRequestReturnsFallbackWithoutRendering() async {
        let store = RatexRenderCacheStore(maxConcurrentRenders: 1)
        let key = makeKey(latex: "cancelled")
        let token = RatexRenderCancellationToken()
        let counter = LockedCounter()
        token.cancel()

        let result = await store.result(
            for: key,
            isCancelled: { token.isCancelled },
            cancelledResult: {
                Self.unavailableResult(latex: "cancelled")
            }
        ) {
            counter.increment()
            return Self.svgResult(latex: "cancelled")
        }

        XCTAssertEqual(counter.value, 0)
        guard case .unavailable = result.payload else {
            return XCTFail("Expected cancelled fallback result")
        }
    }

    private func makeKey(latex: String) -> RatexRenderCacheKey {
        RatexRenderCacheKey(
            latex: latex,
            layoutMode: .block,
            options: RatexRenderOptions(timeoutSeconds: 1),
            rendererIdentifier: "test-renderer-\(UUID().uuidString)"
        )
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("bilin-ratex-cache-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitForDiskCachedResult(
        in store: RatexRenderCacheStore,
        for key: RatexRenderCacheKey
    ) async -> MathRenderResult? {
        for _ in 0..<50 {
            if let result = store.cachedResult(for: key) {
                return result
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }

    nonisolated private static func svgResult(latex: String) -> MathRenderResult {
        MathRenderResult(
            latex: latex,
            mode: .display,
            accessibilityLabel: latex,
            payload: .svg(#"<svg xmlns="http://www.w3.org/2000/svg"></svg>"#)
        )
    }

    nonisolated private static func unavailableResult(latex: String) -> MathRenderResult {
        MathRenderResult(
            latex: latex,
            mode: .display,
            accessibilityLabel: latex,
            payload: .unavailable(reason: "missing render-svg")
        )
    }
}

@MainActor
final class ReaderWorkbenchSessionSelectionTests: XCTestCase {
    func testReaderTextSelectionIsDebouncedAndKeepsBlockSelectionImmediate() async throws {
        let session = ReaderWorkbenchSession()

        session.updateReaderTextSelection(blockUid: "block-1", selectedText: " first ")
        XCTAssertEqual(session.selectedBlockUid, "block-1")
        XCTAssertNil(session.readerTextSelection)
        XCTAssertEqual(session.readerTextSelection(for: "block-1")?.text, " first ")

        session.updateReaderTextSelection(blockUid: "block-1", selectedText: " second ")
        XCTAssertEqual(session.readerTextSelection(for: "block-1")?.text, " second ")
        try await Task.sleep(nanoseconds: 130_000_000)

        XCTAssertEqual(session.readerTextSelection?.blockUid, "block-1")
        XCTAssertEqual(session.readerTextSelection?.text, " second ")
    }

    func testPendingReaderTextSelectionImmediatelyFeedsCurrentReaderActions() {
        let session = ReaderWorkbenchSession()

        session.updateReaderTextSelection(blockUid: "block-1", selectedText: " immediate excerpt ")

        XCTAssertNil(session.readerTextSelection)
        XCTAssertEqual(session.readerTextSelection(for: "block-1")?.text, " immediate excerpt ")
    }

    func testPendingReaderTextSelectionClearHidesCommittedExcerptImmediately() {
        let session = ReaderWorkbenchSession()
        session.readerTextSelection = ReaderTextSelection(
            blockUid: "block-1",
            text: "old excerpt",
            textHash: ReaderSelectionSnapshot.sha256TextHash(for: "old excerpt")
        )

        session.updateReaderTextSelection(blockUid: "block-1", selectedText: nil)

        XCTAssertEqual(session.readerTextSelection?.text, "old excerpt")
        XCTAssertNil(session.readerTextSelection(for: "block-1"))
    }

    func testPendingReaderTextSelectionCanBeFlushedBeforeDebounceCompletes() {
        let session = ReaderWorkbenchSession()

        session.updateReaderTextSelection(blockUid: "block-1", selectedText: " quoted excerpt ")
        XCTAssertNil(session.readerTextSelection)

        session.flushPendingReaderTextSelection()

        XCTAssertEqual(session.readerTextSelection?.blockUid, "block-1")
        XCTAssertEqual(session.readerTextSelection?.text, " quoted excerpt ")
    }

    func testReaderTextSelectionPreservesExactSelectionForNotebookExcerptHash() {
        let session = ReaderWorkbenchSession()
        let selectedText = "  exact excerpt with boundary space\n"

        session.updateReaderTextSelection(blockUid: "block-1", selectedText: selectedText)
        session.flushPendingReaderTextSelection()

        XCTAssertEqual(session.readerTextSelection?.text, selectedText)
        XCTAssertEqual(
            session.readerTextSelection?.textHash,
            ReaderSelectionSnapshot.sha256TextHash(for: selectedText)
        )
    }

    func testWhitespaceOnlyReaderTextSelectionClearsCurrentBlockSelection() {
        let session = ReaderWorkbenchSession()
        session.readerTextSelection = ReaderTextSelection(
            blockUid: "block-1",
            text: "old excerpt",
            textHash: ReaderSelectionSnapshot.sha256TextHash(for: "old excerpt")
        )

        session.updateReaderTextSelection(blockUid: "block-1", selectedText: " \n\t ")
        session.flushPendingReaderTextSelection()

        XCTAssertNil(session.readerTextSelection)
    }

    func testManualBlockSelectionDiscardsPendingReaderTextSelection() async throws {
        let session = ReaderWorkbenchSession()

        session.updateReaderTextSelection(blockUid: "block-1", selectedText: "quoted excerpt")
        session.selectReaderBlock("block-2")
        try await Task.sleep(nanoseconds: 130_000_000)

        XCTAssertEqual(session.selectedBlockUid, "block-2")
        XCTAssertNil(session.readerTextSelection)
    }

    func testSelectingZoteroItemDiscardsPendingReaderTextSelection() async throws {
        let session = ReaderWorkbenchSession()

        session.updateReaderTextSelection(blockUid: "block-1", selectedText: "quoted excerpt")
        session.selectZoteroItem(id: 42)
        try await Task.sleep(nanoseconds: 130_000_000)

        XCTAssertEqual(session.selectedLibraryItem, .zoteroItem(id: 42))
        XCTAssertNil(session.selectedBlockUid)
        XCTAssertNil(session.readerTextSelection)
    }

    func testSelectingSameLoadedZoteroItemIsIdempotent() {
        let session = ReaderWorkbenchSession()

        session.selectZoteroItem(id: 42)
        let generation = session.selectionLoadGeneration
        session.selectZoteroItem(id: 42)

        XCTAssertEqual(session.selectionLoadGeneration, generation)
        XCTAssertEqual(session.selectedLibraryItem, .zoteroItem(id: 42))
        XCTAssertEqual(session.selectedLibraryItemLoadState, .loaded(.zoteroItem(id: 42)))
    }

    func testSelectingSameZoteroItemRepairsStaleReaderState() {
        let session = ReaderWorkbenchSession()
        session.selectedLibraryItem = .zoteroItem(id: 42)
        session.selectedLibraryItemLoadState = .loaded(.zoteroItem(id: 42))
        session.activeRevisionId = "old-revision"
        session.blocks = [
            makeReaderBlock(uid: "old-block", structuralPath: "00001", type: .paragraph)
        ]
        session.selectedBlockUid = "old-block"
        session.readerTextSelection = ReaderTextSelection(
            blockUid: "old-block",
            text: "old quote",
            textHash: "old-hash"
        )

        session.selectZoteroItem(id: 42)

        XCTAssertEqual(session.selectionLoadGeneration, 1)
        XCTAssertEqual(session.selectedLibraryItem, .zoteroItem(id: 42))
        XCTAssertEqual(session.selectedLibraryItemLoadState, .loaded(.zoteroItem(id: 42)))
        XCTAssertNil(session.activeRevisionId)
        XCTAssertTrue(session.blocks.isEmpty)
        XCTAssertNil(session.selectedBlockUid)
        XCTAssertNil(session.readerTextSelection)
    }

    func testLibraryItemRequestKeepsLastSelection() async throws {
        let session = ReaderWorkbenchSession()

        session.requestLibraryItemSelection(.zoteroItem(id: 1))
        session.requestLibraryItemSelection(.zoteroItem(id: 2))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(session.selectedLibraryItem, .zoteroItem(id: 2))
    }

    func testArticleSelectionImmediatelyClearsOldReaderContentAndShowsLoadingState() {
        let session = ReaderWorkbenchSession()
        session.articles = [
            makeArticle(id: "article-1", revisionId: "revision-1")
        ]
        session.activeRevisionId = "old-revision"
        session.blocks = [
            makeReaderBlock(uid: "old-block", structuralPath: "00001", type: .paragraph)
        ]
        session.selectedBlockUid = "old-block"
        session.readerTextSelection = ReaderTextSelection(
            blockUid: "old-block",
            text: "old quote",
            textHash: "old-hash"
        )

        session.requestLibraryItemSelection(.article(id: "article-1"))

        XCTAssertEqual(session.selectedLibraryItem, .article(id: "article-1"))
        XCTAssertEqual(session.selectedLibraryItemLoadState, .loading(.article(id: "article-1")))
        XCTAssertNil(session.activeRevisionId)
        XCTAssertTrue(session.blocks.isEmpty)
        XCTAssertNil(session.selectedBlockUid)
        XCTAssertNil(session.readerTextSelection)
    }

    func testFailedArticleSelectionCanBeClickedAgainToRetry() {
        let session = ReaderWorkbenchSession()
        session.articles = [
            makeArticle(id: "article-1", revisionId: "revision-1")
        ]
        session.selectedLibraryItem = .article(id: "article-1")
        session.selectedLibraryItemLoadState = .failed(.article(id: "article-1"), message: "Old failure")
        session.blocks = [
            makeReaderBlock(uid: "old-block", structuralPath: "00001", type: .paragraph)
        ]

        session.requestLibraryItemSelection(.article(id: "article-1"))

        XCTAssertEqual(session.selectedLibraryItemLoadState, .loading(.article(id: "article-1")))
        XCTAssertTrue(session.blocks.isEmpty)
    }

    func testLoadedArticleWithEmptyReaderContentCanBeSelectedAgainToReload() {
        let session = ReaderWorkbenchSession()
        session.articles = [
            makeArticle(id: "article-1", revisionId: "revision-1")
        ]
        session.selectedLibraryItem = .article(id: "article-1")
        session.selectedLibraryItemLoadState = .loaded(.article(id: "article-1"))
        session.activeRevisionId = "revision-1"
        session.blocks = []

        session.requestLibraryItemSelection(.article(id: "article-1"))

        XCTAssertEqual(session.selectedLibraryItemLoadState, .loading(.article(id: "article-1")))
        XCTAssertNil(session.activeRevisionId)
        XCTAssertTrue(session.blocks.isEmpty)
    }

    func testLoadedArticleWithReaderContentDoesNotReloadWhenSelectedAgain() {
        let session = ReaderWorkbenchSession()
        let block = makeReaderBlock(uid: "block-1", structuralPath: "00001", type: .paragraph)
        session.articles = [
            makeArticle(id: "article-1", revisionId: "revision-1")
        ]
        session.selectedLibraryItem = .article(id: "article-1")
        session.selectedLibraryItemLoadState = .loaded(.article(id: "article-1"))
        session.activeRevisionId = "revision-1"
        session.blocks = [block]

        session.requestLibraryItemSelection(.article(id: "article-1"))

        XCTAssertEqual(session.selectedLibraryItemLoadState, .loaded(.article(id: "article-1")))
        XCTAssertEqual(session.activeRevisionId, "revision-1")
        XCTAssertEqual(session.blocks.map(\.blockUid), ["block-1"])
    }

    func testLoadedArticleCanBeExplicitlyReloadedWithoutChangingSelectionSemantics() {
        let session = ReaderWorkbenchSession()
        let block = makeReaderBlock(uid: "block-1", structuralPath: "00001", type: .paragraph)
        session.articles = [
            makeArticle(id: "article-1", revisionId: "revision-1")
        ]
        session.selectedLibraryItem = .article(id: "article-1")
        session.selectedLibraryItemLoadState = .loaded(.article(id: "article-1"))
        session.activeRevisionId = "revision-1"
        session.blocks = [block]
        session.selectedBlockUid = "block-1"

        session.reloadSelectedLibraryItem()

        XCTAssertEqual(session.selectedLibraryItem, .article(id: "article-1"))
        XCTAssertEqual(session.selectedLibraryItemLoadState, .loading(.article(id: "article-1")))
        XCTAssertNil(session.activeRevisionId)
        XCTAssertTrue(session.blocks.isEmpty)
        XCTAssertNil(session.selectedBlockUid)
    }

    func testMissingArticleSelectionMovesToFailureState() async throws {
        let session = ReaderWorkbenchSession()

        session.requestLibraryItemSelection(.article(id: "missing-article"))
        try await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(session.selectedLibraryItem, .article(id: "missing-article"))
        XCTAssertEqual(
            session.selectedLibraryItemLoadState,
            .failed(
                .article(id: "missing-article"),
                message: "The selected paper is no longer available in this library."
            )
        )
        XCTAssertEqual(session.selectedLibraryItemLoadError, "The selected paper is no longer available in this library.")
    }

    func testSelectCitationEntryTargetsBibliographyBlockAndClearsPendingTextSelection() async throws {
        let session = ReaderWorkbenchSession()
        session.blocks = [
            makeReaderBlock(uid: "p-1", structuralPath: "00001", type: .paragraph),
            makeReaderBlock(uid: "bib-1", structuralPath: "99999", type: .bibliography)
        ]
        session.updateReaderTextSelection(blockUid: "p-1", selectedText: "quoted text")

        let targetBlockUid = session.selectCitationEntry(
            ReaderCitationEntry(
                id: "bib.bib7",
                label: "7",
                rawText: "Ada L. Reference title.",
                sourceBlockUid: "bib-1",
                sourceStructuralPath: "99999"
            )
        )
        try await Task.sleep(nanoseconds: 130_000_000)

        XCTAssertEqual(targetBlockUid, "bib-1")
        XCTAssertEqual(session.selectedBlockUid, "bib-1")
        XCTAssertEqual(session.selectedCitationEntryId, "bib.bib7")
        XCTAssertNil(session.readerTextSelection)
        XCTAssertEqual(session.readerBlockScrollRequest?.blockUid, "bib-1")
    }

    func testManualBlockSelectionClearsSelectedCitationEntry() {
        let session = ReaderWorkbenchSession()
        session.blocks = [
            makeReaderBlock(uid: "p-1", structuralPath: "00001", type: .paragraph),
            makeReaderBlock(uid: "bib-1", structuralPath: "99999", type: .bibliography)
        ]
        session.selectCitationEntry(
            ReaderCitationEntry(
                id: "bib.bib7",
                label: "7",
                rawText: "Ada L. Reference title.",
                sourceBlockUid: "bib-1",
                sourceStructuralPath: "99999"
            )
        )

        session.selectReaderBlock("p-1")

        XCTAssertEqual(session.selectedBlockUid, "p-1")
        XCTAssertNil(session.selectedCitationEntryId)
    }

    func testReaderTextSelectionClearsSelectedCitationEntry() {
        let session = ReaderWorkbenchSession()
        session.blocks = [
            makeReaderBlock(uid: "p-1", structuralPath: "00001", type: .paragraph),
            makeReaderBlock(uid: "bib-1", structuralPath: "99999", type: .bibliography)
        ]
        session.selectCitationEntry(
            ReaderCitationEntry(
                id: "bib.bib7",
                label: "7",
                rawText: "Ada L. Reference title.",
                sourceBlockUid: "bib-1",
                sourceStructuralPath: "99999"
            )
        )

        session.updateReaderTextSelection(blockUid: "p-1", selectedText: "quoted text")

        XCTAssertEqual(session.selectedBlockUid, "p-1")
        XCTAssertNil(session.selectedCitationEntryId)
    }

    func testReaderTextSelectionDoesNotRequestReaderScroll() {
        let session = ReaderWorkbenchSession()
        session.blocks = [
            makeReaderBlock(uid: "p-1", structuralPath: "00001", type: .paragraph)
        ]

        session.updateReaderTextSelection(blockUid: "p-1", selectedText: "quoted text")

        XCTAssertEqual(session.selectedBlockUid, "p-1")
        XCTAssertNil(session.readerBlockScrollRequest)
    }

    func testSelectingZoteroItemClearsSelectedCitationEntry() {
        let session = ReaderWorkbenchSession()
        session.blocks = [
            makeReaderBlock(uid: "bib-1", structuralPath: "99999", type: .bibliography)
        ]
        session.selectCitationEntry(
            ReaderCitationEntry(
                id: "bib.bib7",
                label: "7",
                rawText: "Ada L. Reference title.",
                sourceBlockUid: "bib-1",
                sourceStructuralPath: "99999"
            )
        )

        session.selectZoteroItem(id: 1)

        XCTAssertNil(session.selectedBlockUid)
        XCTAssertNil(session.selectedCitationEntryId)
    }

    func testSelectCitationEntryRejectsFallbackEntryWithoutNavigatingToSourceParagraph() {
        let session = ReaderWorkbenchSession()
        session.blocks = [
            makeReaderBlock(uid: "p-1", structuralPath: "00001", type: .paragraph)
        ]
        session.selectedBlockUid = nil

        let targetBlockUid = session.selectCitationEntry(
            ReaderCitationEntry(
                id: "bib.bib7",
                label: "7",
                rawText: "",
                sourceBlockUid: "p-1",
                sourceStructuralPath: "00001"
            )
        )

        XCTAssertNil(targetBlockUid)
        XCTAssertNil(session.selectedBlockUid)
        XCTAssertNil(session.selectedCitationEntryId)
        XCTAssertEqual(session.researchWorkbenchStatus, "Citation target missing")
    }

    func testSelectCitationEntryReportsMissingTargetWithoutChangingSelection() {
        let session = ReaderWorkbenchSession()
        session.blocks = [
            makeReaderBlock(uid: "p-1", structuralPath: "00001", type: .paragraph)
        ]
        session.selectedBlockUid = "p-1"

        let targetBlockUid = session.selectCitationEntry(
            ReaderCitationEntry(
                id: "bib.bib7",
                label: "7",
                rawText: "Ada L. Reference title.",
                sourceBlockUid: "missing-bib",
                sourceStructuralPath: "99999"
            )
        )

        XCTAssertNil(targetBlockUid)
        XCTAssertEqual(session.selectedBlockUid, "p-1")
        XCTAssertEqual(session.researchWorkbenchStatus, "Citation target missing")
        XCTAssertEqual(
            session.researchWorkbenchError,
            "The bibliography target [7] is not available in this loaded document."
        )
    }

    func testValidCitationSelectionClearsPreviousMissingCitationError() {
        let session = ReaderWorkbenchSession()
        session.blocks = [
            makeReaderBlock(uid: "p-1", structuralPath: "00001", type: .paragraph),
            makeReaderBlock(uid: "bib-1", structuralPath: "99999", type: .bibliography)
        ]
        _ = session.selectCitationEntry(
            ReaderCitationEntry(
                id: "bib.missing",
                label: "9",
                rawText: "Missing reference.",
                sourceBlockUid: "missing-bib",
                sourceStructuralPath: "99998"
            )
        )

        let targetBlockUid = session.selectCitationEntry(
            ReaderCitationEntry(
                id: "bib.bib7",
                label: "7",
                rawText: "Ada L. Reference title.",
                sourceBlockUid: "bib-1",
                sourceStructuralPath: "99999"
            )
        )

        XCTAssertEqual(targetBlockUid, "bib-1")
        XCTAssertEqual(session.selectedBlockUid, "bib-1")
        XCTAssertEqual(session.selectedCitationEntryId, "bib.bib7")
        XCTAssertEqual(session.researchWorkbenchStatus, "Citation selected")
        XCTAssertNil(session.researchWorkbenchError)
    }

    func testReaderCitationLinkParsesOnlyCitationScheme() {
        XCTAssertEqual(
            ReaderCitationLink.reference(from: "bilin://citation/bib.bib7"),
            "bib.bib7"
        )
        XCTAssertEqual(
            ReaderCitationLink.reference(from: URL(string: "bilin://citation/bib.bib8")!),
            "bib.bib8"
        )
        XCTAssertNil(ReaderCitationLink.reference(from: "https://example.com/bib.bib7"))
        XCTAssertNil(ReaderCitationLink.reference(from: "bilin://citation/"))
    }

    func testReaderCitationLinkBuildsURLFromResolvedEntry() {
        let entry = ReaderCitationEntry(
            id: "bib.inline-only",
            label: "9",
            rawText: "",
            sourceBlockUid: "p-1",
            sourceStructuralPath: "00001"
        )

        XCTAssertEqual(
            ReaderCitationLink.reference(from: ReaderCitationLink.urlString(for: entry)),
            "bib.inline-only"
        )
    }

    func testBackgroundResearchRefreshDoesNotBlockActions() async throws {
        ResearchAPIMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/health")
            let response = HTTPURLResponse(
                url: URL(string: "http://127.0.0.1:8000/health")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data("""
                {
                  "status": "ok",
                  "app": "Ilios",
                  "version": "0.3.6"
                }
                """.utf8)
            )
        }
        defer {
            ResearchAPIMockURLProtocol.requestHandler = nil
        }
        let session = ReaderWorkbenchSession(researchAPIClient: makeResearchAPIClient())

        session.requestResearchWorkbenchRefresh()
        XCTAssertFalse(session.researchAPIBusy)
        try await Task.sleep(nanoseconds: 160_000_000)

        XCTAssertFalse(session.researchAPIBusy)
        XCTAssertEqual(session.researchAPIStatus, "API connected")
        XCTAssertEqual(session.researchAPIHealth?.app, "Ilios")
        XCTAssertEqual(session.researchWorkbenchStatus, "No library")
    }

    private func makeResearchAPIClient() -> BilinResearchAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResearchAPIMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return BilinResearchAPIClient(
            baseURL: URL(string: "http://127.0.0.1:8000")!,
            session: session
        )
    }

    private func makeReaderBlock(
        uid: String,
        structuralPath: String,
        type: DocumentBlockKind
    ) -> DocumentBlock {
        DocumentBlock(
            id: "block-\(uid)",
            articleRevisionId: "revision-1",
            blockUid: uid,
            structuralPath: structuralPath,
            blockType: type,
            contentHash: "hash-\(uid)",
            sourceMarkdown: "Reader block \(uid)",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeArticle(id: String, revisionId: String) -> Article {
        Article(
            id: id,
            libraryId: "local-library",
            source: "arxiv",
            externalId: "2401.00001",
            title: "Session Paper",
            activeRevisionId: revisionId
        )
    }
}

final class RatexSVGImageCacheTests: XCTestCase {
    func testCachedImageIsMemoryOnlyUntilAsyncDecodePreheats() async {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10"/></svg>"#
        RatexSVGImageCache.removeAllImagesForTesting()

        XCTAssertNil(RatexSVGImageCache.cachedImage(from: svg))
        let image = await RatexSVGImageCache.image(from: svg)

        XCTAssertNotNil(image)
        XCTAssertNotNil(RatexSVGImageCache.cachedImage(from: svg))
    }

    func testNativeImageStateIsScopedToCurrentSVG() {
        let firstSVG = #"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"></svg>"#
        let secondSVG = #"<svg xmlns="http://www.w3.org/2000/svg" width="30" height="12"></svg>"#
        let image = NSImage(size: NSSize(width: 20, height: 10))
        var state = SVGNativeImageState()

        state.store(image: image, for: firstSVG)
        XCTAssertNotNil(state.image(for: firstSVG))
        XCTAssertNil(state.image(for: secondSVG))

        state.prepareForLoad(svg: secondSVG)
        XCTAssertNil(state.image(for: firstSVG))
        XCTAssertNil(state.image(for: secondSVG))
        XCTAssertFalse(state.loadFailed(for: firstSVG))
        XCTAssertFalse(state.loadFailed(for: secondSVG))

        state.store(image: nil, for: secondSVG)
        XCTAssertFalse(state.loadFailed(for: firstSVG))
        XCTAssertTrue(state.loadFailed(for: secondSVG))
    }
}

final class EquationBlockRenderStateTests: XCTestCase {
    func testResultIsScopedToCurrentRenderKey() {
        var state = EquationBlockRenderState()
        let firstKey = RatexRenderCacheKey(
            latex: "x",
            layoutMode: .block,
            options: RatexRenderOptions(fontSize: 18, foregroundColor: "#111111", timeoutSeconds: 5),
            rendererIdentifier: "test-renderer"
        )
        let secondKey = RatexRenderCacheKey(
            latex: "x",
            layoutMode: .block,
            options: RatexRenderOptions(fontSize: 18, foregroundColor: "#f2f2f2", timeoutSeconds: 5),
            rendererIdentifier: "test-renderer"
        )
        let first = MathRenderResult(
            latex: "x",
            mode: .display,
            accessibilityLabel: "x",
            payload: .svg(#"<svg xmlns="http://www.w3.org/2000/svg"></svg>"#)
        )

        state.store(first, for: firstKey)
        XCTAssertEqual(state.result(for: firstKey)?.latex, "x")
        XCTAssertNil(state.result(for: secondKey))

        state.prepareForLoad(key: secondKey)
        XCTAssertNil(state.result(for: firstKey))
        XCTAssertNil(state.result(for: secondKey))
    }
}

private final class ResearchAPIMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class InlineMathAttachmentFactoryTests: XCTestCase {
    func testCachedAttachmentDecodesSourceImageOnCacheMissAndReusesRasterVariant() async {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="12"><rect width="24" height="12"/></svg>"#
        let font = NSFont.systemFont(ofSize: 16)
        RatexSVGImageCache.removeAllImagesForTesting()
        InlineMathAttachmentFactory.removeAllImagesForTesting()

        XCTAssertNil(RatexSVGImageCache.cachedImage(from: svg))

        let coldAttachment = InlineMathAttachmentFactory.cachedAttachment(
            svg: svg,
            latex: "x",
            baseFont: font
        )
        XCTAssertNotNil(coldAttachment)
        XCTAssertNotNil(RatexSVGImageCache.cachedImage(from: svg))

        let warmed = await InlineMathAttachmentFactory.preheat(svg: svg, baseFont: font)
        let warmAttachment = InlineMathAttachmentFactory.cachedAttachment(
            svg: svg,
            latex: "x",
            baseFont: font
        )

        XCTAssertFalse(warmed)
        XCTAssertNotNil(warmAttachment)
        XCTAssertEqual(warmAttachment?.bounds.height ?? 0, 14, accuracy: 0.5)
    }

    func testPreheatWarmsSourceSVGDecodeCacheBeforeBuildingAttachment() async {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="28" height="14"><rect width="28" height="14"/></svg>"#
        let font = NSFont.systemFont(ofSize: 16)
        RatexSVGImageCache.removeAllImagesForTesting()
        InlineMathAttachmentFactory.removeAllImagesForTesting()

        XCTAssertNil(RatexSVGImageCache.cachedImage(from: svg))

        let warmed = await InlineMathAttachmentFactory.preheat(svg: svg, baseFont: font)

        XCTAssertTrue(warmed)
        XCTAssertNotNil(RatexSVGImageCache.cachedImage(from: svg))
        XCTAssertNotNil(
            InlineMathAttachmentFactory.cachedAttachment(
                svg: svg,
                latex: "x",
                baseFont: font
            )
        )
    }

    func testCachedAttachmentBuildsRasterVariantFromDecodedSourceImage() async {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="30" height="10"><rect width="30" height="10"/></svg>"#
        let font = NSFont.systemFont(ofSize: 16)
        RatexSVGImageCache.removeAllImagesForTesting()
        InlineMathAttachmentFactory.removeAllImagesForTesting()

        let sourceImage = await RatexSVGImageCache.image(from: svg)
        XCTAssertNotNil(sourceImage)
        let attachment = InlineMathAttachmentFactory.cachedAttachment(
            svg: svg,
            latex: "x_i",
            baseFont: font
        )

        XCTAssertNotNil(attachment)
        XCTAssertGreaterThan(attachment?.bounds.width ?? 0, attachment?.bounds.height ?? 0)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}

private final class RenderConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var runningCount = 0
    private var observedMaximumRunningCount = 0

    var maximumRunningCount: Int {
        lock.withLock { observedMaximumRunningCount }
    }

    func render(latex: String) -> MathRenderResult {
        lock.withLock {
            runningCount += 1
            observedMaximumRunningCount = max(observedMaximumRunningCount, runningCount)
        }
        Thread.sleep(forTimeInterval: 0.05)
        lock.withLock {
            runningCount -= 1
        }
        return MathRenderResult(
            latex: latex,
            mode: .display,
            accessibilityLabel: latex,
            payload: .svg(#"<svg xmlns="http://www.w3.org/2000/svg"></svg>"#)
        )
    }
}
