import SwiftUI
import AppKit
import CryptoKit
import BilinReaderKit
import BilinRenderKit

extension NSAttributedString.Key {
    static let bilinInlineMathLatex = NSAttributedString.Key("BilinInlineMathLatex")
    static let bilinInlineMathUnavailableReason = NSAttributedString.Key("BilinInlineMathUnavailableReason")
    static let bilinCitationReference = NSAttributedString.Key("BilinCitationReference")
    static let bilinCrossReference = NSAttributedString.Key("BilinCrossReference")
}

enum ReaderSemanticCopyFormatter {
    static func blockMarkdown(markdown: String) -> String {
        let key = markdown as NSString
        if let cached = blockMarkdownCache.object(forKey: key) {
            return cached.text
        }
        let rendered = renderedBlockMarkdown(markdown: markdown)
        blockMarkdownCache.setObject(Entry(text: rendered), forKey: key)
        return rendered
    }

    static func inlineMarkdown(markdown: String) -> String {
        let key = markdown as NSString
        if let cached = inlineMarkdownCache.object(forKey: key) {
            return cached.text
        }
        let rendered = ReaderInlineRunCache.runs(in: markdown)
            .map(markdownText(for:))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        inlineMarkdownCache.setObject(Entry(text: rendered), forKey: key)
        return rendered
    }

    static func removeAllForTesting() {
        blockMarkdownCache.removeAllObjects()
        inlineMarkdownCache.removeAllObjects()
    }

    static func hasCachedBlockMarkdown(for markdown: String) -> Bool {
        blockMarkdownCache.object(forKey: markdown as NSString) != nil
    }

    static func hasCachedInlineMarkdown(for markdown: String) -> Bool {
        inlineMarkdownCache.object(forKey: markdown as NSString) != nil
    }

    private final class Entry {
        let text: String

        init(text: String) {
            self.text = text
        }
    }

