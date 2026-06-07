import Foundation
import XCTest
import BilinRenderKit
import BilinWorkspaceKit
@testable import BilinMacApp

final class WorkbenchUIAffordanceTests: XCTestCase {
    func testMacAppDoesNotShipPermanentDisabledPlaceholderControls() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let emptyButtonPattern = try NSRegularExpression(pattern: #"Button\s*\{\s*\}"#)
        var violations: [String] = []

        for fileURL in try swiftFiles(in: sourceRoot) {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(
                of: sourceRoot.deletingLastPathComponent().path + "/",
                with: ""
            )
            if text.contains(".disabled(true)") {
                violations.append("\(relativePath) contains .disabled(true)")
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if emptyButtonPattern.firstMatch(in: text, range: range) != nil {
                violations.append("\(relativePath) contains an empty Button action")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Replace permanent placeholder controls with status text or a real action:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testDetectedWorkspacePathUseLabelsNameTheirTarget() {
        XCTAssertEqual(
            WorkspacePathCommandLabels.useDetectedTitle(for: .bilinLibrary),
            "Use Bilin Library"
        )
        XCTAssertEqual(
            WorkspacePathCommandLabels.useDetectedTitle(for: .zoteroLibrary),
            "Use Zotero Library"
        )
        XCTAssertEqual(
            WorkspacePathCommandLabels.useDetectedTitle(for: .obsidianVault),
            "Use Obsidian Vault"
        )
        XCTAssertEqual(
            WorkspacePathCommandLabels.useDetectedTitle(for: .writingProjectRoot),
            "Use Writing Project"
        )
    }

    func testMacAppDoesNotUseAmbiguousUseLabels() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let weakLabelPatterns = [
            try NSRegularExpression(pattern: #"Label\("Use""#),
            try NSRegularExpression(pattern: #"Button\("Use""#),
            try NSRegularExpression(pattern: #"Label\("Use Detected""#),
            try NSRegularExpression(pattern: #"Button\("Use Detected""#)
        ]
        var violations: [String] = []

        for fileURL in try swiftFiles(in: sourceRoot) {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if weakLabelPatterns.contains(where: { $0.firstMatch(in: text, range: range) != nil }) {
                let relativePath = fileURL.path.replacingOccurrences(
                    of: sourceRoot.deletingLastPathComponent().path + "/",
                    with: ""
                )
                violations.append("\(relativePath) uses an ambiguous Use label")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Use buttons must name their target:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testWorkspaceSettingsCanForgetConfiguredLocationsWithoutDeletingFiles() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let settingsSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkspaceSettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            settingsSource.contains("Button(role: .destructive)"),
            "Forgetting an external location should use a standard destructive settings affordance."
        )
        XCTAssertTrue(
            settingsSource.contains("Label(\"Forget Location\", systemImage: \"minus.circle\")"),
            "Configured external locations need an explicit Forget Location command."
        )
        XCTAssertTrue(
            settingsSource.contains("defaults.forgetWorkspacePath(record)"),
            "Forget Location should clear the persisted Bilin configuration instead of only hiding the row."
        )
        XCTAssertTrue(
            settingsSource.contains("without deleting any local files"),
            "The destructive action help should make clear that external user files are not deleted."
        )
    }

    func testSelectablePathTextDoesNotStealActionHitTargets() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let settingsSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkspaceSettingsView.swift"),
            encoding: .utf8
        )
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            settingsSource.contains("WorkspaceSelectablePathText(path: record.path)")
                && settingsSource.contains("WorkspaceSelectablePathText(path: detectedSuggestion.path)"),
            "Workspace settings rows should route long selectable paths through a constrained path text component."
        )
        XCTAssertTrue(
            settingsSource.contains("private struct WorkspaceSelectablePathText")
                && settingsSource.contains(".frame(maxWidth: .infinity, alignment: .leading)")
                && settingsSource.contains(".layoutPriority(-1)")
                && settingsSource.contains(".accessibilityLabel(path)"),
            "Selectable workspace paths should truncate and yield layout space before trailing action buttons."
        )
        XCTAssertTrue(
            workbenchSource.contains("ZoteroAttachmentPathText(path: displayPath)")
                && workbenchSource.contains("private struct ZoteroAttachmentPathText"),
            "Zotero attachment rows should constrain selectable paths before rendering file action buttons."
        )
        XCTAssertTrue(
            workbenchSource.contains(".controlSize(.small)\n                .fixedSize()"),
            "Zotero attachment action buttons should keep intrinsic hit targets when long paths are selectable."
        )
    }

    func testEquationEditorClearCommandNamesItsTarget() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let weakClearPatterns = [
            try NSRegularExpression(pattern: #"Label\("Clear""#),
            try NSRegularExpression(pattern: #"Button\("Clear""#)
        ]
        var violations: [String] = []

        for fileURL in try swiftFiles(in: sourceRoot) {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if weakClearPatterns.contains(where: { $0.firstMatch(in: text, range: range) != nil }) {
                let relativePath = fileURL.path.replacingOccurrences(
                    of: sourceRoot.deletingLastPathComponent().path + "/",
                    with: ""
                )
                violations.append("\(relativePath) uses a targetless Clear command")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Clear commands must say what they clear:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testReaderMenuExposesSemanticCopyCommands() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let appSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("BilinMacApp.swift"),
            encoding: .utf8
        )
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            appSource.contains("Button(\"Copy Reader Selection as Markdown\")"),
            "The Reader menu should expose selected text copy, not only block context menus."
        )
        XCTAssertTrue(
            appSource.contains(".keyboardShortcut(\"c\", modifiers: [.command, .option])"),
            "Reader selection copy should have a stable macOS keyboard shortcut."
        )
        XCTAssertTrue(
            appSource.contains("ReaderClipboard.copy(text)"),
            "The command should copy the semantic selected reader text already produced by the reader."
        )
        XCTAssertTrue(
            appSource.contains("Button(\"Copy Selected Block Markdown\")"),
            "The Reader menu should expose block-level semantic Markdown copy."
        )
        XCTAssertTrue(
            appSource.contains("ReaderBlockClipboardPayload.sourceText(for: block)"),
            "Block copy should use the same semantic formatter as the context menu."
        )
        XCTAssertFalse(
            workbenchSource.contains("private enum ReaderClipboard"),
            "ReaderClipboard must be visible to menu commands and reader context menus inside the app module."
        )
    }

    func testReaderToolRailAndModePersistPerScene() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let appSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("BilinMacApp.swift"),
            encoding: .utf8
        )
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )
        let inspectorSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("ResearchWorkbenchInspectorPane.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            workbenchSource.contains(#"@SceneStorage("bilin.reader.inspectorPresented")"#),
            "The reader tool rail should persist per scene so hiding it does not reset the workspace."
        )
        XCTAssertFalse(
            workbenchSource.contains("@State private var inspectorPresented"),
            "The reader tool rail should not be a transient @State value."
        )
        XCTAssertTrue(
            workbenchSource.contains(#"@SceneStorage("bilin.researchWorkbench.selectedMode")"#),
            "Note Bridge, Research Plan, and Writing Dock mode should survive inspector rebuilds."
        )
        XCTAssertTrue(
            inspectorSource.contains("ResearchWorkbenchMode(rawValue: selectedModeRawValue) ?? .noteBridge"),
            "Inspector mode restoration should tolerate invalid scene storage values."
        )
        XCTAssertTrue(
            inspectorSource.contains("set: { selectedModeRawValue = $0.rawValue }"),
            "Mode tabs should write the selected mode back to scene storage."
        )
        XCTAssertTrue(
            workbenchSource.contains(".focusedSceneValue(\\.readerInspectorPresented, $inspectorPresented)"),
            "ReaderDetailPane should expose rail visibility to macOS commands through focused scene values."
        )
        XCTAssertTrue(
            workbenchSource.contains(".focusedSceneValue(\\.researchWorkbenchModeRawValue, $researchWorkbenchModeRawValue)"),
            "ReaderDetailPane should expose the current workbench mode to macOS commands."
        )
        XCTAssertTrue(
            appSource.contains("Button(\"Show Note Bridge\")"),
            "The Reader menu should open Note Bridge directly."
        )
        XCTAssertTrue(
            appSource.contains("Button(\"Show Research Plan\")"),
            "The Reader menu should open Research Plan directly."
        )
        XCTAssertTrue(
            appSource.contains("Button(\"Show Writing Dock\")"),
            "The Reader menu should open Writing Dock directly."
        )
        XCTAssertTrue(
            appSource.range(of: "Button(\"Show Note Bridge\")")?.lowerBound ?? appSource.endIndex
                < (appSource.range(of: "Button(\"Copy Reader Selection as Markdown\")")?.lowerBound ?? appSource.startIndex),
            "View-switching commands should appear before clipboard commands in the Reader menu."
        )
        XCTAssertTrue(
            appSource.contains("showResearchWorkbenchMode(.writingDock)"),
            "Mode menu commands should open the rail and set the requested workbench mode."
        )
        assertCommandRevealsModeBeforeRunning(
            appSource,
            commandLabel: "Check Research API",
            modeCall: "showResearchWorkbenchMode(.researchPlan)",
            actionCall: "await session.refreshResearchWorkbench()"
        )
        assertCommandDoesNotRevealResearchWorkbench(appSource, commandLabel: "Open Library...")
        assertCommandDoesNotRevealResearchWorkbench(appSource, commandLabel: "Open Zotero Library...")
        assertCommandDoesNotRevealResearchWorkbench(appSource, commandLabel: "Equation Editor...")
        assertCommandDoesNotRevealResearchWorkbench(appSource, commandLabel: "Copy Reader Selection as Markdown")
        assertCommandDoesNotRevealResearchWorkbench(appSource, commandLabel: "Copy Selected Block Markdown")
        assertCommandRevealsModeBeforeRunning(
            appSource,
            commandLabel: "Prepare Obsidian Note Patch...",
            modeCall: "showResearchWorkbenchMode(.noteBridge)",
            actionCall: "await session.prepareSelectedBlockNoteActionPlan()"
        )
        assertCommandRevealsModeBeforeRunning(
            appSource,
            commandLabel: "Prepare Writing Patch...",
            modeCall: "showResearchWorkbenchMode(.writingDock)",
            actionCall: "await session.prepareSelectedBlockWritingActionPlan()"
        )
        XCTAssertTrue(
            appSource.contains("Button(\"Prepare Reading Outline...\")"),
            "The Reader menu should expose paper-specific reading outline preparation."
        )
        assertCommandRevealsModeBeforeRunning(
            appSource,
            commandLabel: "Prepare Reading Outline...",
            modeCall: "showResearchWorkbenchMode(.researchPlan)",
            actionCall: "await session.prepareSelectedArticleReadingOutlineActionPlan()"
        )
        XCTAssertTrue(
            appSource.contains("canPrepareSelectedArticleReadingOutlineActionPlan"),
            "The reading outline menu command should share the same readiness contract as the Research Plan rail."
        )
        XCTAssertTrue(
            appSource.contains("guard let session else { return false }"),
            "Mode menu commands should be disabled when no reader scene is focused."
        )
        XCTAssertTrue(
            appSource.contains("session.selectedZoteroItem != nil")
                && appSource.contains("session.selectedArticle != nil")
                && appSource.contains("!session.blocks.isEmpty"),
            "Mode menu commands should enable for a Bilin paper or Zotero metadata item so Research Plan and import actions stay reachable."
        )
    }

    func testNoteBridgeOffersDetectedObsidianVaultInline() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let inspectorSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("ResearchWorkbenchInspectorPane.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            inspectorSource.contains("var uniqueAvailableDetectedObsidianVault: WorkspacePathRecord?"),
            "Note Bridge should compute a single safe Obsidian vault candidate instead of guessing among multiple vaults."
        )
        XCTAssertTrue(
            inspectorSource.contains("record.kind == .obsidianVault"),
            "The inline detected location shortcut should be scoped to Obsidian vaults for Note Bridge."
        )
        XCTAssertTrue(
            inspectorSource.contains("Detected Obsidian vault"),
            "Note Bridge should show the detected vault path where the user is preparing the note patch."
        )
        XCTAssertTrue(
            inspectorSource.contains("await snapshot.useDetectedWorkspacePath(detectedVault)"),
            "The inline vault shortcut should still route through the explicit confirmed workspace path action."
        )
        XCTAssertTrue(
            inspectorSource.contains("WorkspacePathCommandLabels.useDetectedTitle(for: detectedVault.kind)"),
            "The inline vault shortcut should use the same target-specific label contract as settings and startup."
        )
    }

    func testWritingDockDoesNotHideHardCodedRelatedWorkTarget() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let inspectorSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("ResearchWorkbenchInspectorPane.swift"),
            encoding: .utf8
        )
        let sessionActionsSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("ReaderWorkbenchSession+ResearchActions.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            inspectorSource.contains("targetSectionPreference: \"Related Work\""),
            "Writing Dock preview should derive its target section from the linked manuscript, not a hidden Related Work default."
        )
        XCTAssertFalse(
            sessionActionsSource.contains("targetSectionPreference: \"Related Work\""),
            "Prepared Writing Dock action plans should not silently hard-code Related Work."
        )
        XCTAssertTrue(
            inspectorSource.contains("Picker(\"Target section\", selection: writingTargetSectionBinding)"),
            "Writing Dock should let the user choose the section target that will be used for the prepared manuscript patch."
        )
        XCTAssertTrue(
            inspectorSource.contains("snapshot.selectWritingTargetSection($0)"),
            "Writing Dock target section changes should update the session before preparing the manuscript patch."
        )
        XCTAssertTrue(
            sessionActionsSource.contains("WritingTargetSectionResolver.targetPreference(")
                && sessionActionsSource.contains("selectedTitle: selectedWritingTargetSection"),
            "Writing Dock action plans should share the same user-selected target-section resolver as the preview."
        )
    }

