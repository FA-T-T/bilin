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
}

public struct EquationTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var latex: String
    public var selectedInsertOffset: Int?

    public init(id: String, title: String, latex: String, selectedInsertOffset: Int? = nil) {
        self.id = id
        self.title = title
        self.latex = latex
        self.selectedInsertOffset = selectedInsertOffset
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

public enum EquationTemplateCatalog {
    public static let groups: [EquationTemplateGroup] = [
        EquationTemplateGroup(
            id: "structure",
            title: "Structure",
            templates: [
                EquationTemplate(id: "frac", title: "Fraction", latex: #"\frac{}{}"#),
                EquationTemplate(id: "sqrt", title: "Root", latex: #"\sqrt{}"#),
                EquationTemplate(id: "sup", title: "Power", latex: #"^{}"#),
                EquationTemplate(id: "sub", title: "Index", latex: #"_{}"#),
                EquationTemplate(id: "sum", title: "Sum", latex: #"\sum_{i=1}^{n}"#),
                EquationTemplate(id: "int", title: "Integral", latex: #"\int_{a}^{b}"#)
            ]
        ),
        EquationTemplateGroup(
            id: "greek",
            title: "Greek",
            templates: [
                EquationTemplate(id: "alpha", title: "alpha", latex: #"\alpha"#),
                EquationTemplate(id: "beta", title: "beta", latex: #"\beta"#),
                EquationTemplate(id: "gamma", title: "gamma", latex: #"\gamma"#),
                EquationTemplate(id: "theta", title: "theta", latex: #"\theta"#),
                EquationTemplate(id: "lambda", title: "lambda", latex: #"\lambda"#),
                EquationTemplate(id: "omega", title: "omega", latex: #"\omega"#)
            ]
        ),
        EquationTemplateGroup(
            id: "operators",
            title: "Operators",
            templates: [
                EquationTemplate(id: "times", title: "times", latex: #"\times"#),
                EquationTemplate(id: "cdot", title: "dot", latex: #"\cdot"#),
                EquationTemplate(id: "leq", title: "<=", latex: #"\leq"#),
                EquationTemplate(id: "geq", title: ">=", latex: #"\geq"#),
                EquationTemplate(id: "approx", title: "approx", latex: #"\approx"#),
                EquationTemplate(id: "infty", title: "infty", latex: #"\infty"#)
            ]
        ),
        EquationTemplateGroup(
            id: "matrices",
            title: "Matrices",
            templates: [
                EquationTemplate(id: "pmatrix2", title: "2 x 2", latex: #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#),
                EquationTemplate(id: "bmatrix2", title: "[2 x 2]", latex: #"\begin{bmatrix} a & b \\ c & d \end{bmatrix}"#),
                EquationTemplate(id: "cases", title: "Cases", latex: #"\begin{cases} x & x > 0 \\ 0 & x \leq 0 \end{cases}"#),
                EquationTemplate(id: "aligned", title: "Aligned", latex: #"\begin{aligned} a &= b + c \\ d &= e + f \end{aligned}"#)
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
