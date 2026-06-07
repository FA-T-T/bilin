import Foundation

public struct ReaderInlineRun: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case text
        case inlineMath
        case citation
        case crossReference
    }

    public var id: String
    public var kind: Kind
    public var text: String
    public var payload: String?

    public init(id: String, kind: Kind, text: String, payload: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.payload = payload
    }
}

public enum ReaderInlineMarkupParser {
    public static func runs(in markdown: String) -> [ReaderInlineRun] {
        var runs: [ReaderInlineRun] = []
        var cursor = markdown.startIndex
        var ordinal = 0

        func appendText(upTo index: String.Index) {
            guard cursor < index else { return }
            appendRun(kind: .text, text: String(markdown[cursor..<index]), payload: nil)
            cursor = index
        }

        func appendRun(kind: ReaderInlineRun.Kind, text: String, payload: String?) {
            guard !text.isEmpty else { return }
            runs.append(
                ReaderInlineRun(
                    id: "\(runs.count)-\(ordinal)",
                    kind: kind,
                    text: text,
                    payload: payload
                )
            )
            ordinal += 1
        }

        while cursor < markdown.endIndex {
            if let match = nextToken(in: markdown, from: cursor) {
                appendText(upTo: match.range.lowerBound)
                appendRun(kind: match.kind, text: match.text, payload: match.payload)
                cursor = match.range.upperBound
            } else {
                appendText(upTo: markdown.endIndex)
            }
        }

        return runs
    }

    private struct InlineMatch {
        var range: Range<String.Index>
        var kind: ReaderInlineRun.Kind
        var text: String
        var payload: String?
    }

    private static func nextToken(in markdown: String, from start: String.Index) -> InlineMatch? {
        var index = start
        while index < markdown.endIndex {
            if markdown[index] == "\\" {
                if let match = escapedParenthesizedMath(in: markdown, at: index) {
                    return match
                }
                if let match = citeCommand(in: markdown, at: index) {
                    return match
                }
            }
            if markdown[index] == "$",
               let match = dollarMath(in: markdown, at: index) {
                return match
            }
            if markdown[index] == "[",
               let match = markdownLink(in: markdown, at: index) ?? bracketCitation(in: markdown, at: index) {
                return match
            }
            if markdown[index] == "<", !isEscaped(index, in: markdown),
               let match = htmlInlineToken(in: markdown, at: index) {
                return match
            }
            index = markdown.index(after: index)
        }
        return nil
    }

