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
    // Future FFI boundary: call RaTeX and return renderer-neutral SVG text.
    func renderSVG(latex: String, mode: MathRenderMode) throws -> String
}

public struct RatexMathRenderer: MathRenderer {
    private let adapter: (any RatexMathRenderingAdapter)?

    public init(adapter: (any RatexMathRenderingAdapter)? = nil) {
        self.adapter = adapter
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
                payload: .svg(try adapter.renderSVG(latex: latex, mode: mode))
            )
        } catch {
            return MathRenderResult(
                latex: latex,
                mode: mode,
                accessibilityLabel: label,
                payload: .unavailable(reason: "RaTeX SVG adapter failed: \(error)")
            )
        }
    }
}
