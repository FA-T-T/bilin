import CryptoKit
import Foundation
import BilinRenderKit

struct RatexRenderCacheKey: Codable, Hashable, Sendable {
    var cacheVersion = 2
    var rendererIdentifier: String
    var latex: String
    var layoutMode: EquationLayoutMode
    var options: RatexRenderOptions

    init(
        latex: String,
        layoutMode: EquationLayoutMode,
        options: RatexRenderOptions,
        rendererIdentifier: String = RatexRenderCacheKey.currentRendererIdentifier
    ) {
        self.rendererIdentifier = rendererIdentifier
        self.latex = latex
        self.layoutMode = layoutMode
        self.options = options
    }

    private static var currentRendererIdentifier: String {
        RatexRendererDiscovery.executablePath ?? "ratex-render-svg-unavailable"
    }
}

private enum RatexRendererDiscovery {
    static let executablePath = RatexSVGCLIAdapter.discoveredExecutableURL()?.path
}

@MainActor
final class RatexRenderCacheStore {
    static let shared = RatexRenderCacheStore()

    private let diskCache: RatexRenderDiskCache
    private struct MemoryEntry {
        var result: MathRenderResult
        var expiresAt: Date?
    }

    private var memoryResults: [RatexRenderCacheKey: MemoryEntry] = [:]
    private var memoryOrder: [RatexRenderCacheKey] = []
    private var inFlightResults: [RatexRenderCacheKey: Task<MathRenderResult, Never>] = [:]
    private var inFlightPersistedResults: [RatexRenderCacheKey: PersistedLookup] = [:]
    private let renderGate: RatexRenderConcurrencyGate
    private let maxMemoryResults: Int
    private let failureCacheDuration: TimeInterval
    private let now: () -> Date

    private final class PersistedLookup {
        let id = UUID()
        let task: Task<MathRenderResult?, Never>

        init(task: Task<MathRenderResult?, Never>) {
            self.task = task
        }
    }

    init(
        maxMemoryResults: Int = 512,
        maxConcurrentRenders: Int = 2,
        failureCacheDuration: TimeInterval = 30,
        diskCacheDirectoryURL: URL? = nil,
        diskCacheReadObserverForTesting: (@Sendable (RatexRenderCacheKey) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.maxMemoryResults = max(1, maxMemoryResults)
        self.diskCache = RatexRenderDiskCache(
            directoryURL: diskCacheDirectoryURL,
            readObserver: diskCacheReadObserverForTesting
        )
        self.renderGate = RatexRenderConcurrencyGate(limit: maxConcurrentRenders)
        self.failureCacheDuration = failureCacheDuration
        self.now = now
    }

    func cachedResult(for key: RatexRenderCacheKey) -> MathRenderResult? {
        if let memoryResult = cachedMemoryResult(for: key) {
            return memoryResult
        }
        guard let diskResult = diskCache.cachedResult(for: key) else {
            return nil
        }
        store(diskResult, for: key)
        return diskResult
    }

    func cachedResidentResult(for key: RatexRenderCacheKey) -> MathRenderResult? {
        cachedMemoryResult(for: key)
    }

    func cachedPersistedResult(
        for key: RatexRenderCacheKey,
        priority: TaskPriority = .utility
    ) async -> MathRenderResult? {
        if let cachedResult = cachedResidentResult(for: key) {
            return cachedResult
        }
        let lookup = persistedLookup(for: key, priority: priority)
        let diskResult = await lookup.task.value
        completePersistedLookup(lookup, for: key)
        if let diskResult {
            store(diskResult, for: key)
            return diskResult
        }
        return cachedResidentResult(for: key)
    }

    func cachedPersistedResults(
        for keys: [RatexRenderCacheKey],
        priority: TaskPriority = .utility
    ) async -> [RatexRenderCacheKey: MathRenderResult] {
        var results: [RatexRenderCacheKey: MathRenderResult] = [:]
        var missingKeys: [RatexRenderCacheKey] = []
        var seenKeys: Set<RatexRenderCacheKey> = []

        for key in keys where seenKeys.insert(key).inserted {
            if let cachedResult = cachedResidentResult(for: key) {
                results[key] = cachedResult
            } else {
                missingKeys.append(key)
            }
        }

        guard !missingKeys.isEmpty else {
            return results
        }

        let lookups = missingKeys.map { key in
            (key, persistedLookup(for: key, priority: priority))
        }
        for (key, lookup) in lookups {
            let lookupResult = await lookup.task.value
            completePersistedLookup(lookup, for: key)
            guard let result = lookupResult ?? cachedResidentResult(for: key) else {
                continue
            }
            store(result, for: key)
            results[key] = result
        }

        return results
    }

    private func persistedLookup(
        for key: RatexRenderCacheKey,
        priority: TaskPriority
    ) -> PersistedLookup {
        if let lookup = inFlightPersistedResults[key] {
            return lookup
        }
        let diskCache = diskCache
        let lookup = PersistedLookup(
            task: Task.detached(priority: priority) {
                diskCache.cachedResult(for: key)
            }
        )
        inFlightPersistedResults[key] = lookup
        return lookup
    }

    private func completePersistedLookup(
        _ lookup: PersistedLookup,
        for key: RatexRenderCacheKey
    ) {
        guard inFlightPersistedResults[key]?.id == lookup.id else {
            return
        }
        inFlightPersistedResults[key] = nil
    }

    func cachedMemoryResultForTesting(for key: RatexRenderCacheKey) -> MathRenderResult? {
        cachedMemoryResult(for: key)
    }

    func result(
        for key: RatexRenderCacheKey,
        priority: TaskPriority = .utility,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        cancelledResult: (@Sendable () -> MathRenderResult)? = nil,
        render: @escaping @Sendable () -> MathRenderResult
    ) async -> MathRenderResult {
        if let cachedResult = cachedResidentResult(for: key) {
            return cachedResult
        }
        if let inFlightResult = inFlightResults[key] {
            return await inFlightResult.value
        }

        let diskCache = diskCache
        let renderGate = renderGate
        let task = Task.detached(priority: priority) {
            if let diskResult = diskCache.cachedResult(for: key) {
                return diskResult
            }
            if isCancelled(), let cancelledResult {
                return cancelledResult()
            }
            await renderGate.wait()
            if isCancelled(), let cancelledResult {
                await renderGate.signal()
                return cancelledResult()
            }
            let result = render()
            await renderGate.signal()
            return result
        }
        inFlightResults[key] = task
        let result = await task.value
        inFlightResults[key] = nil
        if case .svg = result.payload {
            Task.detached(priority: .utility) {
                diskCache.store(result, for: key)
            }
        }
        store(result, for: key)
        return result
    }

    func store(_ result: MathRenderResult, for key: RatexRenderCacheKey) {
        switch result.payload {
        case .svg:
            storeInMemory(result, for: key)
        case .unavailable:
            guard failureCacheDuration > 0 else {
                return
            }
            storeInMemory(
                result,
                for: key,
                expiresAt: now().addingTimeInterval(failureCacheDuration)
            )
        case .plainText:
            return
        }
    }

    private func cachedMemoryResult(for key: RatexRenderCacheKey) -> MathRenderResult? {
        guard let memoryEntry = memoryResults[key] else {
            return nil
        }
        if let expiresAt = memoryEntry.expiresAt, expiresAt <= now() {
            removeMemoryResult(for: key)
            return nil
        }
        touchMemoryResult(for: key)
        return memoryEntry.result
    }

    private func storeInMemory(
        _ result: MathRenderResult,
        for key: RatexRenderCacheKey,
        expiresAt: Date? = nil
    ) {
        memoryResults[key] = MemoryEntry(result: result, expiresAt: expiresAt)
        touchMemoryResult(for: key)

        while memoryOrder.count > maxMemoryResults {
            let oldestKey = memoryOrder.removeFirst()
            memoryResults.removeValue(forKey: oldestKey)
        }
    }

    private func touchMemoryResult(for key: RatexRenderCacheKey) {
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
    }

    private func removeMemoryResult(for key: RatexRenderCacheKey) {
        memoryResults.removeValue(forKey: key)
        memoryOrder.removeAll { $0 == key }
    }
}

final class RatexRenderCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
        }
    }
}

