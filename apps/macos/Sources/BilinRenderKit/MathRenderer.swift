import Foundation

public enum MathRenderMode: String, Equatable, Sendable {
    case display
    case inline
}

public enum MathRenderPayload: Equatable, Sendable {
    case plainText(String)
    case svg(String)
    case unavailable(reason: String)
}

public struct MathRenderResult: Equatable, Sendable {
    public let latex: String
    public let mode: MathRenderMode
    public let accessibilityLabel: String
    public let payload: MathRenderPayload

    public init(
        latex: String,
        mode: MathRenderMode,
        accessibilityLabel: String,
        payload: MathRenderPayload
    ) {
        self.latex = latex
        self.mode = mode
        self.accessibilityLabel = accessibilityLabel
        self.payload = payload
    }
}

public protocol MathRenderer {
    func renderDisplay(latex: String, accessibilityLabel: String?) -> MathRenderResult
    func renderInline(latex: String, accessibilityLabel: String?) -> MathRenderResult
}

public extension MathRenderer {
    func renderDisplay(latex: String) -> MathRenderResult {
        renderDisplay(latex: latex, accessibilityLabel: nil)
    }

    func renderInline(latex: String) -> MathRenderResult {
        renderInline(latex: latex, accessibilityLabel: nil)
    }
}

public struct FallbackMathRenderer: MathRenderer, Sendable {
    public init() {}

    public func renderDisplay(latex: String, accessibilityLabel: String?) -> MathRenderResult {
        renderPlainText(latex: latex, mode: .display, accessibilityLabel: accessibilityLabel)
    }

    public func renderInline(latex: String, accessibilityLabel: String?) -> MathRenderResult {
        renderPlainText(latex: latex, mode: .inline, accessibilityLabel: accessibilityLabel)
    }

    private func renderPlainText(
        latex: String,
        mode: MathRenderMode,
        accessibilityLabel: String?
    ) -> MathRenderResult {
        MathRenderResult(
            latex: latex,
            mode: mode,
            accessibilityLabel: accessibilityLabel ?? latex,
            payload: .plainText(latex)
        )
    }
}

public protocol RatexMathRenderingAdapter {
    func renderSVG(latex: String, mode: MathRenderMode, options: RatexRenderOptions) throws -> String
}

public extension RatexMathRenderingAdapter {
    func renderSVG(latex: String, mode: MathRenderMode) throws -> String {
        try renderSVG(latex: latex, mode: mode, options: RatexRenderOptions())
    }
}

public struct RatexRenderOptions: Codable, Hashable, Sendable {
    public var fontSize: Double
    public var foregroundColor: String
    public var timeoutSeconds: Double

    public init(
        fontSize: Double = 18,
        foregroundColor: String = "#111111",
        timeoutSeconds: Double = 5
    ) {
        self.fontSize = fontSize
        self.foregroundColor = foregroundColor
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct RatexMathRenderer: MathRenderer {
    private let adapter: (any RatexMathRenderingAdapter)?
    private let options: RatexRenderOptions

    public init(
        adapter: (any RatexMathRenderingAdapter)? = RatexSVGCLIAdapter(),
        options: RatexRenderOptions = RatexRenderOptions()
    ) {
        self.adapter = adapter
        self.options = options
    }

    public func renderDisplay(latex: String, accessibilityLabel: String?) -> MathRenderResult {
        render(latex: latex, mode: .display, accessibilityLabel: accessibilityLabel)
    }

    public func renderInline(latex: String, accessibilityLabel: String?) -> MathRenderResult {
        render(latex: latex, mode: .inline, accessibilityLabel: accessibilityLabel)
    }

    private func render(
        latex: String,
        mode: MathRenderMode,
        accessibilityLabel: String?
    ) -> MathRenderResult {
        let label = accessibilityLabel ?? latex

        guard let adapter else {
            return MathRenderResult(
                latex: latex,
                mode: mode,
                accessibilityLabel: label,
                payload: .unavailable(reason: "RaTeX SVG adapter is not connected")
            )
        }

        do {
            return MathRenderResult(
                latex: latex,
                mode: mode,
                accessibilityLabel: label,
                payload: .svg(try adapter.renderSVG(latex: latex, mode: mode, options: options))
            )
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return MathRenderResult(
                latex: latex,
                mode: mode,
                accessibilityLabel: label,
                payload: .unavailable(reason: "RaTeX SVG adapter failed: \(reason)")
            )
        }
    }
}
