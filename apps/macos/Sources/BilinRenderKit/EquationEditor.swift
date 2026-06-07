import Foundation

public enum EquationImageFormat: String, CaseIterable, Codable, Hashable, Sendable {
    case svg
    case gif
    case png
    case pdf
    case emf
}

public enum EquationDisplaySize: Int, CaseIterable, Codable, Hashable, Sendable {
    case pt5 = 5
    case pt9 = 9
    case pt10 = 10
    case pt12 = 12
    case pt18 = 18
    case pt20 = 20

    public var label: String {
        "\(rawValue) pt"
    }
}

public enum EquationDPI: Int, CaseIterable, Codable, Hashable, Sendable {
    case dpi50 = 50
    case dpi80 = 80
    case dpi100 = 100
    case dpi110 = 110
    case dpi120 = 120
    case dpi150 = 150
    case dpi200 = 200
    case dpi300 = 300
}

public enum EquationOutputColor: String, CaseIterable, Codable, Hashable, Sendable {
    case transparent
    case white
    case black
    case red
    case green
    case blue

    public var label: String {
        rawValue.capitalized
    }

    public var foregroundColor: String {
        switch self {
        case .transparent, .black:
            return "#111111"
        case .white:
            return "#FFFFFF"
        case .red:
            return "#C62828"
        case .green:
            return "#2E7D32"
        case .blue:
            return "#1565C0"
        }
    }
}

public enum EquationLayoutMode: String, CaseIterable, Codable, Hashable, Sendable {
    case inline
    case block

    public var renderMode: MathRenderMode {
        switch self {
        case .inline:
            return .inline
        case .block:
            return .display
        }
    }
}

public enum EquationExportTarget: String, CaseIterable, Codable, Hashable, Sendable {
    case wordpress
    case phpBB
    case tinyWiki
    case url
    case urlEncoded
    case xml
    case pre
    case doxygen
    case html
    case latex

    public var label: String {
        switch self {
        case .wordpress:
            return "WordPress"
        case .phpBB:
            return "phpBB"
        case .tinyWiki:
            return "Tiny Wiki"
        case .url:
            return "URL"
        case .urlEncoded:
            return "URL encoded"
        case .xml:
            return "XML"
        case .pre:
            return "pre"
        case .doxygen:
            return "Doxygen"
        case .html:
            return "HTML"
        case .latex:
            return "LaTeX"
        }
    }
}

public struct EquationEditorOptions: Codable, Hashable, Sendable {
    public var imageFormat: EquationImageFormat
    public var displaySize: EquationDisplaySize
    public var dpi: EquationDPI
    public var color: EquationOutputColor
    public var layoutMode: EquationLayoutMode
    public var exportTarget: EquationExportTarget

    public init(
        imageFormat: EquationImageFormat = .svg,
        displaySize: EquationDisplaySize = .pt12,
        dpi: EquationDPI = .dpi120,
        color: EquationOutputColor = .transparent,
        layoutMode: EquationLayoutMode = .block,
        exportTarget: EquationExportTarget = .latex
    ) {
        self.imageFormat = imageFormat
        self.displaySize = displaySize
        self.dpi = dpi
        self.color = color
        self.layoutMode = layoutMode
        self.exportTarget = exportTarget
    }

    public var ratexRenderOptions: RatexRenderOptions {
        RatexRenderOptions(
            fontSize: Double(displaySize.rawValue),
            foregroundColor: color.foregroundColor,
            timeoutSeconds: 5
        )
    }
}

public struct EquationTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var latex: String
    public var previewLatex: String?
    public var fallbackPreviewText: String?
    public var selectedInsertOffset: Int?

    public init(
        id: String,
        title: String,
        latex: String,
        previewLatex: String? = nil,
        fallbackPreviewText: String? = nil,
        selectedInsertOffset: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.latex = latex
        self.previewLatex = previewLatex
        self.fallbackPreviewText = fallbackPreviewText
        self.selectedInsertOffset = selectedInsertOffset
    }

    public var renderedPreviewLatex: String {
        previewLatex ?? latex
    }

    public var renderedFallbackPreviewText: String {
        fallbackPreviewText ?? renderedPreviewLatex
    }
}

public struct EquationTemplateGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var templates: [EquationTemplate]

    public init(id: String, title: String, templates: [EquationTemplate]) {
        self.id = id
        self.title = title
        self.templates = templates
    }
}