private actor RatexRenderConcurrencyGate {
    private let limit: Int
    private var runningCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func wait() async {
        if runningCount < limit {
            runningCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            runningCount = max(0, runningCount - 1)
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}

private final class RatexRenderDiskCache: @unchecked Sendable {
    private struct CachedSVG: Codable {
        var latex: String
        var mode: String
        var accessibilityLabel: String
        var svg: String
    }

    private let directoryURL: URL?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager
    private let readObserver: (@Sendable (RatexRenderCacheKey) -> Void)?
    private let lock = NSLock()

    init(
        directoryURL explicitDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        readObserver: (@Sendable (RatexRenderCacheKey) -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.readObserver = readObserver
        if let explicitDirectoryURL {
            try? fileManager.createDirectory(at: explicitDirectoryURL, withIntermediateDirectories: true)
            directoryURL = explicitDirectoryURL
            return
        }
        guard let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            directoryURL = nil
            return
        }
        let directoryURL = cacheRoot
            .appendingPathComponent("Bilin", isDirectory: true)
            .appendingPathComponent("RatexRenderCache", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.directoryURL = directoryURL
    }

    func cachedResult(for key: RatexRenderCacheKey) -> MathRenderResult? {
        readObserver?(key)
        return lock.withLock { () -> MathRenderResult? in
            guard let fileURL = cacheFileURL(for: key),
                  let data = try? Data(contentsOf: fileURL),
                  let cachedSVG = try? decoder.decode(CachedSVG.self, from: data),
                  let mode = MathRenderMode(rawValue: cachedSVG.mode)
            else {
                return nil
            }

            return MathRenderResult(
                latex: cachedSVG.latex,
                mode: mode,
                accessibilityLabel: cachedSVG.accessibilityLabel,
                payload: .svg(cachedSVG.svg)
            )
        }
    }

    func store(_ result: MathRenderResult, for key: RatexRenderCacheKey) {
        lock.withLock {
            guard case .svg(let svg) = result.payload,
                  let fileURL = cacheFileURL(for: key)
            else {
                return
            }

            let cachedSVG = CachedSVG(
                latex: result.latex,
                mode: result.mode.rawValue,
                accessibilityLabel: result.accessibilityLabel,
                svg: svg
            )

            guard let data = try? encoder.encode(cachedSVG) else {
                return
            }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func cacheFileURL(for key: RatexRenderCacheKey) -> URL? {
        directoryURL?.appendingPathComponent(cacheFileName(for: key), isDirectory: false)
    }

    private func cacheFileName(for key: RatexRenderCacheKey) -> String {
        let data = (try? encoder.encode(key)) ?? Data(String(describing: key).utf8)
        let digest = SHA256.hash(data: data)
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hexDigest).json"
    }
}