    private func assertCommandDoesNotRevealResearchWorkbench(
        _ source: String,
        commandLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let commandSource = commandBodySource(source, commandLabel: commandLabel) else {
            XCTFail("Missing Reader menu command \(commandLabel)", file: file, line: line)
            return
        }
        XCTAssertFalse(
            commandSource.contains("showResearchWorkbenchMode("),
            "\(commandLabel) should keep its native macOS behavior without forcing Research Workbench navigation.",
            file: file,
            line: line
        )
    }

    private func assertCommandRevealsModeBeforeRunning(
        _ source: String,
        commandLabel: String,
        modeCall: String,
        actionCall: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let commandSource = commandBodySource(source, commandLabel: commandLabel) else {
            XCTFail("Missing Reader menu command \(commandLabel)", file: file, line: line)
            return
        }
        guard let modeRange = commandSource.range(of: modeCall) else {
            XCTFail("\(commandLabel) should reveal the corresponding research workbench mode.", file: file, line: line)
            return
        }
        guard let actionRange = commandSource.range(of: actionCall) else {
            XCTFail("\(commandLabel) should run its corresponding workbench action.", file: file, line: line)
            return
        }
        XCTAssertLessThan(
            modeRange.lowerBound,
            actionRange.lowerBound,
            "\(commandLabel) should reveal its workbench mode before running the action.",
            file: file,
            line: line
        )
    }