public struct EquationTextSelection: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int = 0, length: Int = 0) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    public func clamped(to text: String) -> EquationTextSelection {
        let textLength = text.utf16.count
        let safeLocation = min(max(0, location), textLength)
        let safeLength = min(max(0, length), textLength - safeLocation)
        return EquationTextSelection(location: safeLocation, length: safeLength)
    }
}

public struct EquationTemplateInsertionResult: Hashable, Sendable {
    public var latex: String
    public var selection: EquationTextSelection

    public init(latex: String, selection: EquationTextSelection) {
        self.latex = latex
        self.selection = selection
    }
}

public enum EquationTemplateInsertionPlanner {
    public static func insert(
        _ template: EquationTemplate,
        into latex: String,
        selection: EquationTextSelection
    ) -> EquationTemplateInsertionResult {
        let clampedSelection = selection.clamped(to: latex)
        let selectedText = substring(in: latex, selection: clampedSelection)
        let insertion = preparedInsertionLatex(
            template: template,
            selectedText: selectedText
        )
        let leadingSpace = leadingSeparator(
            before: clampedSelection.location,
            in: latex,
            insertion: insertion.latex,
            replacesSelection: clampedSelection.length > 0
        )
        let trailingSpace = trailingSeparator(
            after: clampedSelection.location + clampedSelection.length,
            in: latex,
            insertion: insertion.latex,
            replacesSelection: clampedSelection.length > 0
        )
        let replacement = leadingSpace + insertion.latex + trailingSpace
        let resultLatex = replacing(
            selection: clampedSelection,
            in: latex,
            with: replacement
        )
        let insertionStart = clampedSelection.location + leadingSpace.utf16.count
        let nextSelection = EquationTextSelection(
            location: insertionStart + insertion.selectionOffset,
            length: insertion.selectionLength
        )
        .clamped(to: resultLatex)
        return EquationTemplateInsertionResult(
            latex: resultLatex,
            selection: nextSelection
        )
    }

    private struct PreparedInsertion {
        var latex: String
        var selectionOffset: Int
        var selectionLength: Int
    }

    private static func preparedInsertionLatex(
        template: EquationTemplate,
        selectedText: String
    ) -> PreparedInsertion {
        if
            !selectedText.isEmpty,
            let firstPlaceholder = emptyPlaceholderRange(in: template.latex)
        {
            let filledLatex = replacingUTF16Range(
                firstPlaceholder,
                in: template.latex,
                with: selectedText
            )
            if let nextPlaceholder = emptyPlaceholderRange(in: filledLatex) {
                return PreparedInsertion(
                    latex: filledLatex,
                    selectionOffset: nextPlaceholder.location,
                    selectionLength: 0
                )
            }
            let endOffset = firstPlaceholder.location + selectedText.utf16.count
            return PreparedInsertion(
                latex: filledLatex,
                selectionOffset: endOffset,
                selectionLength: 0
            )
        }

        if let selectedInsertOffset = template.selectedInsertOffset {
            return PreparedInsertion(
                latex: template.latex,
                selectionOffset: min(max(0, selectedInsertOffset), template.latex.utf16.count),
                selectionLength: 0
            )
        }
        if let placeholder = emptyPlaceholderRange(in: template.latex) {
            return PreparedInsertion(
                latex: template.latex,
                selectionOffset: placeholder.location,
                selectionLength: 0
            )
        }
        return PreparedInsertion(
            latex: template.latex,
            selectionOffset: template.latex.utf16.count,
            selectionLength: 0
        )
    }

    private static func emptyPlaceholderRange(in latex: String) -> EquationTextSelection? {
        guard let range = latex.range(of: "{}") else { return nil }
        let location = latex.utf16.distance(
            from: latex.utf16.startIndex,
            to: range.lowerBound.samePosition(in: latex.utf16)!
        ) + 1
        return EquationTextSelection(location: location, length: 0)
    }

    private static func leadingSeparator(
        before location: Int,
        in latex: String,
        insertion: String,
        replacesSelection: Bool
    ) -> String {
        guard !latex.isEmpty, location > 0, !replacesSelection else { return "" }
        guard let previous = character(atUTF16Offset: location - 1, in: latex) else { return "" }
        guard let first = insertion.first, !first.isWhitespace else { return "" }
        if previous.isWhitespace || "{([_^=+-*/<>&|,;:".contains(previous) {
            return ""
        }
        if first == "}" || first == ")" || first == "]" || first == "^" || first == "_" {
            return ""
        }
        return " "
    }

