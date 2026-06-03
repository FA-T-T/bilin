import SwiftUI
import BilinReaderKit
import BilinRenderKit

struct WorkbenchView: View {
    @EnvironmentObject private var model: ReaderWorkbenchModel

    var body: some View {
        NavigationSplitView {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            ArticleListPane()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            ReaderDetailPane()
        }
        .frame(minWidth: 1080, minHeight: 720)
    }
}

private struct LibrarySidebar: View {
    @EnvironmentObject private var model: ReaderWorkbenchModel

    var body: some View {
        List(selection: $model.selectedLibraryId) {
            Section("Libraries") {
                ForEach(model.libraries) { library in
                    Label(library.name, systemImage: "books.vertical")
                        .tag(Optional(library.id))
                }
            }
            Section("Local State") {
                Label("\(model.tasks.count) tasks", systemImage: "bolt.horizontal")
                Label("\(model.notes.count) notes", systemImage: "note.text")
            }
        }
        .navigationTitle("Bilin")
    }
}

private struct ArticleListPane: View {
    @EnvironmentObject private var model: ReaderWorkbenchModel

    var body: some View {
        List(selection: $model.selectedArticleId) {
            Section("Papers") {
                ForEach(model.articles) { article in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.headline)
                            .lineLimit(3)
                        Text("\(article.source) \(article.externalId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .tag(Optional(article.id))
                }
            }
        }
        .navigationTitle("Library")
    }
}

private struct ReaderDetailPane: View {
    @EnvironmentObject private var model: ReaderWorkbenchModel
    @State private var inspectorPresented = true

    var body: some View {
        HStack(spacing: 0) {
            ReaderSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if inspectorPresented {
                Divider()
                InspectorPane()
                    .frame(width: 320)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
                Button {} label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                Button {} label: {
                    Label("Translate Selection", systemImage: "character.bubble")
                }
            }
        }
        .navigationTitle(model.selectedArticle?.title ?? "Reader")
    }
}

private struct ReaderSurface: View {
    @EnvironmentObject private var model: ReaderWorkbenchModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let loadError = model.loadError {
                    Text(loadError)
                        .foregroundStyle(.red)
                }
                ForEach(model.blocks) { block in
                    ReaderBlockRow(
                        block: block,
                        isSelected: model.selectedBlockUid == block.blockUid
                    )
                    .onTapGesture {
                        model.selectedBlockUid = block.blockUid
                    }
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 46)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ReaderBlockRow: View {
    var block: DocumentBlock
    var isSelected: Bool
    private let mathRenderer = FallbackMathRenderer()

    var body: some View {
        Group {
            switch block.blockType {
            case .title:
                Text(block.sourceMarkdown)
                    .font(.largeTitle.weight(.semibold))
            case .section, .subsection:
                Text(block.sourceMarkdown)
                    .font(.title2.weight(.semibold))
            case .equation:
                EquationBlockView(
                    result: mathRenderer.renderDisplay(latex: block.sourceLatex ?? block.sourceMarkdown)
                )
            default:
                Text(block.sourceMarkdown)
                    .font(.system(size: 16.5, weight: .regular, design: .serif))
                    .lineSpacing(5)
            }
        }
        .padding(.horizontal, isSelected ? 12 : 0)
        .padding(.vertical, isSelected ? 8 : 0)
        .background(isSelected ? Color.accentColor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }

}

private struct EquationBlockView: View {
    var result: MathRenderResult

    var body: some View {
        Text(displayText)
            .font(.system(.body, design: .serif))
            .monospaced()
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Equation \(result.accessibilityLabel)")
    }

    private var displayText: String {
        switch result.payload {
        case .plainText(let value), .svg(let value):
            return value
        case .unavailable(let reason):
            return "\(result.latex)\n\(reason)"
        }
    }
}

private struct InspectorPane: View {
    @EnvironmentObject private var model: ReaderWorkbenchModel
    @State private var noteTitle = "Reading note"
    @State private var noteMarkdown = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Selection") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.selectedBlock?.blockUid ?? "No block selected")
                        .font(.headline)
                    Text(model.selectedBlock?.blockType.rawValue ?? "Select a block in the reader")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Notes") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Title", text: $noteTitle)
                    TextEditor(text: $noteMarkdown)
                        .frame(minHeight: 110)
                    Button("Save note") {
                        Task {
                            await model.saveDraftNote(title: noteTitle, markdown: noteMarkdown)
                            noteMarkdown = ""
                        }
                    }
                    .disabled(noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            GroupBox("Tasks") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.tasks) { task in
                        HStack {
                            Circle()
                                .fill(task.status == .running ? .green : .secondary)
                                .frame(width: 8, height: 8)
                            Text(task.message ?? task.stage ?? task.status.rawValue)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