    private static let blockMarkdownCache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 2_048
        return cache
    }()

    private static let inlineMarkdownCache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 4_096
        return cache
    }()

    private static func renderedBlockMarkdown(markdown: String) -> String {
        let segments = ReaderMarkdownBlockSegmenter.segments(in: markdown)
        let rendered = segments
            .map { segment in
                switch segment.kind {
                case .markdown:
                    return inlineMarkdown(markdown: segment.text)
                case .displayMath:
                    return displayMathMarkdown(latex: segment.text)
                }
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return rendered.isEmpty
            ? inlineMarkdown(markdown: markdown).trimmingCharacters(in: .whitespacesAndNewlines)
            : rendered
    }

    static func inlineMathMarkdown(latex: String) -> String {
        "$\(latex)$"
    }

    static func displayMathMarkdown(latex: String) -> String {
        "$$\n\(latex)\n$$"
    }

    static func citationMarkdown(reference: String, displayText: String) -> String {
        let references = reference
            .split(separator: ",")
            .map { normalizedCitationReference(String($0)) }
            .filter { !$0.isEmpty }

        guard !references.isEmpty else { return displayText }
        if references.allSatisfy(isNumericCitationReference) {
            return displayText
        }

        return "[\(references.map { "@\($0)" }.joined(separator: "; "))]"
    }

    private static func markdownText(for run: ReaderInlineRun) -> String {
        switch run.kind {
        case .text:
            return run.text
        case .inlineMath:
            let latex = (run.payload ?? run.text).trimmingCharacters(in: .whitespacesAndNewlines)
            return latex.isEmpty ? run.text : inlineMathMarkdown(latex: latex)
        case .citation:
            guard let reference = run.payload else { return run.text }
            return citationMarkdown(reference: reference, displayText: run.text)
        case .crossReference:
            return run.text
        }
    }

    private static func normalizedCitationReference(_ reference: String) -> String {
        var normalized = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fragmentStart = normalized.lastIndex(of: "#") {
            normalized = String(normalized[normalized.index(after: fragmentStart)...])
        }
        if normalized.hasPrefix("@") {
            normalized.removeFirst()
        }
        normalized = writingCitationKey(from: normalized)
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writingCitationKey(from reference: String) -> String {
        let bibliographyPrefixes = [
            "bibitem.",
            "bibitem:",
            "bib.",
            "bib:",
            "bib-",
            "ref-",
            "ref:"
        ]
        for prefix in bibliographyPrefixes where reference.hasPrefix(prefix) {
            let key = String(reference.dropFirst(prefix.count))
            return key.isEmpty ? reference : key
        }
        return reference
    }

    private static func isNumericCitationReference(_ reference: String) -> Bool {
        !reference.isEmpty && reference.allSatisfy { character in
            character.isNumber || character.isWhitespace || character == "-" || character == "–"
        }
    }
}

enum ReaderInlineFontStyle {
    case title
    case heading
    case body
}

enum ReaderMathRenderOptions {
    static func options(
        fontSize: Double,
        colorScheme: ColorScheme,
        timeoutSeconds: Double
    ) -> RatexRenderOptions {
        RatexRenderOptions(
            fontSize: fontSize,
            foregroundColor: foregroundColor(for: colorScheme),
            timeoutSeconds: timeoutSeconds
        )
    }

    static func foregroundColor(for colorScheme: ColorScheme) -> String {
        switch colorScheme {
        case .dark:
            return "#f2f2f2"
        default:
            return "#111111"
        }
    }
}

enum ReaderAttributedTextSignature {
    static func make(
        markdown: String,
        font: ReaderInlineFontStyle,
        citationResolver: ReaderCitationResolver,
        bibliographyLines: [ReaderBibliographyLine],
        selectedCitationEntryId: String?,
        mathResults: [String: MathRenderResult]
    ) -> String {
        let canonical = [
            framed("markdown", textDigest(markdown)),
            framed("font", font.signatureToken),
            framed("citations", citationResolver.signature),
            framed("selectedCitation", bibliographyLines.isEmpty ? "" : selectedCitationEntryId ?? ""),
            framed("bibliography", bibliographySignature(for: bibliographyLines)),
            framed("math", mathResultsSignature(for: mathResults))
        ]
        .joined(separator: "\u{1d}")
        return "reader-attributed:v2:\(stableDigest(canonical))"
    }

    private static func bibliographySignature(for lines: [ReaderBibliographyLine]) -> String {
        lines
            .map { line in
                [
                    framed("lineID", line.id),
                    framed("source", textDigest(line.sourceLine)),
                    framed("entryID", line.entry?.id ?? ""),
                    framed("label", line.entry?.label ?? ""),
                    framed("title", textDigest(line.entry?.title ?? "")),
                    framed("raw", textDigest(line.entry?.rawText ?? ""))
                ]
                .joined(separator: "\u{1e}")
            }
            .joined(separator: "\u{1f}")
    }

    private static func mathResultsSignature(for results: [String: MathRenderResult]) -> String {
        results
            .map { latex, result in
                [
                    framed("latex", textDigest(latex)),
                    framed("payload", payloadSignature(for: result.payload))
                ]
                .joined(separator: "\u{1e}")
            }
            .sorted()
            .joined(separator: "\u{1f}")
    }

    private static func payloadSignature(for payload: MathRenderPayload) -> String {
        switch payload {
        case .plainText(let text):
            return "text:\(textDigest(text))"
        case .svg(let svg):
            return "svg:\(textDigest(svg))"
        case .unavailable(let reason):
            return "unavailable:\(textDigest(reason))"
        }
    }

    private static func framed(_ label: String, _ value: String) -> String {
        "\(label):\(value.utf8.count):\(value)"
    }

    private static func textDigest(_ value: String) -> String {
        "\(value.utf8.count):\(stableDigest(value))"
    }

    private static func stableDigest(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum ReaderAttributedStringCache {
    private final class Entry {
        let attributedString: NSAttributedString

        init(attributedString: NSAttributedString) {
            self.attributedString = attributedString
        }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 1_024
        return cache
    }()

    static func attributedString(for signature: String) -> NSAttributedString? {
        cache.object(forKey: signature as NSString)?.attributedString
    }

    static func store(_ attributedString: NSAttributedString, for signature: String) {
        cache.setObject(Entry(attributedString: attributedString), forKey: signature as NSString)
    }

    static func removeAllForTesting() {
        cache.removeAllObjects()
    }

    static func hasCachedAttributedString(for signature: String) -> Bool {
        cache.object(forKey: signature as NSString) != nil
    }
}

private extension ReaderInlineFontStyle {
    var signatureToken: String {
        switch self {
        case .title:
            return "title"
        case .heading:
            return "heading"
        case .body:
            return "body"
        }
    }
}

enum ReaderCitationLink {
    private static let prefix = "bilin://citation/"

    static func urlString(for reference: String) -> String {
        "\(prefix)\(reference)"
    }

    static func urlString(for entry: ReaderCitationEntry) -> String {
        urlString(for: entry.id)
    }

    static func reference(from link: Any) -> String? {
        let urlString: String?
        if let url = link as? URL {
            urlString = url.absoluteString
        } else {
            urlString = link as? String
        }
        guard let urlString, urlString.hasPrefix(prefix) else { return nil }
        let reference = String(urlString.dropFirst(prefix.count))
        return reference.isEmpty ? nil : reference
    }
}

struct SelectableInlineMarkupView: View {
    @Environment(\.colorScheme) private var colorScheme

    var markdown: String
    var font: ReaderInlineFontStyle
    var citationResolver: ReaderCitationResolver = .empty
    var bibliographyLines: [ReaderBibliographyLine] = []
    var selectedCitationEntryId: String?
    var onActivate: () -> Void = {}
    var onCitationClick: (ReaderCitationEntry) -> Void = { _ in }
    var onSelectionChange: (String?) -> Void = { _ in }

    @State private var mathResults: [String: MathRenderResult] = [:]
    @State private var mathResultsRenderOptions: RatexRenderOptions?

    private var runs: [ReaderInlineRun] {
        ReaderInlineRunCache.runs(in: markdown)
    }

    private var inlineMathLatexValues: [String] {
        ReaderInlineMathRenderQueue.latexValues(in: runs)
    }

    private var renderOptions: RatexRenderOptions {
        ReaderMathRenderOptions.options(
            fontSize: Double(baseFont.pointSize),
            colorScheme: colorScheme,
            timeoutSeconds: 4
        )
    }

    private var inlineMathRenderTaskSignature: String {
        ReaderInlineMathRenderQueue.taskSignature(
            latexValues: inlineMathLatexValues,
            renderOptions: renderOptions
        )
    }

    private var baseFont: NSFont {
        switch font {
        case .title:
            NSFont.systemFont(ofSize: 28, weight: .semibold)
        case .heading:
            NSFont.systemFont(ofSize: 22, weight: .semibold)
        case .body:
            NSFont.systemFont(ofSize: 16, weight: .regular)
        }
    }

    var body: some View {
        let signature = attributedContentSignature
        SelectableRichTextView(
            attributedString: attributedString(for: signature),
            contentSignature: signature,
            selectionStabilitySignature: selectionStabilitySignature,
            onActivate: onActivate,
            onCitationReferenceClick: { reference in
                guard let entry = citationResolver.resolve(reference) else { return }
                onCitationClick(entry)
            },
            onSelectionChange: onSelectionChange
        )
            .fixedSize(horizontal: false, vertical: true)
            .task(id: inlineMathRenderTaskSignature) {
                await renderInlineMathIfNeeded()
            }
    }

    func attributedStringForTesting() -> NSAttributedString {
        attributedString(for: attributedContentSignature)
    }

    private func attributedString(for signature: String) -> NSAttributedString {
        if let cached = ReaderAttributedStringCache.attributedString(for: signature) {
            return cached
        }
        let attributedString = makeAttributedString()
        ReaderAttributedStringCache.store(attributedString, for: signature)
        return attributedString
    }

    private func makeAttributedString() -> NSAttributedString {
        let output = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = font == .body ? 4 : 2
        paragraphStyle.paragraphSpacing = font == .body ? 4 : 2

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]

        if !bibliographyLines.isEmpty {
            appendBibliographyLines(
                bibliographyLines,
                to: output,
                baseAttributes: baseAttributes,
                paragraphStyle: paragraphStyle
            )
        } else {
            appendRuns(
                runs,
                to: output,
                baseAttributes: baseAttributes,
                paragraphStyle: paragraphStyle
            )
        }

        return output
    }

    private var attributedContentSignature: String {
        ReaderAttributedTextSignature.make(
            markdown: markdown,
            font: font,
            citationResolver: citationResolver,
            bibliographyLines: bibliographyLines,
            selectedCitationEntryId: selectedCitationEntryId,
            mathResults: resolvedMathResultsForDisplay()
        )
    }

    private var selectionStabilitySignature: String {
        ReaderAttributedTextSignature.make(
            markdown: markdown,
            font: font,
            citationResolver: citationResolver,
            bibliographyLines: bibliographyLines,
            selectedCitationEntryId: selectedCitationEntryId,
            mathResults: [:]
        )
    }

    private func appendBibliographyLines(
        _ lines: [ReaderBibliographyLine],
        to output: NSMutableAttributedString,
        baseAttributes: [NSAttributedString.Key: Any],
        paragraphStyle: NSParagraphStyle
    ) {
        for (index, line) in lines.enumerated() {
            let lineStart = output.length
            appendRuns(
                ReaderInlineRunCache.runs(in: line.sourceLine),
                to: output,
                baseAttributes: baseAttributes,
                paragraphStyle: paragraphStyle
            )
            if line.entry?.id == selectedCitationEntryId, output.length > lineStart {
                output.addAttribute(
                    .backgroundColor,
                    value: NSColor.controlAccentColor.withAlphaComponent(0.14),
                    range: NSRange(location: lineStart, length: output.length - lineStart)
                )
            }
            if index < lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
        }
    }

    private func appendRuns(
        _ runs: [ReaderInlineRun],
        to output: NSMutableAttributedString,
        baseAttributes: [NSAttributedString.Key: Any],
        paragraphStyle: NSParagraphStyle
    ) {
        for run in runs {
            switch run.kind {
            case .text:
                output.append(NSAttributedString(string: run.text, attributes: baseAttributes))
            case .citation:
                output.append(citationString(for: run, paragraphStyle: paragraphStyle))
            case .crossReference:
                output.append(crossReferenceString(for: run, paragraphStyle: paragraphStyle))
            case .inlineMath:
                output.append(inlineMathString(for: run, paragraphStyle: paragraphStyle))
            }
        }
    }

    private func citationString(
        for run: ReaderInlineRun,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let references = citationReferences(in: run)
        if references.count > 1 {
            return compoundCitationString(
                for: run,
                references: references,
                paragraphStyle: paragraphStyle
            )
        }

        let entry = citationResolver.resolve(run)
        let display = citationDisplayText(for: run, resolvedEntry: entry)
        let tooltip = entry.map(citationTooltip)
        let hasBibliographyTarget = entry?.hasBibliographyEntry == true
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium),
            .foregroundColor: hasBibliographyTarget ? NSColor.linkColor : NSColor.controlAccentColor,
            .paragraphStyle: paragraphStyle,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        if let reference = run.payload {
            attributes[.bilinCitationReference] = reference
        }
        if let entry {
            attributes[.link] = ReaderCitationLink.urlString(for: entry)
            if run.payload == nil {
                attributes[.bilinCitationReference] = entry.id
            }
        }
        if let tooltip, !tooltip.isEmpty {
            attributes[NSAttributedString.Key("NSToolTip")] = tooltip
        }
        return NSAttributedString(
            string: display,
            attributes: attributes
        )
    }

    private func compoundCitationString(
        for run: ReaderInlineRun,
        references: [String],
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let entries = references.map(citationResolver.resolve)
        let display = citationDisplayText(for: run, resolvedEntry: entries.compactMap { $0 }.first)
        let hasBibliographyTarget = entries.contains { $0?.hasBibliographyEntry == true }
        let semanticReference = entries
            .enumerated()
            .map { index, entry in entry?.id ?? references[index] }
            .joined(separator: ",")
        let output = NSMutableAttributedString(
            string: display,
            attributes: [
                .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium),
                .foregroundColor: hasBibliographyTarget ? NSColor.linkColor : NSColor.controlAccentColor,
                .paragraphStyle: paragraphStyle,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .bilinCitationReference: semanticReference
            ]
        )

        let targetRanges = citationTargetRanges(
            in: display,
            references: references,
            entries: entries
        )
        for target in targetRanges {
            guard let entry = target.entry else { continue }
            output.addAttributes(
                [
                    .link: ReaderCitationLink.urlString(for: entry),
                    NSAttributedString.Key("NSToolTip"): citationTooltip(for: entry)
                ],
                range: target.range
            )
        }
        return output
    }

    private func citationDisplayText(
        for run: ReaderInlineRun,
        resolvedEntry entry: ReaderCitationEntry?
    ) -> String {
        if isCompoundCitation(run), !run.text.isEmpty {
            return run.text
        }
        return entry?.displayLabel ?? (run.text.isEmpty ? "[citation]" : run.text)
    }

    private func isCompoundCitation(_ run: ReaderInlineRun) -> Bool {
        guard let payload = run.payload else { return false }
        return payload.split(separator: ",").count > 1
    }

    private func citationReferences(in run: ReaderInlineRun) -> [String] {
        guard let payload = run.payload else { return [] }
        return payload
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private struct CitationTargetRange {
        var reference: String
        var entry: ReaderCitationEntry?
        var range: NSRange
    }

    private func citationTargetRanges(
        in display: String,
        references: [String],
        entries: [ReaderCitationEntry?]
    ) -> [CitationTargetRange] {
        let matchedRanges = matchedCitationTargetRanges(
            in: display,
            references: references,
            entries: entries
        )
        if matchedRanges.count == references.count {
            return matchedRanges
        }

        let componentRanges = citationDisplayComponentRanges(in: display)
        guard componentRanges.count == references.count else {
            return []
        }
        return references.indices.map { index in
            CitationTargetRange(
                reference: references[index],
                entry: entries[index],
                range: NSRange(componentRanges[index], in: display)
            )
        }
    }

    private func matchedCitationTargetRanges(
        in display: String,
        references: [String],
        entries: [ReaderCitationEntry?]
    ) -> [CitationTargetRange] {
        var output: [CitationTargetRange] = []
        var searchStart = display.startIndex

        for index in references.indices {
            let candidates = citationDisplayCandidates(
                reference: references[index],
                entry: entries[index]
            )
            guard let match = candidates.lazy.compactMap({ candidate -> Range<String.Index>? in
                display.range(of: candidate, options: [], range: searchStart..<display.endIndex)
            }).first else {
                return []
            }
            output.append(
                CitationTargetRange(
                    reference: references[index],
                    entry: entries[index],
                    range: NSRange(match, in: display)
                )
            )
            searchStart = match.upperBound
        }

        return output
    }

    private func citationDisplayCandidates(
        reference: String,
        entry: ReaderCitationEntry?
    ) -> [String] {
        let rawCandidates = [
            entry?.label,
            entry?.displayLabel,
            entry?.displayLabel.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
            reference,
            reference.split(separator: "#").last.map(String.init),
            reference.split(separator: ".").last.map(String.init),
            reference.split(separator: ":").last.map(String.init)
        ]
        var seen: Set<String> = []
        return rawCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    private func citationDisplayComponentRanges(in display: String) -> [Range<String.Index>] {
        let coreRange = citationDisplayCoreRange(in: display)
        var ranges: [Range<String.Index>] = []
        var componentStart = coreRange.lowerBound
        var cursor = coreRange.lowerBound

        while cursor < coreRange.upperBound {
            let character = display[cursor]
            if character == "," || character == ";" {
                if let trimmed = trimmedRange(componentStart..<cursor, in: display) {
                    ranges.append(trimmed)
                }
                componentStart = display.index(after: cursor)
            }
            cursor = display.index(after: cursor)
        }
        if let trimmed = trimmedRange(componentStart..<coreRange.upperBound, in: display) {
            ranges.append(trimmed)
        }
        return ranges
    }

    private func citationDisplayCoreRange(in display: String) -> Range<String.Index> {
        guard display.count >= 2,
              let first = display.first,
              let last = display.last,
              (first == "[" && last == "]") || (first == "(" && last == ")")
        else {
            return display.startIndex..<display.endIndex
        }
        return display.index(after: display.startIndex)..<display.index(before: display.endIndex)
    }

    private func trimmedRange(
        _ range: Range<String.Index>,
        in display: String
    ) -> Range<String.Index>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, display[lower].isWhitespace {
            lower = display.index(after: lower)
        }
        while lower < upper {
            let previous = display.index(before: upper)
            guard display[previous].isWhitespace else { break }
            upper = previous
        }
        return lower < upper ? lower..<upper : nil
    }

    private func citationTooltip(for entry: ReaderCitationEntry) -> String {
        let details = [entry.displayLabel, entry.title, entry.rawText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        if details.count > 1 {
            return details.joined(separator: "\n")
        }
        return "\(entry.displayLabel)\nBibliography entry not available in this library."
    }

    private func crossReferenceString(
        for run: ReaderInlineRun,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let display = run.text.isEmpty ? run.payload ?? "" : run.text
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .regular),
            .foregroundColor: NSColor.linkColor,
            .paragraphStyle: paragraphStyle,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        if let payload = run.payload, !payload.isEmpty {
            attributes[.bilinCrossReference] = payload
            attributes[NSAttributedString.Key("NSToolTip")] = payload
        }
        return NSAttributedString(
            string: display,
            attributes: attributes
        )
    }

    private func inlineMathString(
        for run: ReaderInlineRun,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let latex = (run.payload ?? run.text).trimmingCharacters(in: .whitespacesAndNewlines)
        let renderResult = mathRenderResult(for: latex)
        if let attachment = mathAttachment(for: latex) {
            let attributed = NSMutableAttributedString(attachment: attachment)
            attributed.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: 0, length: attributed.length)
            )
            attributed.addAttribute(
                .bilinInlineMathLatex,
                value: latex,
                range: NSRange(location: 0, length: attributed.length)
            )
            return attributed
        }

        if case .unavailable(let reason) = renderResult?.payload {
            return inlineMathFallbackString(
                latex: latex,
                paragraphStyle: paragraphStyle,
                unavailableReason: reason
            )
        }

        return inlineMathFallbackString(
            latex: latex,
            paragraphStyle: paragraphStyle,
            unavailableReason: nil
        )
    }

    private func inlineMathFallbackString(
        latex: String,
        paragraphStyle: NSParagraphStyle,
        unavailableReason: String?
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle,
            .bilinInlineMathLatex: latex
        ]
        if let unavailableReason {
            attributes[.foregroundColor] = NSColor.labelColor
            attributes[.backgroundColor] = NSColor.systemOrange.withAlphaComponent(0.12)
            attributes[.underlineColor] = NSColor.systemOrange
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
            attributes[.bilinInlineMathUnavailableReason] = unavailableReason
            attributes[NSAttributedString.Key("NSToolTip")] = "RaTeX unavailable: \(unavailableReason)"
        }
        return NSAttributedString(
            string: "$\(latex)$",
            attributes: attributes
        )
    }

    private func resolvedMathResultsForDisplay() -> [String: MathRenderResult] {
        let latexValues = inlineMathLatexValues
        var resolved = ReaderInlineMathRenderQueue.currentMathResults(
            mathResults,
            latexValues: latexValues
        )
        for latex in ReaderInlineMathRenderQueue.pendingLatexValues(
            latexValues: latexValues,
            renderedLatex: Set(resolved.keys)
        ) {
            guard let cached = cachedResidentInlineMathResult(for: latex) else { continue }
            resolved[latex] = cached
        }
        return resolved
    }

    private func mathRenderResult(for latex: String) -> MathRenderResult? {
        mathResults[latex] ?? cachedResidentInlineMathResult(for: latex)
    }

    private func cachedResidentInlineMathResult(for latex: String) -> MathRenderResult? {
        guard !latex.isEmpty else { return nil }
        return RatexRenderCacheStore.shared.cachedResidentResult(
            for: RatexRenderCacheKey(
                latex: latex,
                layoutMode: .inline,
                options: renderOptions
            )
        )
    }

    private func mathAttachment(for latex: String) -> NSTextAttachment? {
        guard case .svg(let svg) = mathRenderResult(for: latex)?.payload,
              let attachment = InlineMathAttachmentFactory.cachedAttachment(
                svg: svg,
                latex: latex,
                baseFont: baseFont
              )
        else {
            return nil
        }
        return attachment
    }

    @MainActor
    private func renderInlineMathIfNeeded() async {
        let activeRenderOptions = renderOptions
        if mathResultsRenderOptions != activeRenderOptions {
            mathResults = [:]
            mathResultsRenderOptions = activeRenderOptions
        }
        let currentLatexValues = inlineMathLatexValues
        let currentMathResults = ReaderInlineMathRenderQueue.currentMathResults(
            mathResults,
            latexValues: currentLatexValues
        )
        if currentMathResults.count != mathResults.count {
            mathResults = currentMathResults
        }
        let latexValues = ReaderInlineMathRenderQueue.pendingLatexValues(
            latexValues: currentLatexValues,
            renderedLatex: Set(mathResults.keys)
        )
        guard !latexValues.isEmpty else { return }

        let renderKeysByLatex = Dictionary(
            uniqueKeysWithValues: latexValues.map { latex in
                (
                    latex,
                    RatexRenderCacheKey(
                        latex: latex,
                        layoutMode: .inline,
                        options: activeRenderOptions
                    )
                )
            }
        )
        let persistedResults = await RatexRenderCacheStore.shared.cachedPersistedResults(
            for: Array(renderKeysByLatex.values),
            priority: .utility
        )
        guard !Task.isCancelled else { return }

        var cachedResults: [String: MathRenderResult] = [:]
        for latex in latexValues where mathResults[latex] == nil {
            guard let key = renderKeysByLatex[latex],
                  let persistedResult = persistedResults[key]
            else {
                continue
            }
            if case .svg(let svg) = persistedResult.payload {
                _ = await InlineMathAttachmentFactory.preheat(svg: svg, baseFont: baseFont)
            }
            guard !Task.isCancelled else { return }
            cachedResults[latex] = persistedResult
        }
        if !cachedResults.isEmpty {
            mathResults.merge(cachedResults) { _, new in new }
        }

        var pendingResults: [String: MathRenderResult] = [:]
        pendingResults.reserveCapacity(min(latexValues.count, ReaderInlineMathRenderQueue.stateCommitBatchSize))

        for latex in latexValues where mathResults[latex] == nil {
            guard !Task.isCancelled else { return }
            let key = renderKeysByLatex[latex] ?? RatexRenderCacheKey(
                latex: latex,
                layoutMode: .inline,
                options: activeRenderOptions
            )
            let rendered = await RatexRenderCacheStore.shared.result(
                for: key,
                priority: .utility,
                isCancelled: { Task.isCancelled },
                cancelledResult: {
                    FallbackMathRenderer().renderInline(latex: latex)
                },
                render: {
                    RatexMathRenderer(options: activeRenderOptions).renderInline(latex: latex)
                }
            )
            guard !Task.isCancelled else { return }
            if case .svg(let svg) = rendered.payload {
                _ = await InlineMathAttachmentFactory.preheat(svg: svg, baseFont: baseFont)
            }
            guard !Task.isCancelled else { return }
            pendingResults[latex] = rendered

            if ReaderInlineMathRenderQueue.shouldCommitRenderedBatch(
                count: pendingResults.count,
                isLast: false
            ) {
                mathResults.merge(pendingResults) { _, new in new }
                pendingResults.removeAll(keepingCapacity: true)
            }
        }
        if ReaderInlineMathRenderQueue.shouldCommitRenderedBatch(
            count: pendingResults.count,
            isLast: true
        ) {
            mathResults.merge(pendingResults) { _, new in new }
        }
    }
}