    private static func escapedParenthesizedMath(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index...].hasPrefix(#"\("#) else { return nil }
        let contentStart = markdown.index(index, offsetBy: 2)
        guard let close = markdown[contentStart...].range(of: #"\)"#) else {
            return nil
        }
        let latex = decodeHTMLEntities(String(markdown[contentStart..<close.lowerBound]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return InlineMatch(
            range: index..<close.upperBound,
            kind: .inlineMath,
            text: latex,
            payload: latex
        )
    }

    private static func dollarMath(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index] == "$" else { return nil }
        if isEscaped(index, in: markdown) { return nil }
        let next = markdown.index(after: index)
        if next < markdown.endIndex, markdown[next] == "$" { return nil }
        guard next < markdown.endIndex else { return nil }

        var cursor = next
        while cursor < markdown.endIndex {
            if markdown[cursor] == "$", !isEscaped(cursor, in: markdown) {
                let latex = decodeHTMLEntities(String(markdown[next..<cursor]))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !latex.isEmpty, looksLikeInlineMath(latex) else {
                    return nil
                }
                return InlineMatch(
                    range: index..<markdown.index(after: cursor),
                    kind: .inlineMath,
                    text: latex,
                    payload: latex
                )
            }
            cursor = markdown.index(after: cursor)
        }
        return nil
    }

    private static func looksLikeInlineMath(_ latex: String) -> Bool {
        if latex.contains("\\") || latex.contains("_") || latex.contains("^") {
            return true
        }
        if latex.contains(where: { character in
            "=<>±×÷∑∫√∞∂∇{}[]()".contains(character)
        }) {
            return true
        }

        let compact = latex.filter { !$0.isWhitespace }
        return compact.count <= 4 && compact.contains { $0.isLetter }
            || isNumericMathLiteral(compact)
    }

    private static func isNumericMathLiteral(_ value: String) -> Bool {
        guard value.contains(where: \.isNumber) else { return false }
        let normalized = value.replacingOccurrences(of: ",", with: "")
        return Double(normalized) != nil
    }

    private static func citeCommand(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index] == "\\" else { return nil }
        let commandStart = markdown.index(after: index)
        var commandEnd = commandStart
        while commandEnd < markdown.endIndex, markdown[commandEnd].isLetter {
            commandEnd = markdown.index(after: commandEnd)
        }
        let command = String(markdown[commandStart..<commandEnd]).lowercased()
        guard citationCommands.contains(command) else { return nil }

        var cursor = commandEnd
        if cursor < markdown.endIndex, markdown[cursor] == "*" {
            cursor = markdown.index(after: cursor)
        }
        skipWhitespace(in: markdown, cursor: &cursor)
        guard skipCitationOptions(in: markdown, cursor: &cursor) else { return nil }
        var keys: [String] = []
        var rangeEnd = cursor
        repeat {
            guard cursor < markdown.endIndex, markdown[cursor] == "{" else { break }
            let contentStart = markdown.index(after: cursor)
            guard let close = markdown[contentStart...].firstIndex(of: "}") else { return nil }
            let rawKeys = String(markdown[contentStart..<close])
            keys.append(contentsOf: citationKeys(from: rawKeys))
            rangeEnd = markdown.index(after: close)
            cursor = rangeEnd
            guard multiGroupCitationCommands.contains(command) else { break }
            skipWhitespace(in: markdown, cursor: &cursor)
            guard skipCitationOptions(in: markdown, cursor: &cursor) else { return nil }
        } while cursor < markdown.endIndex

        guard !keys.isEmpty else { return nil }
        return InlineMatch(
            range: index..<rangeEnd,
            kind: .citation,
            text: citationLabel(for: keys),
            payload: keys.joined(separator: ",")
        )
    }

    private static let citationCommands: Set<String> = [
        "cite",
        "citealp",
        "citealt",
        "citeauthor",
        "citep",
        "citet",
        "citepos",
        "citeposs",
        "cites",
        "citeyearpar",
        "autocite",
        "autocites",
        "footcite",
        "footcites",
        "citeyear",
        "citeyearnp",
        "parencite",
        "parencites",
        "smartcite",
        "smartcites",
        "supercite",
        "textcite",
        "textcites",
        "fullcite"
    ]

    private static let multiGroupCitationCommands: Set<String> = [
        "autocites",
        "cites",
        "footcites",
        "parencites",
        "smartcites",
        "textcites"
    ]

    private static func skipCitationOptions(in markdown: String, cursor: inout String.Index) -> Bool {
        while cursor < markdown.endIndex, markdown[cursor] == "[" {
            guard let optionClose = markdown[cursor...].firstIndex(of: "]") else { return false }
            cursor = markdown.index(after: optionClose)
            skipWhitespace(in: markdown, cursor: &cursor)
        }
        return true
    }

