import Foundation

public enum WritingPatchInsertionMode: String, Codable, Hashable, Sendable {
    case sectionEnd
    case appendToEnd
}

public struct WritingPatchSectionAnchor: Codable, Hashable, Sendable {
    public var title: String
    public var level: Int
    public var startLine: Int
    public var endLine: Int
    public var kind: String

    public var anchorID: String {
        Self.anchorID(for: title)
    }

    public init(title: String, level: Int, startLine: Int, endLine: Int, kind: String) {
        self.title = title
        self.level = level
        self.startLine = startLine
        self.endLine = endLine
        self.kind = kind
    }

    public static func anchorID(for title: String) -> String {
        let filtered = title.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar)
            || CharacterSet.decimalDigits.contains(scalar)
            || scalar == " "
        }
        let collapsed = String(String.UnicodeScalarView(filtered))
            .split(whereSeparator: { $0 == " " })
            .joined(separator: "-")
        return collapsed
    }
}

public struct WritingPatchDraft: Codable, Hashable, Sendable {
    public var pendingPatch: PendingFilePatch
    public var sectionAnchor: WritingPatchSectionAnchor?
    public var insertionMode: WritingPatchInsertionMode
    public var insertionLine: Int?
    public var bibliographyFilePaths: [String]
    public var anchorFound: Bool

    public init(
        pendingPatch: PendingFilePatch,
        sectionAnchor: WritingPatchSectionAnchor?,
        insertionMode: WritingPatchInsertionMode,
        insertionLine: Int?,
        bibliographyFilePaths: [String],
        anchorFound: Bool
    ) {
        self.pendingPatch = pendingPatch
        self.sectionAnchor = sectionAnchor
        self.insertionMode = insertionMode
        self.insertionLine = insertionLine
        self.bibliographyFilePaths = bibliographyFilePaths
        self.anchorFound = anchorFound
    }
}

public struct WritingPatchPlanner: Sendable {
    public init() {}

    public func scanSections(in mainFileText: String, fileExtension: String) -> [WritingPatchSectionAnchor] {
        switch normalized(fileExtension: fileExtension) {
        case "typ":
            return parseTypstSections(mainFileText)
        case "tex":
            return parseTeXSections(mainFileText)
        default:
            return []
        }
    }

    public func detectBibliography(in mainFileText: String, fileExtension: String) -> [String] {
        switch normalized(fileExtension: fileExtension) {
        case "typ":
            return detectTypstBibliography(in: mainFileText)
        case "tex":
            return detectLaTeXBibliography(in: mainFileText)
        default:
            return []
        }
    }

    public func planInsertion(
        sourceBlock: String,
        targetSectionPreference: String,
        mainFileText: String,
        fileExtension: String,
        targetPath: String,
        patchId: String = UUID().uuidString,
        now: Date = Date()
    ) -> WritingPatchDraft {
        let sections = scanSections(in: mainFileText, fileExtension: fileExtension)
        let bibliographyPaths = detectBibliography(in: mainFileText, fileExtension: fileExtension)
        let normalizedPref = normalizedSectionTitle(targetSectionPreference)

        let selected = selectSection(preference: normalizedPref, from: sections)
        let insertionMode: WritingPatchInsertionMode = selected == nil ? .appendToEnd : .sectionEnd
        let insertionLine = selected?.endLine
        let patchText = makePatchText(
            from: sourceBlock,
            fileExtension: fileExtension
        )
        let kind: WritingProjectKind = normalized(fileExtension: fileExtension) == "typ" ? .typst : .tex
        let patchKind: PendingFilePatchKind = kind == .typst ? .typstInsertion : .texInsertion
        let patchFormat: PendingFilePatchFormat = kind == .typst ? .typst : .tex
        let sectionPath = selected.map { [$0.title] } ?? []
        let targetAnchor = selected?.anchorID

        let patch = PendingFilePatch(
            id: patchId,
            kind: patchKind,
            format: patchFormat,
            status: .previewReady,
            targetPath: targetPath,
            targetAnchor: targetAnchor,
            targetSectionPath: sectionPath,
            patchText: patchText,
            previewMarkdown: patchText,
            baseFileHash: nil,
            appliedFileHash: nil,
            conflict: nil,
            provenance: [],
            actionPlanId: nil,
            createdAt: now,
            updatedAt: now
        )

        return WritingPatchDraft(
            pendingPatch: patch,
            sectionAnchor: selected,
            insertionMode: insertionMode,
            insertionLine: insertionLine,
            bibliographyFilePaths: bibliographyPaths,
            anchorFound: selected != nil
        )
    }