enum ReaderInlineMathRenderQueue {
    static let stateCommitBatchSize = 8

    static func latexValues(in runs: [ReaderInlineRun]) -> [String] {
        Array(
            Set(
                runs
                    .filter { $0.kind == .inlineMath }
                    .map { ($0.payload ?? $0.text).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }

    static func pendingLatexValues(
        in runs: [ReaderInlineRun],
        renderedLatex: Set<String>
    ) -> [String] {
        pendingLatexValues(
            latexValues: latexValues(in: runs),
            renderedLatex: renderedLatex
        )
    }

    static func pendingLatexValues(
        latexValues: [String],
        renderedLatex: Set<String>
    ) -> [String] {
        latexValues.filter { !renderedLatex.contains($0) }
    }

    static func currentMathResults(
        _ mathResults: [String: MathRenderResult],
        latexValues: [String]
    ) -> [String: MathRenderResult] {
        let currentLatex = Set(latexValues)
        return mathResults.filter { currentLatex.contains($0.key) }
    }

    static func taskSignature(
        latexValues: [String],
        renderOptions: RatexRenderOptions
    ) -> String {
        [
            latexValues.joined(separator: "\u{1e}"),
            String(renderOptions.fontSize),
            renderOptions.foregroundColor,
            String(renderOptions.timeoutSeconds)
        ].joined(separator: "\u{1d}")
    }

    static func shouldCommitRenderedBatch(count: Int, isLast: Bool) -> Bool {
        count >= stateCommitBatchSize || (isLast && count > 0)
    }
}

enum ReaderInlineRunCache {
    private final class Entry {
        let runs: [ReaderInlineRun]

        init(runs: [ReaderInlineRun]) {
            self.runs = runs
        }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 2_048
        return cache
    }()

    static func runs(in markdown: String) -> [ReaderInlineRun] {
        let key = markdown as NSString
        if let cached = cache.object(forKey: key) {
            return cached.runs
        }
        let runs = ReaderInlineMarkupParser.runs(in: markdown)
        cache.setObject(Entry(runs: runs), forKey: key)
        return runs
    }

    static func removeAllForTesting() {
        cache.removeAllObjects()
    }

    static func hasCachedRuns(for markdown: String) -> Bool {
        cache.object(forKey: markdown as NSString) != nil
    }
}

enum InlineMathAttachmentFactory {
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 1_024
        return cache
    }()

    @MainActor
    static func cachedAttachment(
        svg: String,
        latex: String,
        baseFont: NSFont
    ) -> NSTextAttachment? {
        guard let sourceImage = RatexSVGImageCache.cachedOrDecodedImage(from: svg),
              sourceImage.size.width > 0,
              sourceImage.size.height > 0
        else {
            return nil
        }

        let targetSize = fittingSize(for: sourceImage.size, baseFont: baseFont)
        let cacheKey = RatexSVGImageCache.key(
            for: svg,
            variant: "inline-\(Int(baseFont.pointSize * 10))-\(Int(targetSize.width * 10))x\(Int(targetSize.height * 10))"
        )
        let renderedImage: NSImage
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            renderedImage = cachedImage
        } else {
            guard let generatedImage = rasterizedImage(from: sourceImage, targetSize: targetSize)
                ?? sourceImage.copy() as? NSImage
            else {
                return nil
            }
            generatedImage.size = targetSize
            imageCache.setObject(generatedImage, forKey: cacheKey)
            renderedImage = generatedImage
        }

        return attachment(from: renderedImage, targetSize: targetSize, baseFont: baseFont)
    }

    @MainActor
    static func preheat(svg: String, baseFont: NSFont) async -> Bool {
        let fontMetrics = InlineMathFontMetrics(
            pointSize: baseFont.pointSize,
            capHeight: baseFont.capHeight
        )
        guard let sourceImage = await RatexSVGImageCache.image(from: svg),
              sourceImage.size.width > 0,
              sourceImage.size.height > 0
        else {
            return false
        }

        let targetSize = fittingSize(for: sourceImage.size, fontMetrics: fontMetrics)
        let cacheKey = RatexSVGImageCache.key(
            for: svg,
            variant: cacheVariant(for: fontMetrics, targetSize: targetSize)
        )
        if imageCache.object(forKey: cacheKey) != nil {
            return false
        }
        let renderedImage = rasterizedImage(from: sourceImage, targetSize: targetSize)
            ?? sourceImage.copy() as? NSImage
            ?? sourceImage
        renderedImage.size = targetSize
        imageCache.setObject(renderedImage, forKey: cacheKey)
        return true
    }

    static func removeAllImagesForTesting() {
        imageCache.removeAllObjects()
    }

    @MainActor
    static var rasterizationThreadCheckForTesting: (() -> Void)?

    @MainActor
    private static func attachment(
        from renderedImage: NSImage,
        targetSize: NSSize,
        baseFont: NSFont
    ) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.image = renderedImage
        attachment.bounds = CGRect(
            x: 0,
            y: (baseFont.capHeight - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        return attachment
    }

    private static func fittingSize(for sourceSize: NSSize, baseFont: NSFont) -> NSSize {
        fittingSize(
            for: sourceSize,
            fontMetrics: InlineMathFontMetrics(
                pointSize: baseFont.pointSize,
                capHeight: baseFont.capHeight
            )
        )
    }

    private static func fittingSize(for sourceSize: NSSize, fontMetrics: InlineMathFontMetrics) -> NSSize {
        let maximumHeight = fontMetrics.pointSize * 1.75
        let minimumHeight = fontMetrics.pointSize * 0.9
        let targetHeight = min(maximumHeight, max(minimumHeight, sourceSize.height))
        let scale = targetHeight / sourceSize.height
        return NSSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, targetHeight)
        )
    }

