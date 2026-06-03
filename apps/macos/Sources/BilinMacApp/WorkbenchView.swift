import SwiftUI
import BilinImportKit
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
        .sheet(isPresented: $model.equationEditorPresented) {
            EquationEditorView()
        }
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
                Label(model.readingProgressLabel, systemImage: "clock")
                Label("\(model.zoteroItems.count) Zotero items", systemImage: "tray.full")
                if let schemaStatus = model.schemaStatus {
                    Label(schemaStatus.isWritable ? "schema current" : "schema read-only", systemImage: "checkmark.seal")
                }
                if let zoteroSchemaStatus = model.zoteroSchemaStatus {
                    Label(zoteroSchemaStatus.isReadable ? "Zotero readable" : "Zotero unsupported", systemImage: "externaldrive")
                }
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
            Section("Zotero Metadata") {
                ForEach(model.zoteroItems) { item in
                    ZoteroItemRow(item: item)
                        .tag(Optional("zotero:\(item.id)"))
                }
            }
        }
        .onChange(of: model.selectedArticleId) { _, articleId in
            Task {
                if let articleId, articleId.hasPrefix("zotero:"), let itemID = Int64(articleId.dropFirst("zotero:".count)) {
                    model.selectZoteroItem(id: itemID)
                } else {
                    await model.selectArticle(id: articleId)
                }
            }
        }
        .navigationTitle("Library")
    }
}

private struct ZoteroItemRow: View {
    var item: ZoteroItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title ?? item.key)
                .font(.headline)
                .lineLimit(3)
            HStack(spacing: 6) {
                Text(item.itemType)
                if let arxiv = item.arxiv {
                    Text("arXiv \(arxiv.concreteIdentifier)")
                }
                if !item.tags.isEmpty {
                    Text(item.tags.prefix(2).joined(separator: ", "))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct ReaderDetailPane: View {
    @EnvironmentObject private var model: ReaderWorkbenchModel
    @State private var inspectorPresented = true

    var body: some View {
        Group {
            if let item = model.selectedZoteroItem {
                ZoteroMetadataDetailPane(item: item)
            } else {
                HStack(spacing: 0) {
                    ReaderSurface()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if inspectorPresented {
                        Divider()
                        InspectorPane()
                            .frame(width: 320)
                    }
                }
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
        .navigationTitle(model.selectedArticle?.title ?? model.selectedZoteroItem?.title ?? "Reader")
    }
}

private struct ZoteroMetadataDetailPane: View {
    var item: ZoteroItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.title ?? item.key)
                    .font(.largeTitle.weight(.semibold))
                HStack(spacing: 10) {
                    Label(item.itemType, systemImage: "doc.text")
                    if let arxiv = item.arxiv {
                        Label("arXiv \(arxiv.concreteIdentifier)", systemImage: "number")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !item.creators.isEmpty {
                    MetadataSection(title: "Creators", value: item.creators.map(\.displayName).joined(separator: ", "))
                }
                if let abstractNote = item.abstractNote {
                    MetadataSection(title: "Abstract", value: abstractNote)
                }
                HStack(spacing: 10) {
                    Button {} label: {
                        Label("Download Metadata", systemImage: "arrow.down.doc")
                    }
                    .disabled(true)
                    Button {} label: {
                        Label("Import Paper", systemImage: "square.and.arrow.down")
                    }
                    .disabled(true)
                    Button {} label: {
                        Label("Translate", systemImage: "character.bubble")
                    }
                    .disabled(true)
                }
                if !item.collections.isEmpty {
                    MetadataSection(title: "Collections", value: item.collections.map(\.name).joined(separator: ", "))
                }
                if !item.tags.isEmpty {
                    MetadataSection(title: "Tags", value: item.tags.joined(separator: ", "))
                }
                if let doi = item.doi {
                    MetadataSection(title: "DOI", value: doi)
                }
                if let url = item.url {
                    MetadataSection(title: "URL", value: url)
                }
                if !item.attachments.isEmpty {
                    MetadataSection(
                        title: "Attachments",
                        value: item.attachments.compactMap(\.path).joined(separator: "\n")
                    )
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 46)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct MetadataSection: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .lineSpacing(4)
        }
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
                    Text(model.readingProgressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Notes") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(model.notes.count) saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            GroupBox("Translation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(model.translations.count) zh-CN blocks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let translation = model.selectedBlockTranslation {
                        Text(translation.rawMarkdown)
                            .font(.callout)
                            .lineLimit(8)
                    } else {
                        Text("No translation for selection")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
