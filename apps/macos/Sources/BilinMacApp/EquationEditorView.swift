import SwiftUI
import AppKit
import BilinRenderKit

struct EquationEditorView: View {
    @StateObject private var model: EquationEditorModel
    @Environment(\.dismiss) private var dismiss

    init(initialLatex: String? = nil) {
        _model = StateObject(wrappedValue: EquationEditorModel(initialLatex: initialLatex))
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = EquationEditorLayout(width: geometry.size.width)

            VStack(spacing: 0) {
                EquationEditorToolbar(model: model) {
                    dismiss()
                }

                Divider()

                HStack(spacing: 0) {
                    EquationTemplatePane(model: model)
                        .frame(width: layout.templatePaneWidth)

                    Divider()

                    EquationEditorCenterPane(model: model, showsInlineOptions: !layout.showsOptionsPane)
                        .frame(minWidth: layout.centerMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)

                    if layout.showsOptionsPane {
                        Divider()

                        EquationOptionsPane(model: model)
                            .frame(width: layout.optionsPaneWidth)
                    }
                }
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: model.latex) { _, _ in
            model.refreshPreview()
        }
        .onChange(of: model.options) { _, _ in
            model.refreshPreview()
        }
        .onChange(of: model.selectedGroupID) { _, _ in
            model.refreshTemplatePreviews()
        }
        .onDisappear {
            model.cancelPreview()
        }
    }
}

private struct EquationEditorLayout {
    var width: CGFloat

    var showsOptionsPane: Bool {
        width >= 960
    }

    var templatePaneWidth: CGFloat {
        if width >= 1180 {
            return 288
        }
        return width >= 960 ? 256 : 236
    }

    var optionsPaneWidth: CGFloat {
        width >= 1180 ? 248 : 224
    }

    var centerMinimumWidth: CGFloat {
        420
    }
}

enum EquationTemplatePreviewPolicy {
    static func prefersTypographicFallback(_ template: EquationTemplate) -> Bool {
        guard template.fallbackPreviewText != nil else {
            return false
        }
        return template.id.hasPrefix("pmatrix")
            || template.id.hasPrefix("bmatrix")
            || template.id == "cases"
            || template.id == "aligned"
            || template.renderedPreviewLatex == template.latex
    }

    static func shouldRenderPreview(_ template: EquationTemplate) -> Bool {
        !prefersTypographicFallback(template)
    }
}

enum EquationTemplateRenderQueue {
    static let stateCommitBatchSize = 8

    static func shouldCommitRenderedBatch(count: Int, remainingCount: Int) -> Bool {
        count >= stateCommitBatchSize || (remainingCount == 0 && count > 0)
    }
}

enum EquationPreviewPublicationPolicy {
    static func shouldPublishResult(current: MathRenderResult, next: MathRenderResult) -> Bool {
        current != next
    }

    static func shouldPublishRenderingFlag(current: Bool, next: Bool) -> Bool {
        current != next
    }
}

enum EquationLatexEditorUpdatePolicy {
    static func shouldPublishText(current: String, next: String) -> Bool {
        current != next
    }

    static func shouldPublishSelection(current: EquationTextSelection, next: EquationTextSelection) -> Bool {
        current != next
    }
}