    private static func cacheVariant(for fontMetrics: InlineMathFontMetrics, targetSize: NSSize) -> String {
        "inline-\(Int(fontMetrics.pointSize * 10))-\(Int(targetSize.width * 10))x\(Int(targetSize.height * 10))"
    }

    @MainActor
    private static func rasterizedImage(from sourceImage: NSImage, targetSize: NSSize) -> NSImage? {
        rasterizationThreadCheckForTesting?()
        let rasterImage = NSImage(size: targetSize)
        rasterImage.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        sourceImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceImage.size),
            operation: .sourceOver,
            fraction: 1
        )
        rasterImage.unlockFocus()
        return rasterImage
    }
}

private struct InlineMathFontMetrics: Sendable {
    var pointSize: CGFloat
    var capHeight: CGFloat
}

enum SelectableRichTextUpdatePolicy {
    static func shouldDeferUpdate(
        selectedText: String,
        currentSelectionStabilitySignature: String,
        nextSelectionStabilitySignature: String
    ) -> Bool {
        !selectedText.isEmpty
            && currentSelectionStabilitySignature == nextSelectionStabilitySignature
    }
}

private struct SelectableRichTextView: NSViewRepresentable {
    var attributedString: NSAttributedString
    var contentSignature: String
    var selectionStabilitySignature: String
    var onActivate: () -> Void
    var onCitationReferenceClick: (String) -> Void
    var onSelectionChange: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            attributedString: attributedString,
            contentSignature: contentSignature,
            selectionStabilitySignature: selectionStabilitySignature,
            onActivate: onActivate,
            onCitationReferenceClick: onCitationReferenceClick,
            onSelectionChange: onSelectionChange
        )
    }

    func makeNSView(context: Context) -> IntrinsicTextView {
        let textView = IntrinsicTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.allowsUndo = false
        textView.usesFindPanel = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.onActivate = onActivate
        textView.textStorage?.setAttributedString(attributedString)
        textView.invalidateMeasuredContentSize()
        textView.delegate = context.coordinator
        context.coordinator.lastAttributedString = attributedString
        context.coordinator.lastContentSignature = contentSignature
        context.coordinator.lastSelectionStabilitySignature = selectionStabilitySignature
        return textView
    }

    func updateNSView(_ textView: IntrinsicTextView, context: Context) {
        textView.onActivate = onActivate
        context.coordinator.onActivate = onActivate
        context.coordinator.onCitationReferenceClick = onCitationReferenceClick
        context.coordinator.onSelectionChange = onSelectionChange
        guard context.coordinator.lastContentSignature != contentSignature else {
            return
        }
        guard !SelectableRichTextUpdatePolicy.shouldDeferUpdate(
            selectedText: textView.copyableSelectedText(),
            currentSelectionStabilitySignature: context.coordinator.lastSelectionStabilitySignature,
            nextSelectionStabilitySignature: selectionStabilitySignature
        ) else {
            return
        }
        let selectedRanges = textView.selectedRanges
        textView.textStorage?.setAttributedString(attributedString)
        textView.invalidateMeasuredContentSize()
        textView.setSelectedRanges(
            Self.validSelectedRanges(selectedRanges, length: attributedString.length),
            affinity: .downstream,
            stillSelecting: false
        )
        textView.invalidateIntrinsicContentSize()
        context.coordinator.lastAttributedString = attributedString
        context.coordinator.lastContentSignature = contentSignature
        context.coordinator.lastSelectionStabilitySignature = selectionStabilitySignature
    }

    private static func validSelectedRanges(_ ranges: [NSValue], length: Int) -> [NSValue] {
        ranges.compactMap { value in
            let range = value.rangeValue
            guard range.location != NSNotFound, NSMaxRange(range) <= length else {
                return nil
            }
            return value
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var lastAttributedString: NSAttributedString
        var lastContentSignature: String
        var lastSelectionStabilitySignature: String
        var onActivate: () -> Void
        var onCitationReferenceClick: (String) -> Void
        var onSelectionChange: (String?) -> Void
        var suppressNextEmptySelectionChange = false

        init(
            attributedString: NSAttributedString,
            contentSignature: String,
            selectionStabilitySignature: String,
            onActivate: @escaping () -> Void,
            onCitationReferenceClick: @escaping (String) -> Void,
            onSelectionChange: @escaping (String?) -> Void
        ) {
            self.lastAttributedString = attributedString
            self.lastContentSignature = contentSignature
            self.lastSelectionStabilitySignature = selectionStabilitySignature
            self.onActivate = onActivate
            self.onCitationReferenceClick = onCitationReferenceClick
            self.onSelectionChange = onSelectionChange
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let reference = ReaderCitationLink.reference(from: link) else {
                return false
            }
            suppressNextEmptySelectionChange = true
            (textView as? IntrinsicTextView)?.suppressActivationForCurrentMouseDown()
            onCitationReferenceClick(reference)
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? IntrinsicTextView else {
                return
            }
            let selectedText = textView.copyableSelectedText()
            if suppressNextEmptySelectionChange, selectedText.isEmpty {
                suppressNextEmptySelectionChange = false
                return
            }
            suppressNextEmptySelectionChange = false
            onSelectionChange(selectedText.isEmpty ? nil : selectedText)
        }
    }
}

