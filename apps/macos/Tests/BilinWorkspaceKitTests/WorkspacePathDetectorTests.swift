import XCTest
@testable import BilinWorkspaceKit

final class WorkspacePathDetectorTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testDetectsObsidianVaultsFromConfigAndCommonDocumentRoots() throws {
        let homeURL = try makeTemporaryHome()
        let configuredVaultURL = homeURL.appendingPathComponent("Research Notes", isDirectory: true)
        let discoveredVaultURL = homeURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Lab Notes", isDirectory: true)
        try makeObsidianVault(at: configuredVaultURL)
        try makeObsidianVault(at: discoveredVaultURL)
        let obsidianConfigURL = homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("obsidian", isDirectory: true)
            .appendingPathComponent("obsidian.json")
        try FileManager.default.createDirectory(
            at: obsidianConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "vaults": {
            "abc": {
              "path": "\(configuredVaultURL.path)",
              "name": "Research"
            }
          }
        }
        """.write(to: obsidianConfigURL, atomically: true, encoding: .utf8)

        let records = WorkspacePathDetector(homeDirectoryURL: homeURL)
            .detectPathRecords(now: baseDate)

        let vaults = records.filter { $0.kind == .obsidianVault }
        XCTAssertEqual(Set(vaults.map(\.path)), Set([configuredVaultURL.path, discoveredVaultURL.path]))
        XCTAssertTrue(vaults.allSatisfy { $0.status == .available })
        XCTAssertTrue(vaults.contains { $0.name == "Research" && $0.path == configuredVaultURL.path })
    }

    func testDetectsZoteroDataDirectoryFromProfilePrefs() throws {
        let homeURL = try makeTemporaryHome()
        let dataDirectoryURL = homeURL.appendingPathComponent("Library/Zotero Data", isDirectory: true)
        try makeZoteroDataDirectory(at: dataDirectoryURL)
        let prefsURL = homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Zotero", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("abc.default", isDirectory: true)
            .appendingPathComponent("prefs.js")
        try FileManager.default.createDirectory(
            at: prefsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        user_pref("extensions.zotero.dataDir", "\(dataDirectoryURL.path)");
        """.write(to: prefsURL, atomically: true, encoding: .utf8)

        let records = WorkspacePathDetector(homeDirectoryURL: homeURL)
            .detectPathRecords(now: baseDate)

        let zotero = try XCTUnwrap(records.first { $0.kind == .zoteroLibrary })
        XCTAssertEqual(zotero.path, dataDirectoryURL.path)
        XCTAssertEqual(zotero.status, .available)
    }

    func testDetectsDefaultZoteroDirectoryAndDeduplicatesPrefsCandidate() throws {
        let homeURL = try makeTemporaryHome()
        let defaultDataURL = homeURL.appendingPathComponent("Zotero", isDirectory: true)
        try makeZoteroDataDirectory(at: defaultDataURL)
        let prefsURL = homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Zotero", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("abc.default", isDirectory: true)
            .appendingPathComponent("prefs.js")
        try FileManager.default.createDirectory(
            at: prefsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        user_pref("extensions.zotero.dataDir", "~/Zotero");
        """.write(to: prefsURL, atomically: true, encoding: .utf8)

        let records = WorkspacePathDetector(homeDirectoryURL: homeURL)
            .detectPathRecords(now: baseDate)

        let zoteroRecords = records.filter { $0.kind == .zoteroLibrary && $0.path == defaultDataURL.path }
        XCTAssertEqual(zoteroRecords.count, 1)
        XCTAssertEqual(zoteroRecords.first?.status, .available)
    }

    func testConfiguredObsidianVaultReportsPermissionRequiredWhenUnreadable() throws {
        let homeURL = try makeTemporaryHome()
        let configuredVaultURL = homeURL.appendingPathComponent("Research Notes", isDirectory: true)
        try makeObsidianVault(at: configuredVaultURL)
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: configuredVaultURL.path
            )
        }
        let obsidianConfigURL = homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("obsidian", isDirectory: true)
            .appendingPathComponent("obsidian.json")
        try FileManager.default.createDirectory(
            at: obsidianConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "vaults": {
            "abc": {
              "path": "\(configuredVaultURL.path)",
              "name": "Research"
            }
          }
        }
        """.write(to: obsidianConfigURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: configuredVaultURL.path
        )

        let records = WorkspacePathDetector(homeDirectoryURL: homeURL)
            .detectPathRecords(now: baseDate)

        let vault = try XCTUnwrap(records.first { $0.kind == .obsidianVault })
        XCTAssertEqual(vault.status, .permissionRequired)
    }

    func testConfiguredZoteroDatabaseReportsPermissionRequiredWhenUnreadable() throws {
        let homeURL = try makeTemporaryHome()
        let dataDirectoryURL = homeURL.appendingPathComponent("Library/Zotero Data", isDirectory: true)
        try makeZoteroDataDirectory(at: dataDirectoryURL)
        let databaseURL = dataDirectoryURL.appendingPathComponent("zotero.sqlite")
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: databaseURL.path
            )
        }
        let prefsURL = homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Zotero", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("abc.default", isDirectory: true)
            .appendingPathComponent("prefs.js")
        try FileManager.default.createDirectory(
            at: prefsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        user_pref("extensions.zotero.dataDir", "\(dataDirectoryURL.path)");
        """.write(to: prefsURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: databaseURL.path
        )

        let records = WorkspacePathDetector(homeDirectoryURL: homeURL)
            .detectPathRecords(now: baseDate)

        let zotero = try XCTUnwrap(records.first { $0.kind == .zoteroLibrary })
        XCTAssertEqual(zotero.status, .permissionRequired)
    }

    private func makeTemporaryHome(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let homeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePathDetectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: homeURL)
        }
        return homeURL
    }

    private func makeObsidianVault(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func makeZoteroDataDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data().write(to: url.appendingPathComponent("zotero.sqlite"))
    }
}