    private func normalized(fileExtension: String) -> String {
        let lowered = fileExtension.lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if lowered.hasPrefix(".") { return String(lowered.dropFirst()) }
        return lowered
    }

    private func parseTypstSections(_ text: String) -> [WritingPatchSectionAnchor] {
        let lines = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" || $0 == "\r" }
        )
        var headings: [WritingPatchSectionAnchor] = []
        for (lineIndex, rawLine) in lines.enumerated() {
            if let heading = parseTypstHeading(String(rawLine), lineIndex: lineIndex) {
                headings.append(heading)
            }
        }
        return finalizeSections(headings, totalLines: max(lines.count - 1, 0), minimumLevel: 1)
    }

    private func parseTypstHeading(_ line: String, lineIndex: Int) -> WritingPatchSectionAnchor? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("//") else { return nil }

        var markerLength = 0
        for scalar in trimmed.unicodeScalars {
            if scalar == "=" {
                markerLength += 1
            } else {
                break
            }
        }
        guard markerLength > 0 else { return nil }
        guard trimmed.count > markerLength else { return nil }
        let remainder = trimmed.dropFirst(markerLength)
        guard let first = remainder.first, first == " " else { return nil }
        let title = remainder
            .dropFirst()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !title.isEmpty else { return nil }
        return WritingPatchSectionAnchor(
            title: String(title),
            level: markerLength,
            startLine: lineIndex,
            endLine: lineIndex,
            kind: "typst"
        )
    }

    private func parseTeXSections(_ text: String) -> [WritingPatchSectionAnchor] {
        let lines = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" || $0 == "\r" }
        )
        guard let regex = Self.latexHeadingRegex else {
            return []
        }
        var headings: [WritingPatchSectionAnchor] = []
        for (lineIndex, rawLine) in lines.enumerated() {
            let cleanLine = Self.stripLatexComments(from: String(rawLine))
            let range = NSRange(cleanLine.startIndex..<cleanLine.endIndex, in: cleanLine)
            guard let match = regex.firstMatch(in: cleanLine, range: range),
                  match.numberOfRanges >= 3,
                  let commandRange = Range(match.range(at: 1), in: cleanLine),
                  let titleRange = Range(match.range(at: 2), in: cleanLine)
            else {
                continue
            }
            let command = String(cleanLine[commandRange]).lowercased()
            let title = String(cleanLine[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let level = Self.latexHeadingLevel(for: command)
            headings.append(
                WritingPatchSectionAnchor(
                    title: title,
                    level: level,
                    startLine: lineIndex,
                    endLine: lineIndex,
                    kind: "tex"
                )
            )
        }
        return finalizeSections(headings, totalLines: max(lines.count - 1, 0), minimumLevel: 1)
    }

    private func finalizeSections(
        _ sections: [WritingPatchSectionAnchor],
        totalLines: Int,
        minimumLevel: Int
    ) -> [WritingPatchSectionAnchor] {
        guard !sections.isEmpty else { return [] }
        var finalized: [WritingPatchSectionAnchor] = []
        for index in sections.indices {
            let section = sections[index]
            let next = sections[(index + 1)...].first { candidate in
                candidate.level <= max(section.level, minimumLevel)
            }
            let boundary = next?.startLine ?? totalLines
            let endLine = max(section.startLine, boundary - 1)
            finalized.append(
                WritingPatchSectionAnchor(
                    title: section.title,
                    level: section.level,
                    startLine: section.startLine,
                    endLine: endLine,
                    kind: section.kind
                )
            )
        }
        return finalized
    }

    private func selectSection(
        preference: String,
        from sections: [WritingPatchSectionAnchor]
    ) -> WritingPatchSectionAnchor? {
        guard !sections.isEmpty else { return nil }
        let aliases = sectionAliases(for: preference)
        var scored: [(score: Int, section: WritingPatchSectionAnchor)] = []

        for section in sections {
            let normalizedTitle = normalizedSectionTitle(section.title)
            var score = 0
            if normalizedTitle == preference {
                score = 110
            } else if aliases.contains(normalizedTitle) {
                score = 100
            } else {
                for alias in aliases {
                    if normalizedTitle.contains(alias) || alias.contains(normalizedTitle) {
                        score = 90
                        break
                    }
                }
            }
            if score > 0 {
                scored.append((score: score, section: section))
            }
        }

        if !scored.isEmpty {
            scored.sort {
                if $0.score == $1.score {
                    return $0.section.startLine < $1.section.startLine
                }
                return $0.score > $1.score
            }
            return scored.first?.section
        }

        return nil
    }

    private func sectionAliases(for preference: String) -> Set<String> {
        let normalized = preference
        if normalized.isEmpty {
            return Set<String>()
        }
        switch normalized {
        case "related work", "related", "related works", "relatedwork":
            return Set(["related work", "background", "related works"])
        case "background":
            return Set(["background", "introduction"])
        case "method":
            return Set(["method", "methodology", "approach"])
        case "discussion":
            return Set(["discussion", "conclusion", "results"])
        default:
            return Set([normalized])
        }
    }

    private func makePatchText(from sourceBlock: String, fileExtension: String) -> String {
        let block = sourceBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !block.isEmpty else {
            return "# Insert content is empty."
        }
        let normalizedExtension = normalized(fileExtension: fileExtension)
        let writingBlock = convertMarkdownCitations(in: block, fileExtension: normalizedExtension)
        switch normalizedExtension {
        case "tex":
            return [
                "\\begin{quote}",
                writingBlock,
                "\\end{quote}"
            ].joined(separator: "\n")
        default:
            return [
                "#block[",
                "  \(writingBlock)",
                "]"
            ].joined(separator: "\n")
        }
    }

    private func convertMarkdownCitations(in text: String, fileExtension: String) -> String {
        guard fileExtension == "tex" || fileExtension == "typ",
              let regex = Self.markdownCitationRegex
        else {
            return text
        }

        let matches = regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let tokenRange = Range(match.range(at: 0), in: text),
                  let rawKeysRange = Range(match.range(at: 1), in: text)
            else {
                continue
            }
            let keys = citationKeys(fromMarkdownCitation: String(text[rawKeysRange]))
            guard !keys.isEmpty else { continue }
            result += text[cursor..<tokenRange.lowerBound]
            result += citationReplacement(keys: keys, fileExtension: fileExtension)
            cursor = tokenRange.upperBound
        }
        result += text[cursor..<text.endIndex]
        return result
    }

    private func citationKeys(fromMarkdownCitation raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == ";" || $0 == "," })
            .compactMap { component -> String? in
                let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("@") else { return nil }
                let key = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return nil }
                return String(key)
            }
    }

    private func citationReplacement(keys: [String], fileExtension: String) -> String {
        switch fileExtension {
        case "tex":
            return "\\cite{\(keys.joined(separator: ","))}"
        case "typ":
            return keys.map { "@\($0)" }.joined(separator: ", ")
        default:
            return keys.map { "@\($0)" }.joined(separator: "; ")
        }
    }

    private func detectTypstBibliography(in text: String) -> [String] {
        guard let commandRegex = Self.typstBibliographyRegex else { return [] }
        var bibs: [String] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = commandRegex.matches(in: text, options: [], range: range)
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let argsRange = Range(match.range(at: 1), in: text)
            if let argsRange {
                let args = String(text[argsRange])
                bibs.append(contentsOf: extractBibliographyPaths(from: args))
            }
        }
        return dedupePreservingOrder(bibs)
    }

    private func detectLaTeXBibliography(in text: String) -> [String] {
        let cleaned = text
        var bibs: [String] = []
        let lines = cleaned.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" || $0 == "\r" }
        )
        for rawLine in lines {
            let line = Self.stripLatexComments(from: String(rawLine))
            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            if let regex = Self.latexBibliographyRegex {
                let matches = regex.matches(in: line, options: [], range: range)
                for match in matches {
                    guard match.numberOfRanges >= 2,
                          let listRange = Range(match.range(at: 1), in: line)
                    else {
                        continue
                    }
                    let list = String(line[listRange])
                    bibs.append(contentsOf: extractLaTeXBibliographyList(list))
                }
            }

            if let regex = Self.latexAddBibResourceRegex {
                let matches = regex.matches(in: line, options: [], range: range)
                for match in matches {
                    guard match.numberOfRanges >= 2,
                          let listRange = Range(match.range(at: 1), in: line)
                    else {
                        continue
                    }
                    let list = String(line[listRange])
                    bibs.append(contentsOf: extractLaTeXBibliographyList(list))
                }
            }
        }
        return dedupePreservingOrder(bibs)
    }

    private func extractLaTeXBibliographyList(_ rawList: String) -> [String] {
        rawList
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { normalizeBibliographyPath($0) }
    }

    private func extractBibliographyPaths(from args: String) -> [String] {
        guard let quotedStringRegex = Self.quotedStringRegex else { return [] }
        let quoted = quotedStringRegex.matches(
            in: args,
            range: NSRange(args.startIndex..<args.endIndex, in: args)
        )
        return quoted.compactMap { match -> String? in
            guard match.numberOfRanges >= 3,
                  let argumentStart = Range(match.range(at: 0), in: args),
                  let valueRange = Range(match.range(at: 2), in: args)
            else {
                return nil
            }
            if isOptionArgument(startingAt: argumentStart.lowerBound, in: args) {
                return nil
            }
            return normalizeBibliographyPath(String(args[valueRange]))
        }
        .filter { value in
            let normalized = value.lowercased()
            return normalized.contains(".bib") || normalized.contains("/")
        }
    }

    private func isOptionArgument(startingAt index: String.Index, in text: String) -> Bool {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            if text[previous].isWhitespace {
                cursor = previous
                continue
            }
            return text[previous] == ":"
        }
        return false
    }

    private func normalizeBibliographyPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasSuffix(".bib") {
            return trimmed
        }
        return "\(trimmed).bib"
    }

    private func dedupePreservingOrder(_ values: [String]) -> [String] {
        var set: Set<String> = []
        return values.compactMap { value in
            guard !value.isEmpty else { return nil }
            if set.contains(value) { return nil }
            set.insert(value)
            return value
        }
    }

    private func normalizedSectionTitle(_ title: String) -> String {
        let compact = title.lowercased()
            .unicodeScalars
            .map { scalar in
                if scalar == " " {
                    return " "
                }
                if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                    return String(scalar)
                }
                return " "
            }
            .joined()
        let words = compact.split { $0 == " " }
        return words.joined(separator: " ")
    }

    private static let latexHeadingRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\\(part|chapter|section|subsection|subsubsection|paragraph|subparagraph)\*?\{([^{}]+)\}"#,
            options: []
        )
    }()

    private static let typstBibliographyRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"#bibliography\((.*?)\)"#,
            options: [.dotMatchesLineSeparators]
        )
    }()

    private static let quotedStringRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(\"|')([^\"']+)\1"#, options: [])
    }()

    private static let latexBibliographyRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\\bibliography\s*\{([^}]*)\}"#, options: [])
    }()

    private static let latexAddBibResourceRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\\addbibresource\s*\{([^}]*)\}"#, options: [])
    }()

    private static let markdownCitationRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\[((?:\s*@[A-Za-z0-9_:.:-]+\s*(?:[;,]\s*)?)+)\]"#,
            options: []
        )
    }()

    private static func stripLatexComments(from line: String) -> String {
        var result = ""
        var previousWasEscape = false
        for char in line {
            if char == "\\" && !previousWasEscape {
                previousWasEscape = true
                result.append(char)
                continue
            }
            if char == "%" && !previousWasEscape {
                break
            }
            previousWasEscape = false
            result.append(char)
        }
        return result
    }

    private static func latexHeadingLevel(for command: String) -> Int {
        switch command {
        case "part", "chapter":
            return 1
        case "section":
            return 2
        case "subsection":
            return 3
        case "subsubsection":
            return 4
        case "paragraph":
            return 5
        case "subparagraph":
            return 6
        default:
            return 7
        }
    }
}