final class IntrinsicTextView: NSTextView {
    var onActivate: () -> Void = {}
    private var suppressCurrentMouseActivation = false
    private var measuredWidth: CGFloat = -1
    private var measuredHeight: CGFloat = 24
    private var measuredContentSizeIsDirty = true

    override func mouseDown(with event: NSEvent) {
        suppressCurrentMouseActivation = false
        super.mouseDown(with: event)
        if shouldActivateAfterMouseDown() {
            onActivate()
        }
        suppressCurrentMouseActivation = false
    }

    func suppressActivationForCurrentMouseDown() {
        suppressCurrentMouseActivation = true
    }

    func setAttributedStringForTesting(_ attributedString: NSAttributedString) {
        textStorage?.setAttributedString(attributedString)
    }

    func shouldActivateAfterMouseDown() -> Bool {
        !suppressCurrentMouseActivation && copyableSelectedText().isEmpty
    }

    func invalidateMeasuredContentSize() {
        measuredContentSizeIsDirty = true
        invalidateIntrinsicContentSize()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        readerSelectionContextMenu() ?? super.menu(for: event)
    }

    func readerSelectionContextMenu() -> NSMenu? {
        guard !copyableSelectedText().isEmpty else { return nil }
        let menu = NSMenu()
        let copyItem = NSMenuItem(
            title: "Copy",
            action: #selector(copy(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)
        return menu
    }

    override func copy(_ sender: Any?) {
        guard copySelection(to: .general) else {
            super.copy(sender)
            return
        }
    }

    @discardableResult
    func copySelection(to pasteboard: NSPasteboard) -> Bool {
        let copiedText = copyableSelectedText()
        guard !copiedText.isEmpty else { return false }
        pasteboard.clearContents()
        pasteboard.setString(copiedText, forType: .string)
        return true
    }

    func copyableSelectedText() -> String {
        selectedRanges
            .map(\.rangeValue)
            .filter { $0.length > 0 }
            .map(copyableString(in:))
            .joined(separator: "\n")
    }

    private func copyableString(in range: NSRange) -> String {
        guard let textStorage else { return "" }
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
        guard safeRange.length > 0 else { return "" }

        let selected = textStorage.attributedSubstring(from: safeRange)
        let fullRange = NSRange(location: 0, length: selected.length)
        var output = ""
        var cursor = 0
        while cursor < selected.length {
            var effectiveRange = NSRange(location: cursor, length: 1)
            if let latex = selected.attribute(
                .bilinInlineMathLatex,
                at: cursor,
                longestEffectiveRange: &effectiveRange,
                in: fullRange
            ) as? String {
                output += ReaderSemanticCopyFormatter.inlineMathMarkdown(latex: latex)
            } else if let reference = selected.attribute(
                .bilinCitationReference,
                at: cursor,
                longestEffectiveRange: &effectiveRange,
                in: fullRange
            ) as? String {
                let displayText = selected
                    .attributedSubstring(from: effectiveRange)
                    .string
                output += ReaderSemanticCopyFormatter.citationMarkdown(
                    reference: reference,
                    displayText: displayText
                )
            } else {
                _ = selected.attributes(at: cursor, effectiveRange: &effectiveRange)
                output += selected
                    .attributedSubstring(from: effectiveRange)
                    .string
                    .replacingOccurrences(of: "\u{fffc}", with: "")
            }
            cursor = NSMaxRange(effectiveRange)
        }
        return output
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 24)
        }

        let width = bounds.width > 0 ? bounds.width : 1
        if !measuredContentSizeIsDirty, abs(width - measuredWidth) < 0.5 {
            return NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight)
        }

        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        measuredWidth = width
        measuredHeight = ceil(usedRect.height + textContainerInset.height * 2)
        measuredContentSizeIsDirty = false
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: measuredHeight
        )
    }

    override func layout() {
        super.layout()
        let width = bounds.width > 0 ? bounds.width : 1
        guard abs(width - measuredWidth) >= 0.5 else { return }
        invalidateMeasuredContentSize()
    }
}
