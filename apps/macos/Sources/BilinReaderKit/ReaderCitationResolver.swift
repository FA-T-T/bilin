import Foundation

public struct ReaderCitationEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var title: String?
    public var rawText: String
    public var sourceBlockUid: String
    public var sourceStructuralPath: String

    public init(
        id: String,
        label: String,
        title: String? = nil,
        rawText: String,
        sourceBlockUid: String,
        sourceStructuralPath: String
    ) {
        self.id = id
        self.label = label
        self.title = title
        self.rawText = rawText
        self.sourceBlockUid = sourceBlockUid
        self.sourceStructuralPath = sourceStructuralPath
    }

    public var displayLabel: String {
        label.hasPrefix("[") && label.hasSuffix("]") ? label : "[\(label)]"
    }

    public var hasBibliographyEntry: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct ReaderBibliographyLine: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var sourceLine: String
    public var entry: ReaderCitationEntry?

    public init(
        id: String,
        sourceLine: String,
        entry: ReaderCitationEntry?
    ) {
        self.id = id
        self.sourceLine = sourceLine
        self.entry = entry
    }
}

public struct ReaderCitationResolver: Codable, Hashable, Sendable {
    public static let empty = ReaderCitationResolver(entries: [])

    public private(set) var entriesByAlias: [String: ReaderCitationEntry]
    public private(set) var signature: String

    public init(entries: [ReaderCitationEntry]) {
        var entriesByAlias: [String: ReaderCitationEntry] = [:]
        for entry in entries {
            for alias in Self.aliases(for: entry) {
                entriesByAlias[alias] = entry
            }
        }
        self.entriesByAlias = entriesByAlias
        self.signature = Self.signature(for: entriesByAlias)
    }

    public init(blocks: [DocumentBlock]) {
        self.init(entries: Self.entries(from: blocks))
    }