    private func commandBodySource(_ source: String, commandLabel: String) -> Substring? {
        guard let commandRange = source.range(of: "Button(\"\(commandLabel)\")") else {
            return nil
        }
        let commandSource = source[commandRange.lowerBound...]
        let nextButton = commandSource
            .dropFirst()
            .range(of: "\n            Button(")?
            .lowerBound
        let nextDivider = commandSource
            .dropFirst()
            .range(of: "\n            Divider()")?
            .lowerBound
        let end = [nextButton, nextDivider].compactMap { $0 }.min() ?? commandSource.endIndex
        return commandSource[..<end]
    }

    func testLibraryItemRowsDoNotNestSelectionInsideButtons() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )
        let nestedSelectionButtonPattern = try NSRegularExpression(
            pattern: #"Button\s*\{\s*session\.requestLibraryItemSelection\(selection\)"#
        )
        let range = NSRange(workbenchSource.startIndex..<workbenchSource.endIndex, in: workbenchSource)

        XCTAssertNil(
            nestedSelectionButtonPattern.firstMatch(in: workbenchSource, range: range),
            "Article and Zotero rows should be standard selectable List rows. Nesting selection in Button makes macOS row hit testing unreliable."
        )
    }

    func testLibraryItemRowsHavePointerActivationWithoutNestedButtons() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )
        let rowPointerActivationPattern = try NSRegularExpression(
            pattern: #"(?s)\.simultaneousGesture\(\s*TapGesture\(\)\.onEnded\s*\{\s*session\.requestLibraryItemSelection\(selection\)"#
        )
        let range = NSRange(workbenchSource.startIndex..<workbenchSource.endIndex, in: workbenchSource)
        let matches = rowPointerActivationPattern.matches(in: workbenchSource, range: range)

        XCTAssertEqual(
            matches.count,
            2,
            "Article and Zotero rows should keep List(selection:) for keyboard selection while also providing explicit pointer activation for custom rows."
        )
    }

    func testLibraryItemRowsUseOptionalSelectionTags() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )
        let nonOptionalSelectionTagPattern = try NSRegularExpression(
            pattern: #"(?m)\.tag\(selection\)"#
        )
        let optionalSelectionTagPattern = try NSRegularExpression(
            pattern: #"(?m)\.tag\(Optional\(selection\)\)"#
        )
        let range = NSRange(workbenchSource.startIndex..<workbenchSource.endIndex, in: workbenchSource)

        XCTAssertNil(
            nonOptionalSelectionTagPattern.firstMatch(in: workbenchSource, range: range),
            "Article and Zotero rows use a Binding<ReaderLibrarySelection?>. Their tags should be optional to keep macOS List(selection:) hit testing stable."
        )
        XCTAssertEqual(
            optionalSelectionTagPattern.matches(in: workbenchSource, range: range).count,
            2
        )
    }

    func testEquationTemplateSymbolsUseImmediateFallbackPreviews() throws {
        let groups = Dictionary(
            uniqueKeysWithValues: EquationTemplateCatalog.groups.map { ($0.id, $0.templates) }
        )
        let greekAlpha = try XCTUnwrap(groups["greek"]?.first { $0.id == "alpha" })
        let operatorTimes = try XCTUnwrap(groups["operators"]?.first { $0.id == "times" })
        let matrix = try XCTUnwrap(groups["matrices"]?.first { $0.id == "pmatrix2" })
        let fraction = try XCTUnwrap(groups["structure"]?.first { $0.id == "frac" })

        XCTAssertTrue(EquationTemplatePreviewPolicy.prefersTypographicFallback(greekAlpha))
        XCTAssertTrue(EquationTemplatePreviewPolicy.prefersTypographicFallback(operatorTimes))
        XCTAssertTrue(EquationTemplatePreviewPolicy.prefersTypographicFallback(matrix))
        XCTAssertFalse(EquationTemplatePreviewPolicy.shouldRenderPreview(greekAlpha))
        XCTAssertFalse(EquationTemplatePreviewPolicy.shouldRenderPreview(operatorTimes))
        XCTAssertFalse(EquationTemplatePreviewPolicy.shouldRenderPreview(matrix))
        XCTAssertTrue(EquationTemplatePreviewPolicy.shouldRenderPreview(fraction))
    }

    func testMacAppDoesNotShipFutureDisabledWorkflowCopy() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let forbiddenPhrases = [
            "stay disabled until",
            "disabled until they can be prepared"
        ]
        var violations: [String] = []

        for fileURL in try swiftFiles(in: sourceRoot) {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(
                of: sourceRoot.deletingLastPathComponent().path + "/",
                with: ""
            )
            let lowercased = text.lowercased()
            for phrase in forbiddenPhrases where lowercased.contains(phrase) {
                violations.append("\(relativePath) contains future-disabled workflow copy: \(phrase)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Replace future-disabled workflow copy with a real action or a concrete current-state explanation:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testReaderLoadFailureStateOffersRetryAction() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            workbenchSource.contains("Label(\"Retry Paper\", systemImage: \"arrow.clockwise\")"),
            "Reader load failures should offer a concrete retry action."
        )
        XCTAssertTrue(
            workbenchSource.contains("session.requestLibraryItemSelection(session.selectedLibraryItem)"),
            "Retry Paper should reuse the selected library item instead of asking users to reselect it."
        )
    }

    func testLibraryOpeningStateOffersDetectedStartupLocationConfirmation() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            workbenchSource.contains("private var detectedStartupLocations: [WorkspacePathRecord]"),
            "The empty library state should surface detected startup paths as explicit candidates."
        )
        XCTAssertTrue(
            workbenchSource.contains("uniqueAvailableDetectedWorkspacePath(kind: .zoteroLibrary)"),
            "Detected Zotero startup should only offer a one-click path when there is exactly one available candidate."
        )
        XCTAssertTrue(
            workbenchSource.contains("uniqueAvailableDetectedWorkspacePath(kind: .obsidianVault)"),
            "First setup should also surface a unique detected Obsidian vault for Note Bridge configuration."
        )
        XCTAssertTrue(
            workbenchSource.contains("WorkspacePathCommandLabels.useDetectedTitle(for: record.kind)"),
            "Detected startup actions should use the same target-specific label contract as settings."
        )
        XCTAssertTrue(
            workbenchSource.contains("await session.useDetectedWorkspacePath(record)"),
            "Detected startup actions must route through the session confirmation path."
        )
        XCTAssertTrue(
            workbenchSource.contains("Use it only if this is the Obsidian vault for Note Bridge patches."),
            "The user should see which local Obsidian candidate is being offered before using it."
        )
        XCTAssertTrue(
            workbenchSource.contains("ViewThatFits(in: .horizontal)"),
            "Multiple detected startup actions should have a compact horizontal layout with a narrower fallback."
        )
    }

    func testRenderedEquationBlocksRemainHitTestableForCopyAndSelection() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )
        let svgEquationBranchPattern = try NSRegularExpression(
            pattern: #"(?s)case \.svg\(let svg\):\s*SVGImageView\([\s\S]*?Label\("Copy LaTeX", systemImage: "doc\.on\.doc"\)[\s\S]*?\.help"#
        )
        let range = NSRange(workbenchSource.startIndex..<workbenchSource.endIndex, in: workbenchSource)
        guard
            let match = svgEquationBranchPattern.firstMatch(in: workbenchSource, range: range),
            let matchRange = Range(match.range, in: workbenchSource)
        else {
            return XCTFail("Rendered equation blocks should have an SVG branch with a local context menu.")
        }

        let branch = String(workbenchSource[matchRange])
        XCTAssertFalse(
            branch.contains(".allowsHitTesting(false)"),
            "The rendered equation block itself must remain hit-testable so copy and block selection controls keep working after SVG render succeeds."
        )
        XCTAssertTrue(
            branch.contains("Label(\"Copy LaTeX\", systemImage: \"doc.on.doc\")"),
            "Rendered equation blocks should keep a visible copy affordance for LaTeX."
        )
        XCTAssertTrue(
            workbenchSource.contains("private struct SelectableDisplayEquationBlock"),
            "Display equations should have a semantic selection wrapper instead of being a render-only SVG block."
        )
        XCTAssertTrue(
            workbenchSource.contains("SelectableDisplayEquationBlock("),
            "Equation block call sites should route through the selectable display equation wrapper."
        )
        XCTAssertTrue(
            workbenchSource.contains("ReaderSemanticCopyFormatter.displayMathMarkdown(latex: trimmedLatex)"),
            "Clicking a display equation should publish notebook-ready Markdown through the Reader selection pipeline."
        )
    }

    func testReaderToolbarOffersExplicitReloadSelectionAction() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            workbenchSource.contains("session.reloadSelectedLibraryItem()"),
            "Reader toolbar should expose an explicit reload action instead of making repeated list selection reload content."
        )
        XCTAssertTrue(
            workbenchSource.contains("Label(\"Reload Selection\", systemImage: \"arrow.clockwise\")"),
            "The reload action should use a standard macOS refresh affordance."
        )
        XCTAssertTrue(
            workbenchSource.contains(".disabled(!session.canReloadSelectedLibraryItem)"),
            "Reload Selection should be disabled when no selected item can be reloaded."
        )
        XCTAssertTrue(
            workbenchSource.contains("inspectorPresented ? \"Hide Research Tools\" : \"Show Research Tools\""),
            "The research tools toolbar button should name the actual state change instead of using a vague toggle label."
        )
        XCTAssertTrue(
            workbenchSource.contains(".disabled(!canShowResearchTools)"),
            "Research tools should not be clickable on the welcome page where no paper or Zotero item is selected."
        )
        XCTAssertTrue(
            workbenchSource.contains("session.selectedZoteroItem != nil")
                && workbenchSource.contains("session.selectedArticle != nil")
                && workbenchSource.contains("!session.blocks.isEmpty"),
            "Research tools availability should include Zotero metadata because Zotero import and related-paper planning are part of the workbench."
        )
        XCTAssertTrue(
            workbenchSource.contains("ZoteroMetadataDetailPane(item: item)")
                && workbenchSource.contains("ResearchWorkbenchInspectorPane("),
            "Zotero metadata should keep the research tools rail visible instead of becoming an isolated dead-end detail page."
        )
    }

    func testZoteroMetadataStateOffersRecoveryActionsForBlockedImportPlan() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            workbenchSource.contains("Label(\"Open Bilin Library\", systemImage: \"folder\")"),
            "Zotero import readiness should offer an inline Bilin library recovery action."
        )
        XCTAssertTrue(
            workbenchSource.contains("await session.openLibraryFromPanel()"),
            "Open Bilin Library should launch the standard macOS library picker."
        )
        XCTAssertTrue(
            workbenchSource.contains("Label(\"Refresh Research API\", systemImage: \"arrow.clockwise\")"),
            "Zotero import readiness should offer an inline research backend recovery action."
        )
        XCTAssertTrue(
            workbenchSource.contains("await session.refreshResearchWorkbench()"),
            "Refresh Research API should reuse the standard workbench refresh path."
        )
        XCTAssertTrue(
            workbenchSource.contains("ZoteroImportActionPlansSection(actionPlans: zoteroActionPlans)"),
            "Prepared Zotero import action plans should stay visible on the Zotero metadata page."
        )
        XCTAssertTrue(
            workbenchSource.contains("payload[\"zotero_item_id\"] == String(zoteroItemId)"),
            "Zotero metadata should filter action plans to the currently selected Zotero item."
        )
        XCTAssertTrue(
            workbenchSource.contains("await session.approveResearchActionPlan(actionPlan)")
                && workbenchSource.contains("await session.rejectResearchActionPlan(actionPlan)")
                && workbenchSource.contains("await session.applyResearchActionPlan(actionPlan)"),
            "Zotero action plans should be approvable, rejectable, and executable without leaving the metadata page."
        )
        XCTAssertTrue(
            workbenchSource.contains("await session.regenerateResearchActionPlan(actionPlan)")
                && workbenchSource.contains("session.dismissResearchActionPlan(actionPlan)"),
            "Failed Zotero action plans should expose recovery and dismissal on the metadata page."
        )
        XCTAssertTrue(
            workbenchSource.contains("&& !hasOpenActionPlan"),
            "Preparing a Zotero import plan should not keep stacking duplicate open plans for the same item."
        )
    }

    func testZoteroMetadataAttachmentsAreActionableLocalFiles() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BilinMacApp", isDirectory: true)
        let workbenchSource = try String(
            contentsOf: sourceRoot.appendingPathComponent("WorkbenchView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            workbenchSource.contains("ZoteroAttachmentSection(attachments: item.attachments)"),
            "Zotero metadata should render attachment rows, not only newline-joined attachment paths."
        )
        XCTAssertTrue(
            workbenchSource.contains("Label(\"Open Attachment\", systemImage: \"doc.text\")"),
            "Zotero attachment rows should let users open resolved local files."
        )
        XCTAssertTrue(
            workbenchSource.contains("WorkbenchFileActions.open(path: filePath)"),
            "Open Attachment should use the standard macOS workspace open path."
        )
        XCTAssertTrue(
            workbenchSource.contains("Label(\"Show in Finder\", systemImage: \"magnifyingglass\")"),
            "Zotero attachment rows should let users reveal resolved local files in Finder."
        )
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }
}
