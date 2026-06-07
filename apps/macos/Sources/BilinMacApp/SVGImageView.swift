import SwiftUI
import AppKit
import CryptoKit
import WebKit

struct SVGImageView: View {
    var svg: String
    var accessibilityLabel: String
    var preferNativeImage = true
    @State private var nativeImageState = SVGNativeImageState()

    var body: some View {
        Group {
            if preferNativeImage,
               let image = nativeImageState.image(for: svg) ?? RatexSVGImageCache.cachedImage(from: svg) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(accessibilityLabel)
            } else if preferNativeImage, !nativeImageState.loadFailed(for: svg) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(accessibilityLabel)
            } else {
                SVGWebView(svg: svg, accessibilityLabel: accessibilityLabel)
            }
        }
        .allowsHitTesting(false)
        .task(id: svg) {
            await loadNativeImageIfNeeded()
        }
    }

    @MainActor
    private func loadNativeImageIfNeeded() async {
        let requestedSVG = svg
        guard preferNativeImage else {
            nativeImageState.reset()
            return
        }
        nativeImageState.prepareForLoad(svg: requestedSVG)
        if let cachedImage = RatexSVGImageCache.cachedImage(from: requestedSVG) {
            nativeImageState.store(image: cachedImage, for: requestedSVG)
            return
        }
        let image = await RatexSVGImageCache.image(from: requestedSVG)
        guard !Task.isCancelled else { return }
        nativeImageState.store(image: image, for: requestedSVG)
    }
}

struct SVGNativeImageState {
    private var svg: String?
    private var nativeImage: NSImage?
    private var nativeImageLoadFailed = false

    func image(for requestedSVG: String) -> NSImage? {
        svg == requestedSVG ? nativeImage : nil
    }

    func loadFailed(for requestedSVG: String) -> Bool {
        svg == requestedSVG && nativeImageLoadFailed
    }

    mutating func prepareForLoad(svg requestedSVG: String) {
        guard svg != requestedSVG else { return }
        svg = requestedSVG
        nativeImage = nil
        nativeImageLoadFailed = false
    }

    mutating func store(image: NSImage?, for requestedSVG: String) {
        svg = requestedSVG
        nativeImage = image
        nativeImageLoadFailed = image == nil
    }

    mutating func reset() {
        svg = nil
        nativeImage = nil
        nativeImageLoadFailed = false
    }
}

enum RatexSVGImageCache {
    private final class DecodeThreadCheck: @unchecked Sendable {
        private let lock = NSLock()
        private var check: (() -> Void)?

        func set(_ check: (() -> Void)?) {
            lock.withLock {
                self.check = check
            }
        }

        func call() {
            lock.withLock { check }?()
        }
    }

    private static let sourceImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()
    private static let lock = NSLock()
    private static let decodeThreadCheck = DecodeThreadCheck()
    private static var inFlightDecodes: [NSString: Task<NSImage?, Never>] = [:]

    static func cachedImage(from svg: String) -> NSImage? {
        let key = key(for: svg, variant: "source")
        if let image = sourceImageCache.object(forKey: key) {
            return image
        }
        return nil
    }

    static func cachedOrDecodedImage(from svg: String) -> NSImage? {
        if let cachedImage = cachedImage(from: svg) {
            return cachedImage
        }
        return decodeImage(from: svg, key: key(for: svg, variant: "source"))
    }

    static func image(from svg: String) async -> NSImage? {
        if let cachedImage = cachedImage(from: svg) {
            return cachedImage
        }
        let key = key(for: svg, variant: "source")
        let task = lock.withLock {
            if let inFlightDecode = inFlightDecodes[key] {
                return inFlightDecode
            }
            let task = Task.detached(priority: .utility) {
                decodeImage(from: svg, key: key)
            }
            inFlightDecodes[key] = task
            return task
        }

        let image = await task.value
        lock.withLock {
            inFlightDecodes[key] = nil
        }
        return image
    }

    static func preheat(svg: String) async {
        _ = await image(from: svg)
    }

    static func removeAllImagesForTesting() {
        sourceImageCache.removeAllObjects()
        lock.withLock {
            inFlightDecodes.removeAll()
        }
    }

    static func setDecodeThreadCheckForTesting(_ check: (() -> Void)?) {
        decodeThreadCheck.set(check)
    }

    private static func decodeImage(from svg: String, key: NSString) -> NSImage? {
        decodeThreadCheck.call()
        if let cachedImage = sourceImageCache.object(forKey: key) {
            return cachedImage
        }
        guard let data = svg.data(using: .utf8) else { return nil }
        guard let image = NSImage(data: data) else { return nil }
        sourceImageCache.setObject(image, forKey: key)
        return image
    }

    static func key(for svg: String, variant: String) -> NSString {
        let digest = SHA256.hash(data: Data(svg.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(variant)-\(digest)" as NSString
    }
}

private struct SVGWebView: NSViewRepresentable {
    var svg: String
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.setAccessibilityLabel(accessibilityLabel)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.setAccessibilityLabel(accessibilityLabel)
        guard context.coordinator.lastSVG != svg else { return }
        context.coordinator.lastSVG = svg
        webView.loadHTMLString(Self.html(for: svg), baseURL: nil)
    }

    final class Coordinator {
        var lastSVG: String?
    }

    private static func html(for svg: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              overflow: hidden;
              background: transparent;
            }
            body {
              display: flex;
              align-items: center;
              justify-content: center;
            }
            svg {
              max-width: 100%;
              max-height: 100%;
              width: auto;
              height: auto;
            }
          </style>
        </head>
        <body>
        \(svg)
        </body>
        </html>
        """
    }
}
