import Foundation

public struct ReaderMarkdownBlockSegment: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case markdown
        case displayMath
    }

    public var id: String
    public var kind: Kind
    public var text: String

    public init(id: String, kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = text
    }
}

public enum ReaderMarkdownBlockSegmenter {
    public static func segments(in markdown: String) -> [ReaderMarkdownBlockSegment] {
        let key = markdown as NSString
        if let cached = segmentCache.object(forKey: key) {
            return cached.segments
        }
        let segments = parsedSegments(in: markdown)
        segmentCache.setObject(Entry(segments: segments), forKey: key)
        return segments
    }

    static func removeAllForTesting() {
        segmentCache.removeAllObjects()
    }

    static func hasCachedSegments(for markdown: String) -> Bool {
        segmentCache.object(forKey: markdown as NSString) != nil
    }

    private final class Entry {
        let segments: [ReaderMarkdownBlockSegment]

        init(segments: [ReaderMarkdownBlockSegment]) {
            self.segments = segments
        }
    }

    private static let segmentCache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 2_048
        return cache
    }()

    private static func parsedSegments(in markdown: String) -> [ReaderMarkdownBlockSegment] {
        var segments: [ReaderMarkdownBlockSegment] = []
        var cursor = markdown.startIndex
        var ordinal = 0

        func append(kind: ReaderMarkdownBlockSegment.Kind, text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            segments.append(
                ReaderMarkdownBlockSegment(
                    id: "\(kind.rawValue)-\(ordinal)",
                    kind: kind,
                    text: trimmed
                )
            )
            ordinal += 1
        }

        func appendMarkdown(upTo index: String.Index) {
            guard cursor < index else { return }
            append(kind: .markdown, text: String(markdown[cursor..<index]))
            cursor = index
        }

        while cursor < markdown.endIndex {
            guard let match = nextDisplayMath(in: markdown, from: cursor) else {
                appendMarkdown(upTo: markdown.endIndex)
                break
            }
            appendMarkdown(upTo: match.range.lowerBound)
            append(kind: .displayMath, text: decodeHTMLEntities(match.latex))
            cursor = match.range.upperBound
        }

        return segments.isEmpty && !markdown.isEmpty
            ? [
                ReaderMarkdownBlockSegment(
                    id: "markdown-0",
                    kind: .markdown,
                    text: markdown.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            ].filter { !$0.text.isEmpty }
            : segments
    }

    private struct DisplayMathMatch {
        var range: Range<String.Index>
        var latex: String
    }

    private static func nextDisplayMath(in markdown: String, from start: String.Index) -> DisplayMathMatch? {
        var cursor = start
        while cursor < markdown.endIndex {
            if markdown[cursor...].hasPrefix("$$"), !isEscaped(cursor, in: markdown) {
                if let match = dollarDisplayMath(in: markdown, at: cursor) {
                    return match
                }
            }
            if markdown[cursor...].hasPrefix(#"\["#) {
                if let match = bracketDisplayMath(in: markdown, at: cursor) {
                    return match
                }
            }
            if markdown[cursor...].hasPrefix(#"\begin{"#) {
                if let match = environmentDisplayMath(in: markdown, at: cursor) {
                    return match
                }
            }
            if markdown[cursor] == "<" {
                if let match = htmlDisplayMath(in: markdown, at: cursor) {
                    return match
                }
            }
            cursor = markdown.index(after: cursor)
        }
        return nil
    }

    private static func dollarDisplayMath(in markdown: String, at index: String.Index) -> DisplayMathMatch? {
        let contentStart = markdown.index(index, offsetBy: 2)
        guard contentStart < markdown.endIndex else { return nil }

        var cursor = contentStart
        while cursor < markdown.endIndex {
            if markdown[cursor...].hasPrefix("$$"), !isEscaped(cursor, in: markdown) {
                let latex = String(markdown[contentStart..<cursor])
                let trimmedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLatex.isEmpty else { return nil }
                return DisplayMathMatch(
                    range: index..<markdown.index(cursor, offsetBy: 2),
                    latex: trimmedLatex
                )
            }
            cursor = markdown.index(after: cursor)
        }
        return nil
    }

    private static func bracketDisplayMath(in markdown: String, at index: String.Index) -> DisplayMathMatch? {
        guard markdown[index...].hasPrefix(#"\["#) else { return nil }
        let contentStart = markdown.index(index, offsetBy: 2)
        guard let close = markdown[contentStart...].range(of: #"\]"#) else {
            return nil
        }
        let latex = String(markdown[contentStart..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else { return nil }
        return DisplayMathMatch(range: index..<close.upperBound, latex: latex)
    }

    private static func environmentDisplayMath(in markdown: String, at index: String.Index) -> DisplayMathMatch? {
        let beginPrefix = #"\begin{"#
        guard markdown[index...].hasPrefix(beginPrefix) else { return nil }
        let environmentNameStart = markdown.index(index, offsetBy: beginPrefix.count)
        guard let environmentNameEnd = markdown[environmentNameStart...].firstIndex(of: "}") else {
            return nil
        }
        let environmentName = String(markdown[environmentNameStart..<environmentNameEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEnvironmentName = environmentName.lowercased()
        guard displayMathEnvironments.contains(normalizedEnvironmentName) else {
            return nil
        }

        let contentStart = markdown.index(after: environmentNameEnd)
        let closeToken = "\\end{\(environmentName)}"
        guard let close = markdown[contentStart...].range(of: closeToken) else {
            return nil
        }
        let body = String(markdown[contentStart..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let fullRange = index..<close.upperBound
        let latex = bodyOnlyDisplayMathEnvironments.contains(normalizedEnvironmentName)
            ? body
            : String(markdown[fullRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return DisplayMathMatch(range: fullRange, latex: latex)
    }

    private static func htmlDisplayMath(in markdown: String, at index: String.Index) -> DisplayMathMatch? {
        if let match = htmlMathDisplayTag(in: markdown, at: index) {
            return match
        }
        if let match = htmlScriptDisplayMathTag(in: markdown, at: index) {
            return match
        }
        return htmlClassedDisplayMathTag(in: markdown, at: index)
    }

    private static func htmlMathDisplayTag(in markdown: String, at index: String.Index) -> DisplayMathMatch? {
        guard markdown[index...].lowercased().hasPrefix("<math") else { return nil }
        guard let openingEnd = markdown[index...].firstIndex(of: ">") else { return nil }
        let openingTag = String(markdown[index...openingEnd])
        guard isDisplayMathOpeningTag(openingTag) else { return nil }
        guard let close = markdown[openingEnd...].range(
            of: "</math>",
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let body = String(markdown[markdown.index(after: openingEnd)..<close.lowerBound])
        let latex = htmlMathLatex(openingTag: openingTag, body: body)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else { return nil }
        return DisplayMathMatch(range: index..<close.upperBound, latex: latex)
    }

    private static func htmlScriptDisplayMathTag(in markdown: String, at index: String.Index) -> DisplayMathMatch? {
        guard markdown[index...].lowercased().hasPrefix("<script") else { return nil }
        guard let openingEnd = markdown[index...].firstIndex(of: ">") else { return nil }
        let openingTag = String(markdown[index...openingEnd])
        guard let type = htmlAttribute("type", in: openingTag)?.lowercased(),
              type.contains("math/tex"),
              type.contains("mode=display")
        else {
            return nil
        }
        guard let close = markdown[openingEnd...].range(
            of: "</script>",
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let latex = String(markdown[markdown.index(after: openingEnd)..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else { return nil }
        return DisplayMathMatch(range: index..<close.upperBound, latex: latex)
    }

    private static func htmlClassedDisplayMathTag(in markdown: String, at index: String.Index) -> DisplayMathMatch? {
        guard let tagName = openingHTMLTagName(in: markdown, at: index),
              displayMathContainerTags.contains(tagName)
        else {
            return nil
        }
        guard let openingEnd = markdown[index...].firstIndex(of: ">") else { return nil }
        let openingTag = String(markdown[index...openingEnd])
        guard isDisplayMathOpeningTag(openingTag) else { return nil }
        guard let closeRange = matchingHTMLCloseRange(
            tagName: tagName,
            in: markdown,
            openingStart: index,
            openingEnd: openingEnd
        ) else {
            return nil
        }
        let body = String(markdown[markdown.index(after: openingEnd)..<closeRange.lowerBound])
        let latex = htmlMathLatex(openingTag: openingTag, body: body)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else { return nil }
        return DisplayMathMatch(range: index..<closeRange.upperBound, latex: latex)
    }

    private static let bodyOnlyDisplayMathEnvironments: Set<String> = [
        "displaymath",
        "equation",
        "equation*"
    ]

    private static let displayMathEnvironments: Set<String> = [
        "align",
        "align*",
        "alignat",
        "alignat*",
        "displaymath",
        "eqnarray",
        "eqnarray*",
        "equation",
        "equation*",
        "flalign",
        "flalign*",
        "gather",
        "gather*",
        "multline",
        "multline*"
    ]

    private static let displayMathContainerTags: Set<String> = [
        "div",
        "p",
        "span",
        "table"
    ]

    private static func isDisplayMathOpeningTag(_ tag: String) -> Bool {
        if let display = htmlAttribute("display", in: tag)?.lowercased(),
           display == "block" || display == "display" || display == "true" {
            return true
        }
        return containsHTMLClass(named: "katex-display", in: tag)
            || containsHTMLClass(named: "ltx_equation", in: tag)
            || containsHTMLClass(named: "ltx_display_math", in: tag)
            || containsHTMLClasses(["math", "display"], in: tag)
    }

    private static func htmlMathLatex(openingTag: String, body: String) -> String {
        htmlAttribute("alttext", in: openingTag)
            ?? htmlAttribute("altText", in: openingTag)
            ?? htmlAttribute("tex", in: openingTag)
            ?? htmlAttribute("data-tex", in: openingTag)
            ?? htmlAttribute("data-latex", in: openingTag)
            ?? htmlAttribute("aria-label", in: openingTag)
            ?? htmlAnnotationTex(in: body)
            ?? cleanHTMLText(body)
    }

    private static func htmlAnnotationTex(in fragment: String) -> String? {
        let pattern = #"(?is)<annotation\b(?=[^>]*\bencoding\s*=\s*["']application/x-tex["'])[^>]*>([\s\S]*?)</annotation>"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: fragment, range: NSRange(fragment.startIndex..., in: fragment)),
            match.numberOfRanges >= 2,
            let range = Range(match.range(at: 1), in: fragment)
        else {
            return nil
        }
        return decodeHTMLEntities(String(fragment[range]))
    }

    private static func openingHTMLTagName(in markdown: String, at index: String.Index) -> String? {
        guard index < markdown.endIndex, markdown[index] == "<" else { return nil }
        var cursor = markdown.index(after: index)
        guard cursor < markdown.endIndex, markdown[cursor].isLetter else { return nil }
        let start = cursor
        while cursor < markdown.endIndex, markdown[cursor].isLetter {
            cursor = markdown.index(after: cursor)
        }
        return String(markdown[start..<cursor]).lowercased()
    }

    private static func matchingHTMLCloseRange(
        tagName: String,
        in markdown: String,
        openingStart: String.Index,
        openingEnd: String.Index
    ) -> Range<String.Index>? {
        var depth = 1
        var cursor = markdown.index(after: openingEnd)
        let openToken = "<\(tagName)"
        let closeToken = "</\(tagName)>"

        while cursor < markdown.endIndex {
            let searchRange = cursor..<markdown.endIndex
            let nextOpen = markdown.range(
                of: openToken,
                options: [.caseInsensitive],
                range: searchRange
            )
            let nextClose = markdown.range(
                of: closeToken,
                options: [.caseInsensitive],
                range: searchRange
            )
            guard let nextClose else { return nil }

            if let nextOpen, nextOpen.lowerBound < nextClose.lowerBound {
                if nextOpen.lowerBound != openingStart {
                    depth += 1
                }
                cursor = nextOpen.upperBound
            } else {
                depth -= 1
                if depth == 0 {
                    return nextClose
                }
                cursor = nextClose.upperBound
            }
        }
        return nil
    }

    private static func htmlAttribute(_ name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?i)\b"# + escapedName + #"\s*=\s*(["'])([\s\S]*?)\1"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
            match.numberOfRanges >= 3,
            let valueRange = Range(match.range(at: 2), in: tag)
        else {
            return nil
        }
        return decodeHTMLEntities(String(tag[valueRange]))
    }

    private static func containsHTMLClass(named className: String, in tag: String) -> Bool {
        guard let classValue = htmlAttribute("class", in: tag) else { return false }
        let normalizedTarget = className.lowercased()
        return classValue
            .split(whereSeparator: \.isWhitespace)
            .contains { $0.lowercased() == normalizedTarget }
    }

    private static func containsHTMLClasses(_ classNames: [String], in tag: String) -> Bool {
        guard let classValue = htmlAttribute("class", in: tag) else { return false }
        let actualClasses = Set(classValue.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })
        return classNames.allSatisfy { actualClasses.contains($0.lowercased()) }
    }

    private static func cleanHTMLText(_ fragment: String) -> String {
        let withoutTags = replacingRegex(#"(?is)<[^>]+>"#, in: fragment, with: "")
        return decodeHTMLEntities(withoutTags)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingRegex(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        return regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: replacement
        )
    }

    private static func isEscaped(_ index: String.Index, in markdown: String) -> Bool {
        var backslashCount = 0
        var cursor = index
        while cursor > markdown.startIndex {
            cursor = markdown.index(before: cursor)
            guard markdown[cursor] == "\\" else { break }
            backslashCount += 1
        }
        return backslashCount % 2 == 1
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