private struct EquationEditorToolbar: View {
    @ObservedObject var model: EquationEditorModel
    var close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label("RaTeX Equation Editor", systemImage: "function")
                .font(.headline)
            Spacer(minLength: 16)
            ViewThatFits(in: .horizontal) {
                toolbarActionsWithTitles
                toolbarIconActions
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbarActionsWithTitles: some View {
        toolbarActions
            .labelStyle(.titleAndIcon)
    }

    private var toolbarIconActions: some View {
        toolbarActions
            .labelStyle(.iconOnly)
    }

    private var toolbarActions: some View {
        HStack(spacing: 8) {
            Button {
                model.copyLatex()
            } label: {
                Label("Copy LaTeX", systemImage: "doc.on.doc")
            }
            .help("Copy LaTeX")

            Button {
                model.copySVG()
            } label: {
                Label("Copy SVG", systemImage: "photo.on.rectangle")
            }
            .disabled(!model.hasRenderedSVG)
            .help("Copy SVG")

            Button {
                model.saveSVG()
            } label: {
                Label("Save SVG", systemImage: "arrow.down.doc")
            }
            .disabled(!model.hasRenderedSVG)
            .help("Save SVG")

            Button {
                close()
            } label: {
                Label("Close", systemImage: "xmark")
            }
            .help("Close")
        }
    }
}

@MainActor
private final class EquationEditorModel: ObservableObject {
    @Published var latex: String
    @Published var latexSelection = EquationTextSelection()
    @Published var options: EquationEditorOptions
    @Published var selectedGroupID = EquationTemplateCatalog.groups.first?.id ?? "structure"
    @Published private(set) var renderResult: MathRenderResult
    @Published private(set) var isRenderingPreview = false
    @Published private(set) var templateRenderResults: [String: MathRenderResult] = [:]
    private var previewTask: Task<Void, Never>?
    private var templatePreviewTask: Task<Void, Never>?
    private var previewRevision = 0
    private var templatePreviewRevision = 0
    private var previewCancellationToken = RatexRenderCancellationToken()
    private var templatePreviewCancellationToken = RatexRenderCancellationToken()
    private let renderCache: RatexRenderCacheStore

    init(
        initialLatex: String? = nil,
        renderCache: RatexRenderCacheStore? = nil
    ) {
        let initialOptions = EquationEditorOptions()
        let renderCache = renderCache ?? RatexRenderCacheStore.shared
        let defaultLatex = #"\frac{\partial L}{\partial \theta_i} = \mathbb{E}_{x \sim \mathcal{D}}\left[\nabla_{\theta_i} f_\theta(x)\right]"#
        let trimmedInitialLatex = initialLatex?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLatex = trimmedInitialLatex?.isEmpty == false ? trimmedInitialLatex ?? defaultLatex : defaultLatex
        self.options = initialOptions
        self.renderCache = renderCache
        latex = resolvedLatex
        latexSelection = EquationTextSelection(location: resolvedLatex.utf16.count, length: 0)
        let initialLatex = resolvedLatex.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialKey = RatexRenderCacheKey(
            latex: initialLatex,
            layoutMode: initialOptions.layoutMode,
            options: initialOptions.ratexRenderOptions
        )
        renderResult = renderCache.cachedResidentResult(for: initialKey) ?? FallbackMathRenderer().renderDisplay(latex: resolvedLatex)
        refreshPreview(loadPersistedCacheImmediately: true)
        refreshTemplatePreviews()
    }

    var templateGroups: [EquationTemplateGroup] {
        EquationTemplateCatalog.groups
    }

    var selectedGroup: EquationTemplateGroup {
        templateGroups.first { $0.id == selectedGroupID } ?? templateGroups[0]
    }

    var hasRenderedSVG: Bool {
        if case .svg = renderResult.payload {
            return true
        }
        return false
    }

