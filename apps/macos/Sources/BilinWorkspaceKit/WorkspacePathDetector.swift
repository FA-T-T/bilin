import Foundation

public struct WorkspacePathDetector {
    public var homeDirectoryURL: URL
    public var fileManager: FileManager

    public init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectoryURL = homeDirectoryURL
        self.fileManager = fileManager
    }

    public func detectPathRecords(now: Date = Date()) -> [WorkspacePathRecord] {
        var records: [WorkspacePathRecord] = []
        var seen = Set<String>()

        for record in detectObsidianVaults(now: now) + detectZoteroLibraries(now: now) {
            let key = "\(record.kind.rawValue):\(standardizedPath(record.path))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            records.append(record)
        }

        return records.sorted { lhs, rhs in
            if lhs.kind.rawValue == rhs.kind.rawValue {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    private func detectObsidianVaults(now: Date) -> [WorkspacePathRecord] {
        var records: [WorkspacePathRecord] = []
        for (path, configuredName) in configuredObsidianVaultPaths() {
            records.append(
                pathRecord(
                    path: path,
                    name: configuredName ?? displayName(for: path),
                    kind: .obsidianVault,
                    status: obsidianStatus(for: path),
                    now: now
                )
            )
        }

        for path in commonObsidianVaultPaths() {
            records.append(
                pathRecord(
                    path: path,
                    name: displayName(for: path),
                    kind: .obsidianVault,
                    status: obsidianStatus(for: path),
                    now: now
                )
            )
        }
        return records
    }

    private func detectZoteroLibraries(now: Date) -> [WorkspacePathRecord] {
        var records: [WorkspacePathRecord] = []
        for path in configuredZoteroDataDirectories() {
            records.append(
                pathRecord(
                    path: path,
                    name: displayName(for: path),
                    kind: .zoteroLibrary,
                    status: zoteroStatus(for: path),
                    now: now
                )
            )
        }
        for path in defaultZoteroDataDirectories() where zoteroStatus(for: path) == .available {
            records.append(
                pathRecord(
                    path: path,
                    name: displayName(for: path),
                    kind: .zoteroLibrary,
                    status: .available,
                    now: now
                )
            )
        }
        return records
    }

    private func configuredObsidianVaultPaths() -> [(path: String, name: String?)] {
        let url = homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("obsidian", isDirectory: true)
            .appendingPathComponent("obsidian.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let vaults = json["vaults"] as? [String: Any]
        else {
            return []
        }

        return vaults.values.compactMap { value in
            guard
                let vault = value as? [String: Any],
                let path = vault["path"] as? String,
                !path.isEmpty
            else {
                return nil
            }
            return (expandHome(in: path), vault["name"] as? String)
        }
    }

    private func commonObsidianVaultPaths() -> [String] {
        let roots = [
            homeDirectoryURL.appendingPathComponent("Documents", isDirectory: true),
            homeDirectoryURL.appendingPathComponent("Desktop", isDirectory: true),
            homeDirectoryURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Mobile Documents", isDirectory: true)
                .appendingPathComponent("iCloud~md~obsidian", isDirectory: true)
                .appendingPathComponent("Documents", isDirectory: true)
        ]

        return roots.flatMap { root in
            directVaults(under: root)
        }
    }

    private func directVaults(under root: URL) -> [String] {
        var paths: [String] = []
        if fileManager.fileExists(atPath: root.appendingPathComponent(".obsidian", isDirectory: true).path) {
            paths.append(root.path)
        }
        let children = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children where isDirectory(child) {
            if fileManager.fileExists(atPath: child.appendingPathComponent(".obsidian", isDirectory: true).path) {
                paths.append(child.path)
            }
        }
        return paths
    }

    private func configuredZoteroDataDirectories() -> [String] {
        let profilesURL = homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Zotero", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
        let profiles = (try? fileManager.contentsOfDirectory(
            at: profilesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return profiles
            .filter { isDirectory($0) }
            .compactMap { profileURL in
                zoteroDataDirectory(fromPrefsAt: profileURL.appendingPathComponent("prefs.js"))
            }
    }

    private func zoteroDataDirectory(fromPrefsAt url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            guard line.contains("\"extensions.zotero.dataDir\"") else { continue }
            let parts = line.split(separator: ",", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let rawValue = parts[1]
                .replacingOccurrences(of: ");", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let unquoted = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !unquoted.isEmpty else { continue }
            return expandHome(in: unescapePrefsString(unquoted))
        }
        return nil
    }

    private func defaultZoteroDataDirectories() -> [String] {
        [
            homeDirectoryURL.appendingPathComponent("Zotero", isDirectory: true).path,
            homeDirectoryURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Zotero", isDirectory: true)
                .path
        ]
    }

    private func pathRecord(
        path: String,
        name: String,
        kind: WorkspacePathKind,
        status: ExternalFileTargetStatus,
        now: Date
    ) -> WorkspacePathRecord {
        WorkspacePathRecord(
            id: stableIdentifier(kind: kind, path: path),
            name: name,
            path: standardizedPath(path),
            kind: kind,
            status: status,
            createdAt: now,
            updatedAt: now
        )
    }

    private func obsidianStatus(for path: String) -> ExternalFileTargetStatus {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return fileManager.isReadableFile(atPath: path) ? .available : .permissionRequired
        }
        return .missing
    }

    private func zoteroStatus(for path: String) -> ExternalFileTargetStatus {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            guard fileManager.isReadableFile(atPath: path) else {
                return .permissionRequired
            }
        }
        let databasePath = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("zotero.sqlite")
            .path
        guard fileManager.fileExists(atPath: databasePath) else {
            return .missing
        }
        return fileManager.isReadableFile(atPath: databasePath) ? .available : .permissionRequired
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func displayName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    private func stableIdentifier(kind: WorkspacePathKind, path: String) -> String {
        let slug = standardizedPath(path)
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partialResult, character in
                if character == "-", partialResult.last == "-" {
                    return
                }
                partialResult.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "detected-\(kind.rawValue)-\(String(slug.suffix(80)))"
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: expandHome(in: path)).standardizedFileURL.path
    }

    private func expandHome(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return homeDirectoryURL.path + path.dropFirst()
    }

    private func unescapePrefsString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }
}
