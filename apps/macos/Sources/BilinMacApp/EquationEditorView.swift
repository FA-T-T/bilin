import SwiftUI
import AppKit
import BilinRenderKit

struct EquationEditorView: View {
    @StateObject private var model = EquationEditorModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("RaTeX Equation Editor", systemImage: "function")
                    .font(.headline)
                Spacer()
                Button {
                    model.copyLatex()
                } label: {
                    Label("Copy LaTeX", systemImage: "doc.on.doc")
                }
                Button {
                    model.copyExport()
                } label: {
                    Label("Copy Export", systemImage: "square.on.square")
                }
                Button {
                    model.saveExport()
                } label: {
                    Label("Save Export", systemImage: "square.and.arrow.down")
                }
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HStack(spacing: 0) {
                EquationTemplatePane(model: model)
                    .frame(width: 240)

                Divider()

                EquationEditorCenterPane(model: model)
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                EquationOptionsPane(model: model)
                    .frame(width: 260)
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

@MainActor
private final class EquationEditorModel: ObservableObject {
    @Published var latex = #"\frac{\partial L}{\partial \theta_i} = \mathbb{E}_{x \sim \mathcal{D}}\left[\nabla_{\theta_i} f_\theta(x)\right]"#
    @Published var options = EquationEditorOptions()
    @Published var selectedGroupID = EquationTemplateCatalog.groups.first?.id ?? "structure"

    private let renderer = RatexMathRenderer()

    var templateGroups: [EquationTemplateGroup] {
        EquationTemplateCatalog.groups
    }

    var selectedGroup: EquationTemplateGroup {
        templateGroups.first { $0.id == selectedGroupID } ?? templateGroups[0]
    }

    var renderResult: MathRenderResult {
        switch options.layoutMode {
        case .inline:
            return renderer.renderInline(latex: latex)
        case .block:
            return renderer.renderDisplay(latex: latex)
        }
    }

    var exportString: String {
        EquationEditorExportBuilder.exportString(latex: latex, options: options)
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

    var diagnostics: [String] {
        EquationSyntaxInspector.diagnostics(for: latex)
    }

    var suggestions: [EquationTemplate] {
        Array(EquationSyntaxInspector.suggestions(for: latex).prefix(6))
    }

    func insert(_ template: EquationTemplate) {
        if latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            latex = template.latex
        } else {
            latex += " " + template.latex
        }
    }

    func clear() {
        latex = ""
    }

    func copyLatex() {
        copy(latex.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func copyExport() {
        copy(exportString)
    }

    func saveExport() {
        let panel = NSSavePanel()
        panel.title = "Save equation export"
        panel.nameFieldStringValue = "equation.\(fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportString.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            assertionFailure("Failed to save equation export: \(error)")
        }
    }

    private var fileExtension: String {
        switch options.exportTarget {
        case .html, .wordpress:
            return "html"
        case .xml:
            return "xml"
        case .latex:
            return "tex"
        case .url, .urlEncoded:
            return "txt"
        case .phpBB, .tinyWiki, .pre, .doxygen:
            return "txt"
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
        VStack(alignment: .leading, spacing: 12) {
            Picker("Template group", selection: $model.selectedGroupID) {
                ForEach(model.templateGroups) { group in
                    Text(group.title).tag(group.id)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(model.selectedGroup.templates) { template in
                    Button {
                        model.insert(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.title)
                                .font(.caption.weight(.semibold))
                            Text(template.latex)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct EquationEditorCenterPane: View {
    @ObservedObject var model: EquationEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("LaTeX", systemImage: "text.cursor")
                    .font(.headline)
                Spacer()
                Button {
                    model.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }

            TextEditor(text: $model.latex)
                .font(.system(size: 15, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .frame(minHeight: 150)

            if !model.suggestions.isEmpty || !model.diagnostics.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    if !model.suggestions.isEmpty {
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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Export", systemImage: "arrowshape.turn.up.right")
                        .font(.headline)
                    Spacer()
                    Text(model.options.exportTarget.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: .constant(model.exportString))
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .frame(minHeight: 120)
            }
        }
        .padding(18)
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
                Text(model.rendererStatus)
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
            .frame(minHeight: 150)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    private var previewBackground: Color {
        switch model.options.color {
        case .black:
            return .black
        case .white:
            return .white
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
            ScrollView {
                Text(svg)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
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
        Form {
            Picker("Format", selection: $model.options.imageFormat) {
                ForEach(EquationImageFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            Picker("Size", selection: $model.options.displaySize) {
                ForEach(EquationDisplaySize.allCases, id: \.self) { size in
                    Text(size.label).tag(size)
                }
            }
            Picker("DPI", selection: $model.options.dpi) {
                ForEach(EquationDPI.allCases, id: \.self) { dpi in
                    Text("\(dpi.rawValue)").tag(dpi)
                }
            }
            Picker("Color", selection: $model.options.color) {
                ForEach(EquationOutputColor.allCases, id: \.self) { color in
                    Text(color.label).tag(color)
                }
            }
            Picker("Mode", selection: $model.options.layoutMode) {
                ForEach(EquationLayoutMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue.capitalized).tag(mode)
                }
            }
            Picker("Output", selection: $model.options.exportTarget) {
                ForEach(EquationExportTarget.allCases, id: \.self) { target in
                    Text(target.label).tag(target)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