    func refreshPreview(loadPersistedCacheImmediately: Bool = false) {
        previewCancellationToken.cancel()
        let cancellationToken = RatexRenderCancellationToken()
        previewCancellationToken = cancellationToken
        previewTask?.cancel()

        let latex = latex
        let options = options
        let trimmedLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision = previewRevision + 1
        previewRevision = revision
        guard !trimmedLatex.isEmpty else {
            publishRenderResult(FallbackMathRenderer().renderDisplay(latex: ""))
            publishRenderingPreview(false)
            return
        }

        let key = RatexRenderCacheKey(
            latex: trimmedLatex,
            layoutMode: options.layoutMode,
            options: options.ratexRenderOptions
        )
        if let cachedResult = renderCache.cachedResidentResult(for: key) {
            publishRenderResult(cachedResult)
            publishRenderingPreview(false)
            return
        }

        publishRenderingPreview(true)
        previewTask = Task { @MainActor [trimmedLatex, options, key, revision, loadPersistedCacheImmediately] in
            if loadPersistedCacheImmediately,
               let cachedResult = await renderCache.cachedPersistedResult(
                    for: key,
                    priority: .userInitiated
               )
            {
                guard !Task.isCancelled, previewRevision == revision else { return }
                publishRenderResult(cachedResult)
                publishRenderingPreview(false)
                return
            }
            guard !Task.isCancelled, previewRevision == revision else { return }
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, previewRevision == revision else { return }

            let result = await renderCache.result(
                for: key,
                priority: .userInitiated,
                isCancelled: { cancellationToken.isCancelled },
                cancelledResult: {
                    FallbackMathRenderer().renderDisplay(latex: trimmedLatex)
                }
            ) {
                let renderer = RatexMathRenderer(options: options.ratexRenderOptions)
                switch options.layoutMode {
                case .inline:
                    return renderer.renderInline(latex: trimmedLatex)
                case .block:
                    return renderer.renderDisplay(latex: trimmedLatex)
                }
            }

            guard !Task.isCancelled, previewRevision == revision else { return }
            publishRenderResult(result)
            publishRenderingPreview(false)
        }
    }

    func cancelPreview() {
        previewCancellationToken.cancel()
        templatePreviewCancellationToken.cancel()
        previewTask?.cancel()
        templatePreviewTask?.cancel()
        publishRenderingPreview(false)
    }

    private func publishRenderResult(_ nextResult: MathRenderResult) {
        guard EquationPreviewPublicationPolicy.shouldPublishResult(
            current: renderResult,
            next: nextResult
        ) else { return }
        renderResult = nextResult
    }

    private func publishRenderingPreview(_ nextValue: Bool) {
        guard EquationPreviewPublicationPolicy.shouldPublishRenderingFlag(
            current: isRenderingPreview,
            next: nextValue
        ) else { return }
        isRenderingPreview = nextValue
    }

    var rendererStatus: String {
        switch renderResult.payload {
        case .svg:
            return "RaTeX SVG"
        case .plainText:
            return "Plain fallback"
        case .unavailable:
            return "RaTeX unavailable"
        }
    }

    var ratexRuntimeDescription: String {
        if let executableURL = RatexSVGCLIAdapter.discoveredExecutableURL() {
            return executableURL.path
        }
        return "Missing render-svg. Set RATEX_RENDER_SVG_PATH or install RaTeX CLI."
    }

    var rendererDetail: String {
        switch renderResult.payload {
        case .svg:
            return "Rendered with \(ratexRuntimeDescription)"
        case .plainText:
            return "Waiting for RaTeX preview."
        case .unavailable(let reason):
            return reason
        }
    }

    var diagnostics: [String] {
        EquationSyntaxInspector.diagnostics(for: latex)
    }

    var suggestions: [EquationTemplate] {
        Array(EquationSyntaxInspector.suggestions(for: latex).prefix(6))
    }

    func templateRenderResult(for template: EquationTemplate) -> MathRenderResult? {
        templateRenderResults[template.id]
    }