    private static func trailingSeparator(
        after location: Int,
        in latex: String,
        insertion: String,
        replacesSelection: Bool
    ) -> String {
        guard !latex.isEmpty, location < latex.utf16.count, !replacesSelection else { return "" }
        guard let next = character(atUTF16Offset: location, in: latex) else { return "" }
        guard let last = insertion.last, !last.isWhitespace else { return "" }
        if next.isWhitespace || "})]_^=+-*/<>&|,;:".contains(next) {
            return ""
        }
        if last == "{" || last == "(" || last == "[" || last == "^" || last == "_" {
            return ""
        }
        return " "
    }

    private static func replacing(
        selection: EquationTextSelection,
        in text: String,
        with replacement: String
    ) -> String {
        replacingUTF16Range(selection, in: text, with: replacement)
    }

    private static func replacingUTF16Range(
        _ selection: EquationTextSelection,
        in text: String,
        with replacement: String
    ) -> String {
        let start = String.Index(utf16Offset: selection.location, in: text)
        let end = String.Index(utf16Offset: selection.location + selection.length, in: text)
        var output = text
        output.replaceSubrange(start..<end, with: replacement)
        return output
    }

    private static func substring(in text: String, selection: EquationTextSelection) -> String {
        guard selection.length > 0 else { return "" }
        let start = String.Index(utf16Offset: selection.location, in: text)
        let end = String.Index(utf16Offset: selection.location + selection.length, in: text)
        return String(text[start..<end])
    }

    private static func character(atUTF16Offset offset: Int, in text: String) -> Character? {
        guard offset >= 0, offset < text.utf16.count else { return nil }
        let index = String.Index(utf16Offset: offset, in: text)
        return text[index]
    }
}