    private static func bracketCitation(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index] == "[" else { return nil }
        guard let close = markdown[index...].firstIndex(of: "]") else { return nil }
        let contentStart = markdown.index(after: index)
        let raw = String(markdown[contentStart..<close])
        let keys: [String]
        if raw.contains("@") {
            keys = citationKeys(from: raw)
        } else if isNumericCitation(raw) {
            keys = [raw.trimmingCharacters(in: .whitespacesAndNewlines)]
        } else {
            keys = []
        }
        guard !keys.isEmpty else { return nil }
        return InlineMatch(
            range: index..<markdown.index(after: close),
            kind: .citation,
            text: citationLabel(for: keys),
            payload: keys.joined(separator: ",")
        )
    }

    private static func markdownLink(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index] == "[" else { return nil }
        guard let labelClose = markdownLinkLabelClose(in: markdown, openingBracket: index) else { return nil }
        let parenStart = markdown.index(after: labelClose)
        guard parenStart < markdown.endIndex, markdown[parenStart] == "(" else { return nil }
        guard let parenClose = markdown[parenStart...].firstIndex(of: ")") else { return nil }
        let targetStart = markdown.index(after: parenStart)
        let rawHref = String(markdown[targetStart..<parenClose])
        let href = rawHref
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? rawHref
        let label = unescapedMarkdownLinkLabel(String(markdown[markdown.index(after: index)..<labelClose]))
        let bibliographyReference = bibliographyReference(from: href)
        return InlineMatch(
            range: index..<markdown.index(after: parenClose),
            kind: bibliographyReference == nil ? .crossReference : .citation,
            text: bibliographyReference == nil ? label : citationDisplayText(forBibliographyLabel: label),
            payload: bibliographyReference ?? href
        )
    }

    private static func markdownLinkLabelClose(in markdown: String, openingBracket: String.Index) -> String.Index? {
        var cursor = markdown.index(after: openingBracket)
        while cursor < markdown.endIndex {
            if markdown[cursor] == "]", !isEscaped(cursor, in: markdown) {
                return cursor
            }
            cursor = markdown.index(after: cursor)
        }
        return nil
    }

    private static func unescapedMarkdownLinkLabel(_ label: String) -> String {
        var output = ""
        var cursor = label.startIndex
        while cursor < label.endIndex {
            let character = label[cursor]
            if character == "\\" {
                let next = label.index(after: cursor)
                if next < label.endIndex, markdownEscapableLinkLabelCharacters.contains(label[next]) {
                    output.append(label[next])
                    cursor = label.index(after: next)
                    continue
                }
            }
            output.append(character)
            cursor = label.index(after: cursor)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let markdownEscapableLinkLabelCharacters = Set<Character>(["[", "]", "(", ")", "\\"])

    private static func htmlInlineToken(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index] == "<" else { return nil }
        if let match = htmlMathTag(in: markdown, at: index) {
            return match
        }
        if let match = htmlClassedMathTag(in: markdown, at: index) {
            return match
        }
        if let match = htmlScriptMathTag(in: markdown, at: index) {
            return match
        }
        if let match = htmlClassedCitationTag(in: markdown, at: index) {
            return match
        }
        if let match = htmlCitationTag(in: markdown, at: index) {
            return match
        }
        if let match = htmlAnchorTag(in: markdown, at: index) {
            return match
        }
        return nil
    }

    private static func htmlMathTag(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index...].lowercased().hasPrefix("<math") else { return nil }
        guard let openingEnd = markdown[index...].firstIndex(of: ">") else { return nil }
        let openingTag = String(markdown[index...openingEnd])
        let closeRange = markdown[openingEnd...].range(
            of: "</math>",
            options: [.caseInsensitive]
        )
        let rangeEnd = closeRange?.upperBound ?? markdown.index(after: openingEnd)
        let body = closeRange.map { String(markdown[markdown.index(after: openingEnd)..<$0.lowerBound]) } ?? ""
        let latex = htmlMathLatex(openingTag: openingTag, body: body)
        let normalizedLatex = decodeHTMLEntities(latex)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLatex.isEmpty else { return nil }
        return InlineMatch(
            range: index..<rangeEnd,
            kind: .inlineMath,
            text: normalizedLatex,
            payload: normalizedLatex
        )
    }

    private static func htmlClassedMathTag(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index...].lowercased().hasPrefix("<span") else { return nil }
        guard let openingEnd = markdown[index...].firstIndex(of: ">") else { return nil }
        let openingTag = String(markdown[index...openingEnd])
        guard containsHTMLClass(named: "ltx_Math", in: openingTag)
            || containsHTMLClass(named: "ltx_math", in: openingTag)
            || containsHTMLClass(named: "katex", in: openingTag)
            || containsHTMLClass(named: "MathJax", in: openingTag)
            || containsHTMLClasses(["math", "inline"], in: openingTag)
        else {
            return nil
        }
        let closeRange = matchingHTMLCloseRange(
            tagName: "span",
            in: markdown,
            openingStart: index,
            openingEnd: openingEnd
        )
        let rangeEnd = closeRange?.upperBound ?? markdown.index(after: openingEnd)
        let body = closeRange.map { String(markdown[markdown.index(after: openingEnd)..<$0.lowerBound]) } ?? ""
        let latex = htmlMathLatex(openingTag: openingTag, body: body)
        let normalizedLatex = decodeHTMLEntities(latex)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLatex.isEmpty else { return nil }
        return InlineMatch(
            range: index..<rangeEnd,
            kind: .inlineMath,
            text: normalizedLatex,
            payload: normalizedLatex
        )
    }

    private static func htmlScriptMathTag(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index...].lowercased().hasPrefix("<script") else { return nil }
        guard let openingEnd = markdown[index...].firstIndex(of: ">") else { return nil }
        let openingTag = String(markdown[index...openingEnd])
        guard let type = htmlAttribute("type", in: openingTag)?.lowercased(),
              type.contains("math/tex"),
              !type.contains("mode=display")
        else {
            return nil
        }
        guard let close = markdown[openingEnd...].range(
            of: "</script>",
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let body = String(markdown[markdown.index(after: openingEnd)..<close.lowerBound])
        let normalizedLatex = decodeHTMLEntities(body)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLatex.isEmpty else { return nil }
        return InlineMatch(
            range: index..<close.upperBound,
            kind: .inlineMath,
            text: normalizedLatex,
            payload: normalizedLatex
        )
    }

    private static func htmlClassedCitationTag(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index...].lowercased().hasPrefix("<span") else { return nil }
        guard let openingEnd = markdown[index...].firstIndex(of: ">") else { return nil }
        let openingTag = String(markdown[index...openingEnd])
        let dataCites = htmlAttribute("data-cites", in: openingTag)
            ?? htmlAttribute("data-cite", in: openingTag)
            ?? htmlAttribute("data-bibrefs", in: openingTag)
        guard containsHTMLClass(named: "citation", in: openingTag)
            || containsHTMLClass(named: "cite", in: openingTag)
            || containsHTMLClass(named: "ltx_cite", in: openingTag)
            || containsHTMLClass(withPrefix: "ltx_citemacro_", in: openingTag)
            || dataCites != nil
        else {
            return nil
        }
        let closeRange = matchingHTMLCloseRange(
            tagName: "span",
            in: markdown,
            openingStart: index,
            openingEnd: openingEnd
        )
        guard let closeRange else { return nil }

        let body = String(markdown[markdown.index(after: openingEnd)..<closeRange.lowerBound])
        let hrefs = htmlHrefValues(in: body).compactMap(bibliographyReference)
        let citedKeys = dataCites.map(citationKeys) ?? []
        let payloadReferences = citedKeys.isEmpty ? hrefs : citedKeys
        guard !payloadReferences.isEmpty else { return nil }
        let visibleText = cleanHTMLText(body)
        return InlineMatch(
            range: index..<closeRange.upperBound,
            kind: .citation,
            text: visibleText.isEmpty || visibleText == "[]"
                ? citationLabel(for: payloadReferences)
                : visibleText,
            payload: payloadReferences.joined(separator: ",")
        )
    }

    private static func htmlCitationTag(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index...].lowercased().hasPrefix("<cite") else { return nil }
        guard let openingEnd = markdown[index...].firstIndex(of: ">") else { return nil }
        let openingTag = String(markdown[index...openingEnd])
        guard let close = markdown[openingEnd...].range(
            of: "</cite>",
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let bodyStart = markdown.index(after: openingEnd)
        let body = String(markdown[bodyStart..<close.lowerBound])
        let hrefs = htmlHrefValues(in: body).compactMap(bibliographyReference)
        let missingCitationKeys = htmlMissingCitationKeys(in: body)
        let bibrefs = htmlBibrefValues(in: body)
        let openingReferences = htmlCitationReferences(in: openingTag)
        let payloadReferences = hrefs.isEmpty
            ? (missingCitationKeys.isEmpty
                ? (bibrefs.isEmpty ? openingReferences : bibrefs)
                : missingCitationKeys)
            : hrefs
        guard !payloadReferences.isEmpty else { return nil }
        let visibleText = openingReferences.isEmpty
            ? cleanCitationHTMLText(body)
            : cleanHTMLText(body)
        return InlineMatch(
            range: index..<close.upperBound,
            kind: .citation,
            text: visibleText.isEmpty || visibleText == "[]"
                ? citationLabel(for: payloadReferences)
                : visibleText,
            payload: payloadReferences.joined(separator: ",")
        )
    }

    private static func htmlAnchorTag(in markdown: String, at index: String.Index) -> InlineMatch? {
        guard markdown[index...].lowercased().hasPrefix("<a") else { return nil }
        guard let openingEnd = markdown[index...].firstIndex(of: ">") else { return nil }
        guard let close = markdown[openingEnd...].range(
            of: "</a>",
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let openingTag = String(markdown[index...openingEnd])
        guard let href = htmlAttribute("href", in: openingTag), !href.isEmpty else { return nil }
        let body = String(markdown[markdown.index(after: openingEnd)..<close.lowerBound])
        let label = cleanHTMLText(body)
        let bibliographyReference = bibliographyReference(from: href)
        return InlineMatch(
            range: index..<close.upperBound,
            kind: bibliographyReference == nil ? .crossReference : .citation,
            text: bibliographyReference == nil ? label : citationDisplayText(forBibliographyLabel: label),
            payload: bibliographyReference ?? href
        )
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

    private static func htmlCitationReferences(in tag: String) -> [String] {
        let rawReferences = htmlAttribute("data-cites", in: tag)
            ?? htmlAttribute("data-cite", in: tag)
            ?? htmlAttribute("data-bibrefs", in: tag)
        return rawReferences.map(citationKeys) ?? []
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

    private static func containsHTMLClass(named className: String, in tag: String) -> Bool {
        guard let classValue = htmlAttribute("class", in: tag) else { return false }
        let normalizedTarget = className.lowercased()
        return classValue
            .split(whereSeparator: \.isWhitespace)
            .contains { $0.lowercased() == normalizedTarget }
    }

    private static func containsHTMLClass(withPrefix prefix: String, in tag: String) -> Bool {
        guard let classValue = htmlAttribute("class", in: tag) else { return false }
        let normalizedPrefix = prefix.lowercased()
        return classValue
            .split(whereSeparator: \.isWhitespace)
            .contains { $0.lowercased().hasPrefix(normalizedPrefix) }
    }

    private static func containsHTMLClasses(_ classNames: [String], in tag: String) -> Bool {
        guard let classValue = htmlAttribute("class", in: tag) else { return false }
        let actualClasses = Set(classValue.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })
        return classNames.allSatisfy { actualClasses.contains($0.lowercased()) }
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

    private static func htmlHrefValues(in fragment: String) -> [String] {
        let pattern = #"(?is)<a\b[^>]*\bhref\s*=\s*(["'])([\s\S]*?)\1[^>]*>"#
        return htmlRegexCaptureValues(pattern: pattern, in: fragment)
            .map(decodeHTMLEntities)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func htmlMissingCitationKeys(in fragment: String) -> [String] {
        let pattern = #"(?is)<(?:span|a)\b(?=[^>]*\bltx_missing_citation\b)[^>]*>([\s\S]*?)</(?:span|a)>"#
        return htmlRegexCaptureValues(pattern: pattern, in: fragment)
            .map(cleanHTMLText)
            .flatMap(citationKeys)
    }

    private static func htmlBibrefValues(in fragment: String) -> [String] {
        let pattern = #"(?is)<bibref\b[^>]*\bbibrefs\s*=\s*(["'])([\s\S]*?)\1[^>]*/?>"#
        return htmlRegexCaptureValues(pattern: pattern, in: fragment)
            .flatMap(citationKeys)
    }

    private static func htmlRegexCaptureValues(pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .compactMap { match in
                let captureIndex = match.numberOfRanges > 2 ? 2 : 1
                guard let range = Range(match.range(at: captureIndex), in: value) else {
                    return nil
                }
                return String(value[range])
            }
    }

    private static func cleanCitationHTMLText(_ fragment: String) -> String {
        let text = cleanHTMLText(fragment)
            .replacingOccurrences(of: "[ ", with: "[")
            .replacingOccurrences(of: " ]", with: "]")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " ;", with: ";")
        guard !text.isEmpty else { return "" }
        return citationDisplayText(forBibliographyLabel: text)
    }

    private static func cleanHTMLText(_ fragment: String) -> String {
        let withoutTags = replacingRegex(#"(?is)<[^>]+>"#, in: fragment, with: "")
        let decoded = decodeHTMLEntities(withoutTags)
        return compactWhitespace(decoded)
    }

    private static func compactWhitespace(_ value: String) -> String {
        value
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

    private static func decodeHTMLEntities(_ value: String) -> String {
        ReaderHTMLEntityDecoder.decode(value)
    }

    private static func citationKeys(from raw: String) -> [String] {
        raw
            .split { character in
                character == "," || character == ";" || character.isWhitespace
            }
            .map { value in
                value
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[](){}@~"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func citationLabel(for keys: [String]) -> String {
        if keys.count == 1 {
            return "[\(keys[0])]"
        }
        return "[\(keys.joined(separator: "; "))]"
    }

    private static func citationDisplayText(forBibliographyLabel label: String) -> String {
        guard !label.isEmpty else { return "[citation]" }
        if label.hasPrefix("[") && label.hasSuffix("]") {
            return label
        }
        return "[\(label)]"
    }

    private static func isNumericCitation(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: { $0.isNumber }) else { return false }
        return trimmed.allSatisfy { character in
            character.isNumber
                || character.isWhitespace
                || character == ","
                || character == ";"
                || character == "-"
                || character == "–"
                || character == "—"
        }
    }

    private static func isBibliographyHref(_ href: String) -> Bool {
        bibliographyReference(from: href) != nil
    }

    private static func bibliographyReference(from href: String) -> String? {
        let normalized = href.trimmingCharacters(in: .whitespacesAndNewlines)
        let fragment = normalized
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .last
            .map(String.init) ?? normalized
        let reference = fragment
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let lowercasedReference = reference.lowercased()
        guard lowercasedReference.hasPrefix("bib.")
            || lowercasedReference.hasPrefix("bib:")
            || lowercasedReference.hasPrefix("bib-")
            || lowercasedReference.hasPrefix("bibitem.")
            || lowercasedReference.hasPrefix("bibitem:")
            || lowercasedReference.hasPrefix("ref-")
            || lowercasedReference.hasPrefix("bibliography")
        else {
            return nil
        }
        return "#\(reference)"
    }

    private static func skipWhitespace(in markdown: String, cursor: inout String.Index) {
        while cursor < markdown.endIndex, markdown[cursor].isWhitespace {
            cursor = markdown.index(after: cursor)
        }
    }

    private static func isEscaped(_ index: String.Index, in markdown: String) -> Bool {
        guard index > markdown.startIndex else { return false }
        var slashCount = 0
        var cursor = markdown.index(before: index)
        while true {
            guard markdown[cursor] == "\\" else { break }
            slashCount += 1
            if cursor == markdown.startIndex { break }
            cursor = markdown.index(before: cursor)
        }
        return slashCount % 2 == 1
    }
}