    func refreshTemplatePreviews() {
        templatePreviewCancellationToken.cancel()
        let cancellationToken = RatexRenderCancellationToken()
        templatePreviewCancellationToken = cancellationToken
        templatePreviewTask?.cancel()

        let options = RatexRenderOptions(fontSize: 16, foregroundColor: "#111111", timeoutSeconds: 3)
        let templates = selectedGroup.templates.filter(EquationTemplatePreviewPolicy.shouldRenderPreview)
        var cachedResults: [String: MathRenderResult] = [:]
        var missingTemplates: [EquationTemplate] = []

        for template in templates {
            let key = RatexRenderCacheKey(
                latex: template.renderedPreviewLatex,
                layoutMode: .block,
                options: options
            )
            if let cachedResult = renderCache.cachedResidentResult(for: key) {
                cachedResults[template.id] = cachedResult
            } else {
                missingTemplates.append(template)
            }
        }

        if !cachedResults.isEmpty {
            mergeTemplateRenderResults(cachedResults)
        }
        guard !missingTemplates.isEmpty else { return }

        let revision = templatePreviewRevision + 1
        templatePreviewRevision = revision
        templatePreviewTask = Task { @MainActor [missingTemplates, options, revision] in
            var pendingResults: [String: MathRenderResult] = [:]
            pendingResults.reserveCapacity(min(missingTemplates.count, EquationTemplateRenderQueue.stateCommitBatchSize))

            for (index, template) in missingTemplates.enumerated() {
                guard !Task.isCancelled, templatePreviewRevision == revision else { return }
                let key = RatexRenderCacheKey(
                    latex: template.renderedPreviewLatex,
                    layoutMode: .block,
                    options: options
                )
                let title = template.title
                let latex = template.renderedPreviewLatex
                let result = await renderCache.result(
                    for: key,
                    priority: .utility,
                    isCancelled: { cancellationToken.isCancelled },
                    cancelledResult: {
                        FallbackMathRenderer().renderDisplay(
                            latex: latex,
                            accessibilityLabel: title
                        )
                    }
                ) {
                    RatexMathRenderer(options: options)
                        .renderDisplay(
                            latex: latex,
                            accessibilityLabel: title
                        )
                }
                guard !Task.isCancelled, templatePreviewRevision == revision else { return }
                pendingResults[template.id] = result
                let remainingCount = missingTemplates.count - index - 1
                if EquationTemplateRenderQueue.shouldCommitRenderedBatch(
                    count: pendingResults.count,
                    remainingCount: remainingCount
                ) {
                    mergeTemplateRenderResults(pendingResults)
                    pendingResults.removeAll(keepingCapacity: true)
                }
            }
        }
    }

    private func mergeTemplateRenderResults(_ results: [String: MathRenderResult]) {
        guard !results.isEmpty else { return }
        var merged = templateRenderResults
        merged.merge(results) { _, new in new }
        guard merged != templateRenderResults else { return }
        templateRenderResults = merged
    }

    func insert(_ template: EquationTemplate) {
        let result = EquationTemplateInsertionPlanner.insert(
            template,
            into: latex,
            selection: latexSelection
        )
        latex = result.latex
        latexSelection = result.selection
    }

    func clear() {
        latex = ""
        latexSelection = EquationTextSelection()
    }

