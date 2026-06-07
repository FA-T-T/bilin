import Foundation

public struct WritingProjectLocation: Hashable, Sendable {
    public var rootPath: String
    public var kind: WritingProjectKind
    public var status: WritingProjectStatus
    public var mainFilePath: String?
    public var sectionAnchors: [WritingPatchSectionAnchor]
    public var bibliographyFilePaths: [String]
    public var detectedFilePaths: [String]

    public init(
        rootPath: String,
        kind: WritingProjectKind,
        status: WritingProjectStatus,
        mainFilePath: String?,
        sectionAnchors: [WritingPatchSectionAnchor] = [],
        bibliographyFilePaths: [String],
        detectedFilePaths: [String]
    ) {
        self.rootPath = rootPath
        self.kind = kind
        self.status = status
        self.mainFilePath = mainFilePath
        self.sectionAnchors = sectionAnchors
        self.bibliographyFilePaths = bibliographyFilePaths
        self.detectedFilePaths = detectedFilePaths
    }
}

public struct WritingProjectLocator: Sendable {
    public init() {}

    public func locate(rootPath: String) -> WritingProjectLocation {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return WritingProjectLocation(
                rootPath: rootPath,
                kind: .unknown,
                status: .missing,
                mainFilePath: nil,
                bibliographyFilePaths: [],
                detectedFilePaths: []
            )
        }

        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )) ?? []
        let files = candidates
            .filter { !isDirectory($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let mainFile = preferredMainFile(from: files)
        let detectedFilePaths = files.map(\.path)
        let sectionAnchors = sectionAnchors(from: mainFile)
        let bibliographyFilePaths = bibliographyFilePaths(from: files, mainFile: mainFile)
        let kind = projectKind(mainFile: mainFile, files: files)

        return WritingProjectLocation(
            rootPath: rootPath,
            kind: kind,
            status: mainFile == nil ? .needsMainFile : .linked,
            mainFilePath: mainFile?.path,
            sectionAnchors: sectionAnchors,
            bibliographyFilePaths: bibliographyFilePaths,
            detectedFilePaths: detectedFilePaths
        )
    }

    public func mainFileText(for location: WritingProjectLocation) -> String? {
        guard let mainFilePath = location.mainFilePath else { return nil }
        return try? String(contentsOf: URL(fileURLWithPath: mainFilePath), encoding: .utf8)
    }

    private func preferredMainFile(from files: [URL]) -> URL? {
        for name in ["main.typ", "paper.typ", "manuscript.typ", "main.tex", "paper.tex", "manuscript.tex"] {
            if let url = files.first(where: { $0.lastPathComponent == name }) {
                return url
            }
        }
        return files.first {
            ["typ", "tex"].contains($0.pathExtension.lowercased())
        }
    }

    private func sectionAnchors(from mainFile: URL?) -> [WritingPatchSectionAnchor] {
        guard
            let mainFile,
            let text = try? String(contentsOf: mainFile, encoding: .utf8)
        else { return [] }

        return WritingPatchPlanner().scanSections(
            in: text,
            fileExtension: mainFile.pathExtension
        )
    }

    private func bibliographyFilePaths(from files: [URL], mainFile: URL?) -> [String] {
        var paths = files
            .filter { $0.pathExtension.lowercased() == "bib" }
            .map(\.path)

        if
            let mainFile,
            let text = try? String(contentsOf: mainFile, encoding: .utf8)
        {
            let planner = WritingPatchPlanner()
            let referenced = planner.detectBibliography(
                in: text,
                fileExtension: mainFile.pathExtension
            )
            let root = mainFile.deletingLastPathComponent()
            paths.append(contentsOf: referenced.map {
                URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL.path
            })
        }

        var seen: Set<String> = []
        return paths
            .filter { path in
                if seen.contains(path) { return false }
                seen.insert(path)
                return true
            }
            .sorted()
    }

    private func projectKind(mainFile: URL?, files: [URL]) -> WritingProjectKind {
        if let mainFile {
            switch mainFile.pathExtension.lowercased() {
            case "typ":
                return .typst
            case "tex":
                return .tex
            default:
                break
            }
        }
        let hasTypst = files.contains { $0.pathExtension.lowercased() == "typ" }
        let hasTeX = files.contains { $0.pathExtension.lowercased() == "tex" }
        if hasTypst && hasTeX { return .mixed }
        if hasTypst { return .typst }
        if hasTeX { return .tex }
        return .unknown
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