    private enum CodingKeys: String, CodingKey {
        case entriesByAlias
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entriesByAlias = try container.decode(
            [String: ReaderCitationEntry].self,
            forKey: .entriesByAlias
        )
        self.entriesByAlias = entriesByAlias
        self.signature = Self.signature(for: entriesByAlias)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entriesByAlias, forKey: .entriesByAlias)
    }

    public func resolve(_ run: ReaderInlineRun) -> ReaderCitationEntry? {
        guard run.kind == .citation else { return nil }
        guard let payload = run.payload else { return nil }
        for reference in Self.fallbackReferences(from: run) {
            if let entry = resolve(reference) {
                return entry
            }
        }
        return resolve(payload)
    }

    public func resolve(_ reference: String) -> ReaderCitationEntry? {
        let normalized = Self.normalizedReference(reference)
        for alias in Self.aliases(for: normalized) {
            if let entry = entriesByAlias[alias] {
                return entry
            }
        }
        return nil
    }

    public static func entries(from blocks: [DocumentBlock]) -> [ReaderCitationEntry] {
        var collectedEntries: [ReaderCitationEntry] = []
        for block in blocks where isBibliographyBlock(block) {
            collectedEntries.append(contentsOf: bibliographyLines(in: block).compactMap(\.entry))
        }
        collectedEntries.append(contentsOf: metadataReferenceEntries(from: blocks, existingEntries: collectedEntries))
        collectedEntries.append(contentsOf: fallbackEntries(from: blocks, existingEntries: collectedEntries))
        return collectedEntries
    }

    public static func bibliographyLines(in block: DocumentBlock) -> [ReaderBibliographyLine] {
        guard isBibliographyBlock(block) else { return [] }
        return bibliographySourceLines(in: block.sourceMarkdown)
            .enumerated()
            .compactMap { index, line in
                guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                let entry = entry(fromBibliographyLine: line, block: block)
                let id = entry?.id ?? "\(block.blockUid)-line-\(index)"
                return ReaderBibliographyLine(
                    id: id,
                    sourceLine: line,
                    entry: entry
                )
            }
    }

    private struct MetadataReference: Decodable {
        var href: String?
        var text: String?
        var title: String?
    }

    private static func signature(for entriesByAlias: [String: ReaderCitationEntry]) -> String {
        let canonicalRows = entriesByAlias
            .map { alias, entry in
                [
                    alias,
                    entry.id,
                    entry.label,
                    entry.title ?? "",
                    entry.rawText,
                    entry.sourceBlockUid,
                    entry.sourceStructuralPath
                ]
                .joined(separator: "\u{1e}")
            }
            .sorted()
            .joined(separator: "\u{1f}")

        return "reader-citations:v1:\(entriesByAlias.count):\(stableDigest(canonicalRows))"
    }

    private static func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private static func isBibliographyBlock(_ block: DocumentBlock) -> Bool {
        block.blockType == .bibliography
            || (block.blockType == .list && block.metadata["list_kind"] == "bibliography")
            || containsBibliographyListItem(block.sourceMarkdown)
            || containsHTMLBibliographyItem(block.sourceMarkdown)
    }

    private static func containsBibliographyListItem(_ markdown: String) -> Bool {
        markdown
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || startsWithOrderedListMarker(trimmed))
                    && containsBibliographyReference(trimmed)
            }
    }

    private static func containsBibliographyReference(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("#bib.")
            || lowercased.contains("#bib:")
            || lowercased.contains("#bib-")
            || lowercased.contains("#bibitem.")
            || lowercased.contains("#bibitem:")
            || lowercased.contains("#ref-")
            || lowercased.contains("#bibliography")
            || lowercased.contains("id=\"bib.")
            || lowercased.contains("id='bib.")
            || lowercased.contains("id=\"bib:")
            || lowercased.contains("id='bib:")
            || lowercased.contains("id=\"bib-")
            || lowercased.contains("id='bib-")
            || lowercased.contains("id=\"bibitem.")
            || lowercased.contains("id='bibitem.")
            || lowercased.contains("id=\"bibitem:")
            || lowercased.contains("id='bibitem:")
            || lowercased.contains("id=\"ref-")
            || lowercased.contains("id='ref-")
            || lowercased.contains("csl-entry")
    }

    private static func containsHTMLBibliographyItem(_ markdown: String) -> Bool {
        let lowercased = markdown.lowercased()
        return lowercased.contains("ltx_bibitem")
            || lowercased.contains("<li")
                && containsBibliographyReference(markdown)
    }

    private static func startsWithOrderedListMarker(_ text: String) -> Bool {
        guard let markerEnd = text.firstIndex(where: { $0 == "." || $0 == ")" }) else {
            return false
        }
        let marker = text[..<markerEnd]
        return !marker.isEmpty && marker.allSatisfy(\.isNumber)
    }

    private static func fallbackEntries(
        from blocks: [DocumentBlock],
        existingEntries: [ReaderCitationEntry]
    ) -> [ReaderCitationEntry] {
        var knownAliases = Set(existingEntries.flatMap { aliases(for: $0) })
        var fallbackEntries: [ReaderCitationEntry] = []

        for block in blocks {
            let citationRuns = ReaderInlineMarkupParser.runs(in: block.sourceMarkdown)
                .filter { $0.kind == .citation }
            for run in citationRuns {
                for reference in fallbackReferences(from: run) {
                    let normalized = normalizedReference(reference)
                    guard !normalized.isEmpty else { continue }
                    let aliases = aliases(for: normalized)
                    guard knownAliases.isDisjoint(with: aliases) else { continue }
                    knownAliases.formUnion(aliases)
                    fallbackEntries.append(
                        ReaderCitationEntry(
                            id: normalized,
                            label: fallbackLabel(from: run, reference: normalized),
                            rawText: "",
                            sourceBlockUid: block.blockUid,
                            sourceStructuralPath: block.structuralPath
                        )
                    )
                }
            }
        }

        return fallbackEntries
    }

    private static func metadataReferenceEntries(
        from blocks: [DocumentBlock],
        existingEntries: [ReaderCitationEntry]
    ) -> [ReaderCitationEntry] {
        var knownAliases = Set(existingEntries.flatMap { aliases(for: $0) })
        var entries: [ReaderCitationEntry] = []

        for block in blocks {
            guard
                let referencesJSON = block.metadata["references"],
                let data = referencesJSON.data(using: .utf8),
                let references = try? JSONDecoder().decode([MetadataReference].self, from: data)
            else {
                continue
            }

            for reference in references {
                guard
                    let href = reference.href,
                    isBibliographyReference(href)
                else {
                    continue
                }
                let normalized = normalizedReference(href)
                guard !normalized.isEmpty else { continue }
                let aliases = aliases(for: normalized)
                guard knownAliases.isDisjoint(with: aliases) else { continue }
                knownAliases.formUnion(aliases)
                entries.append(
                    ReaderCitationEntry(
                        id: normalized,
                        label: normalizedLabel(reference.text ?? normalized),
                        title: reference.title,
                        rawText: "",
                        sourceBlockUid: block.blockUid,
                        sourceStructuralPath: block.structuralPath
                    )
                )
            }
        }

        return entries
    }

    private static func fallbackReferences(from run: ReaderInlineRun) -> [String] {
        guard let payload = run.payload, !payload.isEmpty else { return [] }
        return payload
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func fallbackLabel(from run: ReaderInlineRun, reference: String) -> String {
        let label = normalizedLabel(run.text)
        guard !label.isEmpty, label.lowercased() != "citation" else {
            if reference.hasPrefix("bib.bib") {
                return String(reference.dropFirst("bib.bib".count))
            }
            if reference.hasPrefix("bib:bib") {
                return String(reference.dropFirst("bib:bib".count))
            }
            return reference
        }
        return label
    }

    private static func entry(
        fromBibliographyLine line: String,
        block: DocumentBlock
    ) -> ReaderCitationEntry? {
        if let entry = markdownEntry(fromBibliographyLine: line, block: block) {
            return entry
        }
        return htmlEntry(fromBibliographyLine: line, block: block)
    }

    private static func markdownEntry(
        fromBibliographyLine line: String,
        block: DocumentBlock
    ) -> ReaderCitationEntry? {
        let pattern = #"^\s*(?:(?:[-+*]|\d+[.)])\s+)?\[(.*?)\]\((#[^\s)]+)(?:\s+"[^"]*")?\)\s*(.*)$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            match.numberOfRanges == 4,
            let labelRange = Range(match.range(at: 1), in: line),
            let hrefRange = Range(match.range(at: 2), in: line),
            let rawRange = Range(match.range(at: 3), in: line)
        else {
            return nil
        }

        let id = normalizedReference(String(line[hrefRange]))
        let rawText = compactWhitespace(String(line[rawRange]))
        return ReaderCitationEntry(
            id: id,
            label: normalizedLabel(String(line[labelRange])),
            title: inferredTitle(from: rawText),
            rawText: rawText,
            sourceBlockUid: block.blockUid,
            sourceStructuralPath: block.structuralPath
        )
    }

    private static func htmlEntry(
        fromBibliographyLine line: String,
        block: DocumentBlock
    ) -> ReaderCitationEntry? {
        guard let openingTag = firstOpeningHTMLTag(in: line) else { return nil }
        let id = htmlAttribute("id", in: openingTag)
            ?? firstBibliographyHref(in: line)
        guard let id, isBibliographyReference(id) else { return nil }
        let label = htmlBibliographyLabel(in: line) ?? displayLabel(fromReference: id)
        let rawText = htmlBibliographyRawText(in: line, label: label)
        return ReaderCitationEntry(
            id: normalizedReference(id),
            label: normalizedLabel(label),
            title: inferredTitle(from: rawText),
            rawText: rawText,
            sourceBlockUid: block.blockUid,
            sourceStructuralPath: block.structuralPath
        )
    }

    private static func bibliographySourceLines(in markdown: String) -> [String] {
        let htmlItems = htmlBibliographyItems(in: markdown)
        if !htmlItems.isEmpty {
            return htmlItems
        }
        return markdown.components(separatedBy: CharacterSet.newlines)
    }

    private static func htmlBibliographyItems(in markdown: String) -> [String] {
        ["li", "div", "p"].flatMap { tagName in
            htmlBibliographyItems(tagName: tagName, in: markdown)
        }
    }

    private static func htmlBibliographyItems(tagName: String, in markdown: String) -> [String] {
        let escapedTagName = NSRegularExpression.escapedPattern(for: tagName)
        let pattern = #"(?is)<"# + escapedTagName + #"\b(?=[^>]*(?:id\s*=\s*["']#?(?:(?:bib|bibitem)[.:]|bib-|ref-)|class\s*=\s*["'][^"']*\b(?:ltx_bibitem|csl-entry)\b))[^>]*>[\s\S]*?</"# + escapedTagName + #">"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
            .compactMap { match in
                guard let range = Range(match.range, in: markdown) else { return nil }
                return String(markdown[range])
            }
            .filter(containsBibliographyReference)
    }

    private static func firstOpeningHTMLTag(in value: String) -> String? {
        let pattern = #"(?is)<(?:li|div|p|span)\b[^>]*>"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
            let range = Range(match.range, in: value)
        else {
            return nil
        }
        return String(value[range])
    }

    private static func firstBibliographyHref(in value: String) -> String? {
        let pattern = #"(?is)<a\b[^>]*\bhref\s*=\s*(["'])(#[^"']*(?:(?:bib|bibitem)[.:]|bib-|ref-)[^"']*)\1[^>]*>"#
        return htmlRegexCaptureValues(pattern: pattern, in: value).first
    }

    private static func htmlBibliographyLabel(in value: String) -> String? {
        let tagPattern = #"(?is)<span\b(?=[^>]*\bltx_tag\b)[^>]*>([\s\S]*?)</span>"#
        if let label = htmlRegexCaptureValues(pattern: tagPattern, in: value)
            .map(cleanHTMLText)
            .first(where: { !$0.isEmpty })
        {
            return label
        }

        let text = cleanHTMLText(value)
        let labelPattern = #"^\s*(\[[^\]]+\]|\d+[.)])"#
        guard
            let regex = try? NSRegularExpression(pattern: labelPattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    private static func htmlBibliographyRawText(in value: String, label: String) -> String {
        var rawText = cleanHTMLText(value)
        let normalized = normalizedLabel(label)
        for prefix in ["[\(normalized)]", "\(normalized).", "\(normalized)"] where rawText.hasPrefix(prefix) {
            rawText.removeFirst(prefix.count)
            break
        }
        return compactWhitespace(rawText)
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

    private static func htmlRegexCaptureValues(pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .compactMap { match in
                let captureIndex = match.numberOfRanges > 2 ? 2 : 1
                guard let range = Range(match.range(at: captureIndex), in: value) else {
                    return nil
                }
                return decodeHTMLEntities(String(value[range]))
            }
    }

    private static func cleanHTMLText(_ fragment: String) -> String {
        let withoutTags = replacingRegex(#"(?is)<[^>]+>"#, in: fragment, with: "")
        return compactWhitespace(decodeHTMLEntities(withoutTags))
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

    private static func isBibliographyReference(_ reference: String) -> Bool {
        let normalized = normalizedReference(reference)
        return normalized.hasPrefix("bib.")
            || normalized.hasPrefix("bib:")
            || normalized.hasPrefix("bib-")
            || normalized.hasPrefix("bibitem.")
            || normalized.hasPrefix("bibitem:")
            || normalized.hasPrefix("ref-")
            || normalized.hasPrefix("bibliography")
    }

    private static func aliases(for reference: String) -> [String] {
        let normalized = normalizedReference(reference)
        var aliases = Set([normalized, "#\(normalized)"])
        if normalized.hasPrefix("bib.") {
            let key = String(normalized.dropFirst("bib.".count))
            aliases.insert("bib:\(key)")
            aliases.insert("#bib:\(key)")
            aliases.insert("bib-\(key)")
            aliases.insert("#bib-\(key)")
        }
        if normalized.hasPrefix("bib:") {
            let key = String(normalized.dropFirst("bib:".count))
            aliases.insert("bib.\(key)")
            aliases.insert("#bib.\(key)")
            aliases.insert("bib-\(key)")
            aliases.insert("#bib-\(key)")
        }
        if normalized.hasPrefix("bib-") {
            let key = String(normalized.dropFirst("bib-".count))
            aliases.insert("bib.\(key)")
            aliases.insert("#bib.\(key)")
            aliases.insert("bib:\(key)")
            aliases.insert("#bib:\(key)")
            aliases.insert(key)
            aliases.insert("@\(key)")
        }
        if normalized.hasPrefix("bibitem.") {
            let key = String(normalized.dropFirst("bibitem.".count))
            aliases.insert("bibitem:\(key)")
            aliases.insert("#bibitem:\(key)")
            aliases.insert("bib.\(key)")
            aliases.insert("#bib.\(key)")
            aliases.insert("bib:\(key)")
            aliases.insert("#bib:\(key)")
            aliases.insert("bib-\(key)")
            aliases.insert("#bib-\(key)")
        }
        if normalized.hasPrefix("bibitem:") {
            let key = String(normalized.dropFirst("bibitem:".count))
            aliases.insert("bibitem.\(key)")
            aliases.insert("#bibitem.\(key)")
            aliases.insert("bib.\(key)")
            aliases.insert("#bib.\(key)")
            aliases.insert("bib:\(key)")
            aliases.insert("#bib:\(key)")
            aliases.insert("bib-\(key)")
            aliases.insert("#bib-\(key)")
        }
        if normalized.hasPrefix("ref-") {
            let key = String(normalized.dropFirst("ref-".count))
            aliases.insert(key)
            aliases.insert("@\(key)")
            aliases.insert("ref:\(key)")
            aliases.insert("#ref:\(key)")
            aliases.insert("#ref-\(key)")
        } else if !normalized.contains(".") && !normalized.contains(":") && !normalized.hasPrefix("bibliography") {
            aliases.insert("ref-\(normalized)")
            aliases.insert("#ref-\(normalized)")
            aliases.insert("@\(normalized)")
        }
        return Array(aliases)
    }

    private static func aliases(for entry: ReaderCitationEntry) -> [String] {
        aliases(for: entry.id) + aliases(forLabel: entry.label)
    }

    private static func aliases(forLabel label: String) -> [String] {
        let normalized = normalizedLabel(label)
        guard !normalized.isEmpty else { return [] }
        return Array(Set([normalized, "[\(normalized)]"]))
    }

    private static func normalizedReference(_ reference: String) -> String {
        let trimmed = reference
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var fragment = trimmed
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .last
            .map(String.init) ?? trimmed
        fragment = fragment
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if fragment.hasPrefix("@") {
            fragment.removeFirst()
        }
        return fragment
    }

    private static func displayLabel(fromReference reference: String) -> String {
        let normalized = normalizedReference(reference)
        if normalized.hasPrefix("ref-") {
            return String(normalized.dropFirst("ref-".count))
        }
        return normalized
    }

    private static func normalizedLabel(_ label: String) -> String {
        var normalized = label
            .replacingOccurrences(of: #"\\["#, with: "[")
            .replacingOccurrences(of: #"\\]"#, with: "]")
            .replacingOccurrences(of: #"\["#, with: "[")
            .replacingOccurrences(of: #"\]"#, with: "]")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            normalized.removeFirst()
            normalized.removeLast()
        }
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inferredTitle(from rawText: String) -> String? {
        let segments = rawText
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { compactWhitespace(String($0)) }
            .filter { !$0.isEmpty }
        guard segments.count >= 2 else {
            return segments.first
        }
        return segments.dropFirst().first
    }

    private static func compactWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