    func copyLatex() {
        copy(latex.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func copySVG() {
        guard case .svg(let svg) = renderResult.payload else { return }
        copy(svg)
    }

    func saveSVG() {
        guard case .svg(let svg) = renderResult.payload else { return }
        let panel = NSSavePanel()
        panel.title = "Save RaTeX SVG"
        panel.nameFieldStringValue = "equation.svg"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try svg.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            assertionFailure("Failed to save RaTeX SVG: \(error)")
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct EquationTemplatePane: View {
    @ObservedObject var model: EquationEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Templates")
                .font(.headline)

            EquationTemplateGroupSelector(
                groups: model.templateGroups,
                selectedGroupID: $model.selectedGroupID
            )

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text(model.selectedGroup.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(model.selectedGroup.templates.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVGrid(
                    columns: EquationTemplateGridLayout.columns,
                    spacing: 10
                ) {
                    ForEach(model.selectedGroup.templates) { template in
                        Button {
                            model.insert(template)
                        } label: {
                            EquationTemplateButton(
                                template: template,
                                renderResult: model.templateRenderResult(for: template)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(template.latex)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct EquationTemplateGroupSelector: View {
    var groups: [EquationTemplateGroup]
    @Binding var selectedGroupID: String

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(groups) { group in
                Button {
                    selectedGroupID = group.id
                } label: {
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .padding(.horizontal, 8)
                        .background(groupBackground(for: group), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(groupBorder(for: group), lineWidth: 1)
                        )
                        .foregroundStyle(group.id == selectedGroupID ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func groupBackground(for group: EquationTemplateGroup) -> Color {
        if group.id == selectedGroupID {
            return Color.accentColor.opacity(0.13)
        }
        return Color(nsColor: .textBackgroundColor)
    }

    private func groupBorder(for group: EquationTemplateGroup) -> Color {
        if group.id == selectedGroupID {
            return Color.accentColor.opacity(0.35)
        }
        return Color(nsColor: .separatorColor)
    }
}

private struct EquationTemplateButton: View {
    var template: EquationTemplate
    var renderResult: MathRenderResult?
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(template.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            preview
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(tileBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tileBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(template.title), inserts \(template.latex)")
    }

    private var tileBackground: Color {
        isHovered ? Color.accentColor.opacity(0.08) : Color(nsColor: .textBackgroundColor)
    }

    private var tileBorder: Color {
        isHovered ? Color.accentColor.opacity(0.32) : Color(nsColor: .separatorColor)
    }

    @ViewBuilder
    private var preview: some View {
        if EquationTemplatePreviewPolicy.prefersTypographicFallback(template) {
            fallbackPreview
        } else {
            switch renderResult?.payload {
            case .some(.svg(let svg)):
                SVGImageView(svg: svg, accessibilityLabel: template.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .some(.plainText(let value)):
                Text(value)
                    .font(.system(size: 14, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            case .some(.unavailable):
                fallbackPreview
            case .none:
                fallbackPreview
                    .overlay(alignment: .topTrailing) {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(2)
                    }
            }
        }
    }

    @ViewBuilder
    private var fallbackPreview: some View {
        if let fallbackPreviewText = template.fallbackPreviewText {
            Text(fallbackPreviewText)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text(template.renderedFallbackPreviewText)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

enum EquationTemplateGridLayout {
    static let columns = [
        GridItem(.adaptive(minimum: 112, maximum: 180), spacing: 10)
    ]
}

private struct EquationEditorCenterPane: View {
    @ObservedObject var model: EquationEditorModel
    var showsInlineOptions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsInlineOptions {
                EquationInlineOptionsBar(model: model)
            }

            HStack {
                Label("LaTeX", systemImage: "text.cursor")
                    .font(.headline)
                Spacer()
                Button {
                    model.clear()
                } label: {
                    Label("Clear LaTeX", systemImage: "trash")
                }
                .controlSize(.regular)
                .help("Clear LaTeX input")
            }

            EquationLatexTextEditor(
                text: $model.latex,
                selection: $model.latexSelection
            )
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .frame(minHeight: 150, idealHeight: 220, maxHeight: 280)

            if !model.suggestions.isEmpty || !model.diagnostics.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    if !model.suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(model.suggestions) { template in
                                    Button(template.latex) {
                                        model.insert(template)
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.system(size: 11, design: .monospaced))
                                }
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if !model.diagnostics.isEmpty {
                        VStack(alignment: .trailing, spacing: 4) {
                            ForEach(model.diagnostics, id: \.self) { diagnostic in
                                Label(diagnostic, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            EquationPreviewPane(model: model)
                .frame(minHeight: 260, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct EquationLatexTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: EquationTextSelection

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selection: $selection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.string = text
        textView.setSelectedRange(selection.clamped(to: text).nsRange)
        context.coordinator.textView = textView
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.isApplyingUpdate = true
        if textView.string != text {
            textView.string = text
        }
        let targetRange = selection.clamped(to: textView.string).nsRange
        if textView.selectedRange() != targetRange {
            textView.setSelectedRange(targetRange)
        }
        context.coordinator.isApplyingUpdate = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var selection: Binding<EquationTextSelection>
        weak var textView: NSTextView?
        var isApplyingUpdate = false

        init(text: Binding<String>, selection: Binding<EquationTextSelection>) {
            self.text = text
            self.selection = selection
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate, let textView = notification.object as? NSTextView else { return }
            let nextText = textView.string
            if EquationLatexEditorUpdatePolicy.shouldPublishText(
                current: text.wrappedValue,
                next: nextText
            ) {
                text.wrappedValue = nextText
            }
            publishSelectionIfNeeded(EquationTextSelection(nsRange: textView.selectedRange()))
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingUpdate, let textView = notification.object as? NSTextView else { return }
            publishSelectionIfNeeded(EquationTextSelection(nsRange: textView.selectedRange()))
        }

        private func publishSelectionIfNeeded(_ nextSelection: EquationTextSelection) {
            guard EquationLatexEditorUpdatePolicy.shouldPublishSelection(
                current: selection.wrappedValue,
                next: nextSelection
            ) else { return }
            selection.wrappedValue = nextSelection
        }
    }
}

private extension EquationTextSelection {
    init(nsRange: NSRange) {
        self.init(location: nsRange.location, length: nsRange.length)
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

private struct EquationInlineOptionsBar: View {
    @ObservedObject var model: EquationEditorModel

    var body: some View {
        HStack(spacing: 12) {
            optionPicker("Size") {
                Picker("Size", selection: $model.options.displaySize) {
                    ForEach(EquationDisplaySize.allCases, id: \.self) { size in
                        Text(size.label).tag(size)
                    }
                }
                .labelsHidden()
                .frame(width: 92)
            }

            optionPicker("Color") {
                Picker("Color", selection: $model.options.color) {
                    ForEach(EquationOutputColor.allCases, id: \.self) { color in
                        Text(color.label).tag(color)
                    }
                }
                .labelsHidden()
                .frame(width: 134)
            }

            optionPicker("Mode") {
                Picker("Mode", selection: $model.options.layoutMode) {
                    ForEach(EquationLayoutMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 104)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func optionPicker<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct EquationPreviewPane: View {
    @ObservedObject var model: EquationEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Preview", systemImage: "eye")
                    .font(.headline)
                Spacer()
                Text(model.isRenderingPreview ? "Rendering RaTeX..." : model.rendererStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(previewBackground)
                previewContent
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 220, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: model.hasRenderedSVG ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.hasRenderedSVG ? .green : .orange)
                Text(model.rendererDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }

    private var previewBackground: Color {
        switch model.options.color {
        case .black:
            return Color(nsColor: .textBackgroundColor)
        case .white:
            return .black.opacity(0.72)
        case .red:
            return .red.opacity(0.08)
        case .green:
            return .green.opacity(0.08)
        case .blue:
            return .blue.opacity(0.08)
        case .transparent:
            return Color(nsColor: .textBackgroundColor)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch model.renderResult.payload {
        case .svg(let svg):
            SVGImageView(svg: svg, accessibilityLabel: "RaTeX rendered equation")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .plainText(let value):
            Text(value)
                .font(.system(size: CGFloat(model.options.displaySize.rawValue + 8), weight: .regular, design: .serif))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: model.options.layoutMode == .inline ? .leading : .center)
        case .unavailable(let reason):
            VStack(spacing: 8) {
                Text(model.latex)
                    .font(.system(size: CGFloat(model.options.displaySize.rawValue + 8), weight: .regular, design: .serif))
                    .textSelection(.enabled)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: model.options.layoutMode == .inline ? .leading : .center)
        }
    }
}

private struct EquationOptionsPane: View {
    @ObservedObject var model: EquationEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Render")
                    .font(.headline)

                VStack(spacing: 0) {
                    optionRow("Size") {
                        Picker("Size", selection: $model.options.displaySize) {
                            ForEach(EquationDisplaySize.allCases, id: \.self) { size in
                                Text(size.label).tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 96)
                    }

                    Divider()

                    optionRow("Color") {
                        Picker("Color", selection: $model.options.color) {
                            ForEach(EquationOutputColor.allCases, id: \.self) { color in
                                Text(color.label).tag(color)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 132)
                    }

                    Divider()

                    optionRow("Mode") {
                        Picker("Mode", selection: $model.options.layoutMode) {
                            ForEach(EquationLayoutMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue.capitalized).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 104)
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("RaTeX Runtime", systemImage: "terminal")
                    .font(.headline)

                Text(model.ratexRuntimeDescription)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func optionRow<Content: View>(
        _ title: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body)
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 48)
    }
}