public enum EquationTemplateCatalog {
    public static let groups: [EquationTemplateGroup] = [
        EquationTemplateGroup(
            id: "structure",
            title: "Structure",
            templates: [
                EquationTemplate(id: "frac", title: "Fraction", latex: #"\frac{}{}"#, previewLatex: #"\frac{a}{b}"#),
                EquationTemplate(id: "sqrt", title: "Root", latex: #"\sqrt{}"#, previewLatex: #"\sqrt{x}"#),
                EquationTemplate(id: "sup", title: "Power", latex: #"^{}"#, previewLatex: #"x^{2}"#),
                EquationTemplate(id: "sub", title: "Index", latex: #"_{}"#, previewLatex: #"x_{i}"#),
                EquationTemplate(id: "sum", title: "Sum", latex: #"\sum_{i=1}^{n}"#, previewLatex: #"\sum_{i=1}^{n} x_i"#),
                EquationTemplate(id: "int", title: "Integral", latex: #"\int_{a}^{b}"#, previewLatex: #"\int_{a}^{b} f(x)\,dx"#)
            ]
        ),
        EquationTemplateGroup(
            id: "greek",
            title: "Greek",
            templates: [
                EquationTemplate(id: "alpha", title: "alpha", latex: #"\alpha"#, fallbackPreviewText: "α"),
                EquationTemplate(id: "beta", title: "beta", latex: #"\beta"#, fallbackPreviewText: "β"),
                EquationTemplate(id: "gamma", title: "gamma", latex: #"\gamma"#, fallbackPreviewText: "γ"),
                EquationTemplate(id: "theta", title: "theta", latex: #"\theta"#, fallbackPreviewText: "θ"),
                EquationTemplate(id: "lambda", title: "lambda", latex: #"\lambda"#, fallbackPreviewText: "λ"),
                EquationTemplate(id: "omega", title: "omega", latex: #"\omega"#, fallbackPreviewText: "ω")
            ]
        ),
        EquationTemplateGroup(
            id: "operators",
            title: "Operators",
            templates: [
                EquationTemplate(id: "times", title: "times", latex: #"\times"#, fallbackPreviewText: "×"),
                EquationTemplate(id: "cdot", title: "dot", latex: #"\cdot"#, fallbackPreviewText: "·"),
                EquationTemplate(id: "leq", title: "<=", latex: #"\leq"#, fallbackPreviewText: "≤"),
                EquationTemplate(id: "geq", title: ">=", latex: #"\geq"#, fallbackPreviewText: "≥"),
                EquationTemplate(id: "approx", title: "approx", latex: #"\approx"#, fallbackPreviewText: "≈"),
                EquationTemplate(id: "infty", title: "infty", latex: #"\infty"#, fallbackPreviewText: "∞")
            ]
        ),
        EquationTemplateGroup(
            id: "matrices",
            title: "Matrices",
            templates: [
                EquationTemplate(id: "pmatrix2", title: "2 x 2", latex: #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#, fallbackPreviewText: "( a  b\n  c  d )"),
                EquationTemplate(id: "bmatrix2", title: "[2 x 2]", latex: #"\begin{bmatrix} a & b \\ c & d \end{bmatrix}"#, fallbackPreviewText: "[ a  b\n  c  d ]"),
                EquationTemplate(id: "cases", title: "Cases", latex: #"\begin{cases} x & x > 0 \\ 0 & x \leq 0 \end{cases}"#, fallbackPreviewText: "x, x > 0\n0, x <= 0"),
                EquationTemplate(id: "aligned", title: "Aligned", latex: #"\begin{aligned} a &= b + c \\ d &= e + f \end{aligned}"#, fallbackPreviewText: "a = b + c\nd = e + f")
            ]
        )
    ]
}

public enum EquationEditorExportBuilder {
    public static func exportString(
        latex: String,
        options: EquationEditorOptions
    ) -> String {
        let compactLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = compactLatex.addingPercentEncoding(withAllowedCharacters: latexURLAllowed) ?? compactLatex
        let mode = options.layoutMode == .inline ? "inline" : "block"
        let ratexURL = "ratex://render?format=\(options.imageFormat.rawValue)&size=\(options.displaySize.rawValue)&dpi=\(options.dpi.rawValue)&color=\(options.color.rawValue)&mode=\(mode)&latex=\(encoded)"
        let escapedLatex = escapeHTML(compactLatex)

        switch options.exportTarget {
        case .wordpress:
            return "[latex]\(compactLatex)[/latex]"
        case .phpBB:
            return "[tex]\(compactLatex)[/tex]"
        case .tinyWiki:
            return "$$\(compactLatex)$$"
        case .url:
            return ratexURL
        case .urlEncoded:
            return encoded
        case .xml:
            return #"<math renderer="ratex" mode="\#(mode)">\#(escapedLatex)</math>"#
        case .pre:
            return #"<pre><code class="language-latex">\#(escapedLatex)</code></pre>"#
        case .doxygen:
            return "\\f[\n\(compactLatex)\n\\f]"
        case .html:
            return #"<span class="bilin-math" data-renderer="ratex" data-mode="\#(mode)">\#(escapedLatex)</span>"#
        case .latex:
            return compactLatex
        }
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static var latexURLAllowed: CharacterSet {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }
}

public enum EquationSyntaxInspector {
    public static func diagnostics(for latex: String) -> [String] {
        var diagnostics: [String] = []
        let openBraces = latex.filter { $0 == "{" }.count
        let closeBraces = latex.filter { $0 == "}" }.count
        if openBraces != closeBraces {
            diagnostics.append("Brace mismatch: \(openBraces) open, \(closeBraces) close")
        }

        let beginCount = matches(pattern: #"\\begin\{"#, in: latex)
        let endCount = matches(pattern: #"\\end\{"#, in: latex)
        if beginCount != endCount {
            diagnostics.append("Environment mismatch: \(beginCount) begin, \(endCount) end")
        }

        return diagnostics
    }

    public static func commandPrefix(in latex: String) -> String? {
        guard let slash = latex.lastIndex(of: "\\") else { return nil }
        let suffix = latex[latex.index(after: slash)...]
        let command = suffix.prefix { $0.isLetter }
        guard !command.isEmpty else { return "" }
        return String(command)
    }

    public static func suggestions(
        for latex: String,
        templates: [EquationTemplate] = EquationTemplateCatalog.groups.flatMap(\.templates)
    ) -> [EquationTemplate] {
        guard let prefix = commandPrefix(in: latex) else { return [] }
        return templates.filter {
            $0.latex.dropFirst().hasPrefix(prefix) || $0.title.localizedCaseInsensitiveContains(prefix)
        }
    }

    private static func matches(pattern: String, in value: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        )
    }
}
