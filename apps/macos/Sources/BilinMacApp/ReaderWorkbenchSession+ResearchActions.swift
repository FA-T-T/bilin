import Foundation
import BilinImportKit
import BilinReaderKit
import BilinWorkspaceKit

@MainActor
extension ReaderWorkbenchSession {
    func requestResearchWorkbenchRefresh() {
        researchWorkbenchRefreshTask?.cancel()
        researchWorkbenchRefreshGeneration += 1
        let selectionGeneration = selectionLoadGeneration
        let refreshGeneration = researchWorkbenchRefreshGeneration
        researchWorkbenchRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard
                let self,
                self.isCurrentSelectionGeneration(selectionGeneration),
                self.isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration)
            else { return }
            await self.performResearchWorkbenchRefresh(
                indicatesBusy: false,
                selectionGeneration: selectionGeneration,
                refreshGeneration: refreshGeneration
            )
        }
    }

    func refreshResearchWorkbench(
        indicatesBusy: Bool = true,
        generation: Int? = nil
    ) async {
        researchWorkbenchRefreshTask?.cancel()
        researchWorkbenchRefreshGeneration += 1
        let selectionGeneration = generation ?? selectionLoadGeneration
        let refreshGeneration = researchWorkbenchRefreshGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performResearchWorkbenchRefresh(
                indicatesBusy: indicatesBusy,
                selectionGeneration: selectionGeneration,
                refreshGeneration: refreshGeneration
            )
        }
        researchWorkbenchRefreshTask = task
        await task.value
    }

    private func performResearchWorkbenchRefresh(
        indicatesBusy: Bool,
        selectionGeneration: Int,
        refreshGeneration: Int
    ) async {
        guard
            isCurrentSelectionGeneration(selectionGeneration),
            isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration),
            !Task.isCancelled
        else { return }

        if indicatesBusy {
            researchAPIBusy = true
            researchAPIStatus = "Checking API"
            researchAPIError = nil
        } else {
            researchAPIStatus = "Checking API"
            researchAPIError = nil
        }
        defer {
            if indicatesBusy, isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration) {
                researchAPIBusy = false
            }
        }

        do {
            let health = try await researchAPIClient.health()
            guard
                isCurrentSelectionGeneration(selectionGeneration),
                isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration),
                !Task.isCancelled
            else { return }
            researchAPIHealth = health
            researchAPIStatus = "API connected"
            researchAPIError = nil
        } catch is CancellationError {
            return
        } catch {
            guard
                isCurrentSelectionGeneration(selectionGeneration),
                isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration),
                !Task.isCancelled
            else { return }
            researchAPIHealth = nil
            researchPlans = []
            researchActionPlans = []
            researchAPIStatus = "API unavailable"
            researchAPIError = error.localizedDescription
            researchWorkbenchStatus = "Backend unavailable"
            researchWorkbenchError = "The research backend at \(researchAPIClient.baseURL.absoluteString) is not reachable."
            return
        }

        guard let libraryId = selectedLibraryId else {
            researchPlans = []
            researchActionPlans = []
            if let recovery = configuredBilinLibraryRecovery {
                researchWorkbenchStatus = "Library needs attention"
                researchWorkbenchError = recovery.message
            } else {
                researchWorkbenchStatus = "No library"
                researchWorkbenchError = nil
            }
            return
        }

        do {
            let skills = try await researchAPIClient.listResearchSkills()
            guard
                isCurrentSelectionGeneration(selectionGeneration),
                isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration),
                !Task.isCancelled
            else { return }
            let backendLibraryId = try await backendResearchLibraryId(
                identifier: libraryId,
                path: selectedLibrary?.path
            )
            guard
                isCurrentSelectionGeneration(selectionGeneration),
                isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration),
                !Task.isCancelled
            else { return }
            let articleRevisionId = selectedBlock?.articleRevisionId ?? selectedArticle?.activeRevisionId ?? activeRevisionId
            let researchPlans = try await researchAPIClient.listResearchPlans(
                libraryId: backendLibraryId,
                articleRevisionId: articleRevisionId,
                kind: .paperReading
            )
            guard
                isCurrentSelectionGeneration(selectionGeneration),
                isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration),
                !Task.isCancelled
            else { return }
            let actionPlans = try await researchAPIClient.listAgentActionPlans(
                libraryId: backendLibraryId,
                articleRevisionId: articleRevisionId
            )
            guard
                isCurrentSelectionGeneration(selectionGeneration),
                isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration),
                !Task.isCancelled
            else { return }
            researchSkills = skills
            self.researchPlans = researchPlans
            researchActionPlans = actionPlansFilteredForCurrentSelection(actionPlans)
            researchWorkbenchStatus = "Workbench ready"
            researchWorkbenchError = nil
        } catch is CancellationError {
            return
        } catch {
            guard
                isCurrentSelectionGeneration(selectionGeneration),
                isCurrentResearchWorkbenchRefreshGeneration(refreshGeneration),
                !Task.isCancelled
            else { return }
            researchWorkbenchStatus = "Workbench unavailable"
            researchWorkbenchError = error.localizedDescription
        }
    }

    private func isCurrentResearchWorkbenchRefreshGeneration(_ generation: Int) -> Bool {
        generation == researchWorkbenchRefreshGeneration
    }

    func indexLocalResearchSkills() async {
        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        do {
            researchSkills = try await researchAPIClient.indexLocalResearchSkills()
            researchWorkbenchStatus = "Skills indexed"
            researchWorkbenchError = nil
        } catch {
            researchWorkbenchStatus = "Skill index failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    func enableResearchSkill(_ skill: ResearchSkill) async {
        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        do {
            let enabledSkill = try await researchAPIClient.enableResearchSkill(
                skillIdentifier: skill.slug,
                expectedDigest: skill.digest,
                grantedPermissions: skill.permissions
            )
            mergeResearchSkill(enabledSkill)
            researchWorkbenchStatus = "Skill enabled"
            researchWorkbenchError = nil
        } catch {
            researchWorkbenchStatus = "Skill enable failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    private func mergeResearchSkill(_ skill: ResearchSkill) {
        if let index = researchSkills.firstIndex(where: { $0.id == skill.id || $0.slug == skill.slug }) {
            researchSkills[index] = skill
        } else {
            researchSkills.append(skill)
            researchSkills.sort { $0.slug < $1.slug }
        }
    }

    private func rejectIfResearchActionBusy() -> Bool {
        guard !researchAPIBusy else {
            researchWorkbenchStatus = "Research action busy"
            researchWorkbenchError = "Another research action is already running. Wait for it to finish before starting a new one."
            return false
        }
        return true
    }

    private func beginResearchActionIfIdle() -> Bool {
        guard rejectIfResearchActionBusy() else { return false }
        researchAPIBusy = true
        return true
    }

    private func finishResearchAction() {
        researchAPIBusy = false
    }

    func prepareSelectedBlockNoteActionPlan(recoveringFrom actionPlan: AgentActionPlan? = nil) async {
        flushPendingReaderTextSelection()
        guard let libraryId = selectedLibraryId, let block = selectedBlock else { return }
        let selectionGeneration = selectionLoadGeneration
        let title = selectedArticle?.title ?? "Untitled Paper"
        let vaultPath = workspaceDefaults.workspaceConfiguration.selectedObsidianVault?.path
        let targetNote = "Papers/\(NoteActionPlanBuilder.noteFileName(for: title)).md"
        let targetPath = vaultPath.map { ($0 as NSString).appendingPathComponent(targetNote) }
        let targetBaseFileHash = targetPath.map { baseFileHash(at: $0) }
        let sourceMarkdown = selectedReaderText ?? semanticSourceMarkdown(for: block)
        let selectedTextHash = selectedReaderTextHash
        let recoveryContext = actionPlan.map {
            ActionPlanRecoveryContextBuilder().build(
                from: $0,
                configuration: workspaceDefaults.workspaceConfiguration
            )
        }
        guard validateRecoveryContext(
            recoveryContext,
            currentTargetPath: targetPath,
            currentBaseFileHash: targetBaseFileHash
        ) else {
            return
        }
        let draft = NoteActionPlanBuilder().build(
            articleTitle: title,
            articleRevisionId: block.articleRevisionId,
            blockUid: block.blockUid,
            sourceMarkdown: sourceMarkdown,
            translationMarkdown: selectedBlockTranslation?.rawMarkdown,
            selectedTextHash: selectedTextHash,
            vaultPath: vaultPath,
            baseFileHash: targetBaseFileHash,
            recoveryContext: recoveryContext
        )

        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        do {
            let backendLibraryId = try await backendResearchLibraryId(
                identifier: libraryId,
                path: selectedLibrary?.path
            )
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            let actionPlan = try await researchAPIClient.createAgentActionPlan(
                libraryId: backendLibraryId,
                draft: draft.actionPlanDraft
            )
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            mergeResearchActionPlan(actionPlan)
            researchWorkbenchStatus = recoveryContext == nil ? "Action plan prepared" : "Recovery patch prepared"
            researchWorkbenchError = nil
        } catch {
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            researchWorkbenchStatus = "Action plan failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    func prepareSelectedBlockWritingActionPlan(recoveringFrom actionPlan: AgentActionPlan? = nil) async {
        flushPendingReaderTextSelection()
        guard
            let libraryId = selectedLibraryId,
            let block = selectedBlock,
            let writingRoot = workspaceDefaults.workspaceConfiguration.writingProjectRoots.first
        else { return }
        let selectionGeneration = selectionLoadGeneration
        let locator = WritingProjectLocator()
        let location = locator.locate(rootPath: writingRoot.path)
        guard let mainFilePath = location.mainFilePath else {
            researchWorkbenchStatus = "Needs main file"
            researchWorkbenchError = "Choose a writing project that contains a main Typst or TeX file."
            return
        }
        guard let mainFileText = locator.mainFileText(for: location) else {
            researchWorkbenchStatus = "Cannot read main file"
            researchWorkbenchError = "Bilin could not read \(mainFilePath)."
            return
        }
        let baseFileHash = LocalFilePatchExecutor.contentHash(for: mainFileText)
        let sourceBlock = selectedReaderText ?? semanticWritingSource(for: block)
        let selectedTextHash = selectedReaderTextHash
        let recoveryContext = actionPlan.map {
            ActionPlanRecoveryContextBuilder().build(
                from: $0,
                configuration: workspaceDefaults.workspaceConfiguration
            )
        }
        guard validateRecoveryContext(
            recoveryContext,
            currentTargetPath: mainFilePath,
            currentBaseFileHash: baseFileHash
        ) else {
            return
        }
        let draft = WritingActionPlanBuilder().build(
            mainFileText: mainFileText,
            targetPath: mainFilePath,
            sourceBlock: sourceBlock,
            articleRevisionId: block.articleRevisionId,
            blockUid: block.blockUid,
            baseFileHash: baseFileHash,
            targetSectionPreference: WritingTargetSectionResolver.targetPreference(
                for: location,
                selectedTitle: selectedWritingTargetSection
            ),
            selectedTextHash: selectedTextHash,
            recoveryContext: recoveryContext
        )

        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        do {
            let backendLibraryId = try await backendResearchLibraryId(
                identifier: libraryId,
                path: selectedLibrary?.path
            )
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            let actionPlan = try await researchAPIClient.createAgentActionPlan(
                libraryId: backendLibraryId,
                draft: draft.actionPlanDraft
            )
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            mergeResearchActionPlan(actionPlan)
            researchWorkbenchStatus = recoveryContext == nil ? "Writing patch prepared" : "Recovery writing patch prepared"
            researchWorkbenchError = nil
        } catch {
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            researchWorkbenchStatus = "Writing patch failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    func prepareSelectedZoteroImportActionPlan(recoveringFrom _: AgentActionPlan? = nil) async {
        guard let item = selectedZoteroItem else {
            researchWorkbenchStatus = "No Zotero item"
            researchWorkbenchError = "Select a Zotero item before preparing an import action plan."
            return
        }
        let selectionGeneration = selectionLoadGeneration
        guard let libraryId = selectedLibraryId else {
            researchWorkbenchStatus = "Bilin library required"
            researchWorkbenchError = "Open a Bilin library before preparing a Zotero import action plan."
            return
        }
        guard isResearchAPIReady else {
            researchWorkbenchStatus = "Backend unavailable"
            researchWorkbenchError = "Connect the research backend before preparing a Zotero import action plan."
            return
        }

        let draft = ZoteroImportActionPlanBuilder().build(
            candidate: zoteroImportCandidate(from: item),
            localLibraryId: libraryId,
            localLibraryPath: selectedLibrary?.path,
            zoteroLibraryPath: workspaceDefaults.workspaceConfiguration.selectedZoteroLibrary?.path
        )

        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        do {
            let backendLibraryId = try await backendResearchLibraryId(
                identifier: libraryId,
                path: selectedLibrary?.path
            )
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            let actionPlan = try await researchAPIClient.createAgentActionPlan(
                libraryId: backendLibraryId,
                draft: draft.actionPlanDraft
            )
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            mergeResearchActionPlan(actionPlan)
            researchWorkbenchStatus = actionPlan.kind == .downloadPaper
                ? "Zotero download action prepared"
                : "Zotero import action prepared"
            researchWorkbenchError = nil
        } catch {
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            researchWorkbenchStatus = "Zotero import action failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    func prepareSelectedArticleReadingOutlineActionPlan() async {
        guard let libraryId = selectedLibraryId, let article = selectedArticle else { return }
        let selectionGeneration = selectionLoadGeneration
        guard validateReadingOutlineSkillReadiness() else { return }
        let revisionId = selectedBlock?.articleRevisionId ?? article.activeRevisionId
        let selectedBlock = selectedBlock
        let visibleBlocks = visibleReadingOutlineBlocks()
        let payload = readingOutlinePayload(
            article: article,
            articleRevisionId: revisionId,
            selectedBlock: selectedBlock,
            visibleBlocks: visibleBlocks
        )
        let candidatePaper = readingOutlineCandidatePaper(
            article: article,
            articleRevisionId: revisionId
        )
        let idempotencySeed = [
            article.id,
            revisionId,
            selectedBlock?.blockUid ?? "no-selected-block",
            visibleBlocks.map { $0.contentHash }.joined(separator: ":")
        ].joined(separator: "|")
        let request = ResearchPlanGenerationRequest(
            title: "Generate reading outline: \(article.title)",
            kind: .paperReading,
            topic: article.title,
            articleRevisionId: revisionId,
            skillSlug: "paper-outline",
            candidatePapers: [candidatePaper],
            idempotencyKey: "reading-outline-\(LocalFilePatchExecutor.contentHash(for: idempotencySeed).prefix(16))",
            payload: payload
        )

        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        do {
            let backendLibraryId = try await backendResearchLibraryId(
                identifier: libraryId,
                path: selectedLibrary?.path
            )
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            let actionPlan = try await researchAPIClient.generateResearchPlanActionPlan(
                libraryId: backendLibraryId,
                request: request
            )
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            mergeResearchActionPlan(actionPlan)
            researchWorkbenchStatus = "Reading outline action prepared"
            researchWorkbenchError = nil
        } catch {
            guard isCurrentSelectionGeneration(selectionGeneration) else { return }
            researchWorkbenchStatus = "Reading outline action failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    func approveResearchActionPlan(_ actionPlan: AgentActionPlan) async {
        guard let libraryId = selectedLibraryId else { return }
        await transitionResearchActionPlan(actionPlan) {
            try await actionPlanCoordinator.approve(
                libraryIdentifier: libraryId,
                libraryPath: selectedLibrary?.path,
                actionPlan: actionPlan
            )
        }
    }

    func rejectResearchActionPlan(_ actionPlan: AgentActionPlan) async {
        guard let libraryId = selectedLibraryId else { return }
        await transitionResearchActionPlan(actionPlan) {
            try await actionPlanCoordinator.reject(
                libraryIdentifier: libraryId,
                libraryPath: selectedLibrary?.path,
                actionPlan: actionPlan
            )
        }
    }

    func applyResearchActionPlan(_ actionPlan: AgentActionPlan) async {
        guard let libraryId = selectedLibraryId else { return }
        if actionPlan.kind == .downloadPaper || actionPlan.kind == .importLibrary {
            await applyZoteroImportBundleActionPlan(actionPlan, libraryId: libraryId)
            return
        }
        guard AgentActionPlanLocalExecutionPolicy.supportsLocalApply(actionPlan) else {
            researchWorkbenchStatus = "No local patch"
            researchWorkbenchError = "This action plan does not have a local file patch to apply. Regenerate it, inspect its payload, or dismiss it from the Research Plan rail."
            return
        }

        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        do {
            let outcome = try await actionPlanCoordinator.apply(
                libraryIdentifier: libraryId,
                libraryPath: selectedLibrary?.path,
                actionPlan: actionPlan,
                configuration: workspaceDefaults.workspaceConfiguration
            )
            mergeResearchActionPlans(outcome.actionPlanUpdates)
            switch outcome {
            case .succeeded:
                researchWorkbenchStatus = "Patch applied"
                researchWorkbenchError = nil
            case .failed(_, _, _, let errorMessage):
                researchWorkbenchStatus = "Patch failed"
                researchWorkbenchError = errorMessage
            }
        } catch ResearchActionPlanCoordinatorError.approvalRequired {
            researchWorkbenchStatus = "Approval required"
            researchWorkbenchError = ResearchActionPlanCoordinatorError.approvalRequired.localizedDescription
        } catch {
            researchWorkbenchStatus = "Patch failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    private func applyZoteroImportBundleActionPlan(_ actionPlan: AgentActionPlan, libraryId: String) async {
        guard actionPlan.status == .approved else {
            researchWorkbenchStatus = "Approval required"
            researchWorkbenchError = "Approve the Zotero import action before writing an import bundle."
            return
        }

        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        var backendLibraryId: String?
        var runningActionPlan: AgentActionPlan?

        do {
            let resolvedLibraryId = try await backendResearchLibraryId(
                identifier: libraryId,
                path: selectedLibrary?.path
            )
            backendLibraryId = resolvedLibraryId

            let running = try await researchAPIClient.startAgentActionPlan(
                libraryId: resolvedLibraryId,
                actionPlanId: actionPlan.id,
                payload: [
                    "executor": "macos",
                    "mode": "zotero_import_bundle"
                ]
            )
            runningActionPlan = running
            mergeResearchActionPlan(running)

            let result = try ZoteroImportBundleWriter().write(
                actionPlan: running,
                libraryPath: selectedLibrary?.path ?? actionPlan.payload["local_library_path"]
            )
            let succeeded = try await researchAPIClient.succeedAgentActionPlan(
                libraryId: resolvedLibraryId,
                actionPlanId: actionPlan.id,
                result: result.actionResultPayload
            )
            mergeResearchActionPlan(succeeded)
            researchWorkbenchStatus = "Import bundle written"
            researchWorkbenchError = nil
        } catch {
            if let backendLibraryId, let runningActionPlan {
                if let failed = try? await researchAPIClient.failAgentActionPlan(
                    libraryId: backendLibraryId,
                    actionPlanId: runningActionPlan.id,
                    error: [
                        "code": "zotero_import_bundle_failed",
                        "message": error.localizedDescription
                    ]
                ) {
                    mergeResearchActionPlan(failed)
                }
            }
            researchWorkbenchStatus = "Import bundle failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    func runResearchOutlineActionPlan(_ actionPlan: AgentActionPlan) async {
        guard let libraryId = selectedLibraryId else { return }
        guard AgentActionPlanRemoteExecutionPolicy.supportsRemoteRun(actionPlan) else {
            researchWorkbenchStatus = "Cannot run action"
            researchWorkbenchError = "This action plan type does not have a remote Research Plan execution flow."
            return
        }
        guard actionPlan.status == .approved else {
            researchWorkbenchStatus = "Approval required"
            researchWorkbenchError = "Approve the reading outline action before generating the Research Plan."
            return
        }

        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        var backendLibraryId: String?
        var runningActionPlan: AgentActionPlan?
        var actionDidSucceed = false

        do {
            let resolvedLibraryId = try await backendResearchLibraryId(
                identifier: libraryId,
                path: selectedLibrary?.path
            )
            backendLibraryId = resolvedLibraryId

            let running = try await researchAPIClient.startAgentActionPlan(
                libraryId: resolvedLibraryId,
                actionPlanId: actionPlan.id,
                payload: [
                    "executor": "macos",
                    "mode": "research_outline"
                ]
            )
            runningActionPlan = running
            mergeResearchActionPlan(running)

            let succeeded = try await researchAPIClient.succeedAgentActionPlan(
                libraryId: resolvedLibraryId,
                actionPlanId: actionPlan.id,
                jsonResult: readingOutlineExecutionResult(for: actionPlan)
            )
            actionDidSucceed = true
            mergeResearchActionPlan(succeeded)

            do {
                let articleRevisionId = researchPlanArticleRevisionId(for: actionPlan)
                researchPlans = try await researchAPIClient.listResearchPlans(
                    libraryId: resolvedLibraryId,
                    articleRevisionId: articleRevisionId,
                    kind: .paperReading
                )
                let actionPlans = try await researchAPIClient.listAgentActionPlans(
                    libraryId: resolvedLibraryId,
                    articleRevisionId: articleRevisionId
                )
                researchActionPlans = actionPlansFilteredForCurrentSelection(actionPlans)
                researchWorkbenchStatus = "Reading outline generated"
                researchWorkbenchError = nil
            } catch {
                researchWorkbenchStatus = "Reading outline generated"
                researchWorkbenchError = "The outline action succeeded, but the Research Plan list could not be refreshed: \(error.localizedDescription)"
            }
        } catch {
            if !actionDidSucceed, let backendLibraryId, let runningActionPlan {
                if let failed = try? await researchAPIClient.failAgentActionPlan(
                    libraryId: backendLibraryId,
                    actionPlanId: runningActionPlan.id,
                    error: [
                        "code": "research_outline_failed",
                        "message": error.localizedDescription
                    ]
                ) {
                    mergeResearchActionPlan(failed)
                }
            }
            researchWorkbenchStatus = "Reading outline failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    func regenerateResearchActionPlan(_ actionPlan: AgentActionPlan) async {
        guard rejectIfResearchActionBusy() else { return }

        if let blockUid = actionPlan.payload["block_uid"] {
            guard blocks.contains(where: { $0.blockUid == blockUid }) else {
                researchWorkbenchStatus = "Cannot regenerate"
                researchWorkbenchError = "The source block for this failed action is no longer loaded."
                return
            }
            selectedBlockUid = blockUid
            selectedCitationEntryId = nil
            requestReaderBlockScroll(to: blockUid)
        }

        switch actionPlan.kind {
        case .writeObsidian, .notePatch:
            await prepareSelectedBlockNoteActionPlan(recoveringFrom: actionPlan)
        case .editManuscript, .writingPatch:
            await prepareSelectedBlockWritingActionPlan(recoveringFrom: actionPlan)
        case .generateResearchOutline:
            await prepareSelectedArticleReadingOutlineActionPlan()
        case .downloadPaper, .importLibrary:
            if let zoteroItemId = actionPlan.payload["zotero_item_id"].flatMap(Int64.init),
               zoteroItems.contains(where: { $0.id == zoteroItemId }) {
                selectZoteroItem(id: zoteroItemId)
            }
            await prepareSelectedZoteroImportActionPlan(recoveringFrom: actionPlan)
        case .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .custom:
            researchWorkbenchStatus = "Cannot regenerate"
            researchWorkbenchError = "This action plan type does not have a local patch preparation flow."
        }
    }

    func dismissResearchActionPlan(_ actionPlan: AgentActionPlan) {
        researchActionPlans.removeAll { $0.id == actionPlan.id }
        researchWorkbenchStatus = "Action plan dismissed"
        researchWorkbenchError = nil
    }

    private func transitionResearchActionPlan(
        _ actionPlan: AgentActionPlan,
        operation: () async throws -> AgentActionPlan
    ) async {
        guard beginResearchActionIfIdle() else { return }
        defer { finishResearchAction() }

        do {
            let updated = try await operation()
            mergeResearchActionPlan(updated)
            researchWorkbenchStatus = researchActionStatusLabel(updated.status)
            researchWorkbenchError = nil
        } catch {
            researchWorkbenchStatus = "Action update failed"
            researchWorkbenchError = error.localizedDescription
        }
    }

    private func mergeResearchActionPlan(_ actionPlan: AgentActionPlan) {
        if selectedLibraryItem?.zoteroItemId != nil, !actionPlan.isZoteroImportActionPlan {
            researchActionPlans.removeAll { $0.id == actionPlan.id }
            return
        }
        if let index = researchActionPlans.firstIndex(where: { $0.id == actionPlan.id }) {
            researchActionPlans[index] = actionPlan
        } else {
            researchActionPlans.insert(actionPlan, at: 0)
        }
        researchActionPlans = actionPlansFilteredForCurrentSelection(researchActionPlans)
    }

    private func mergeResearchActionPlans(_ actionPlans: [AgentActionPlan]) {
        for actionPlan in actionPlans {
            mergeResearchActionPlan(actionPlan)
        }
    }

    private func actionPlansFilteredForCurrentSelection(_ actionPlans: [AgentActionPlan]) -> [AgentActionPlan] {
        guard selectedLibraryItem?.zoteroItemId != nil else { return actionPlans }
        return actionPlans.filter(\.isZoteroImportActionPlan)
    }

    private func visibleReadingOutlineBlocks() -> [DocumentBlock] {
        blocks
            .filter { block in
                switch block.blockType {
                case .abstract, .section, .subsection, .paragraph, .equation, .figure, .table:
                    return true
                case .title, .algorithm, .list, .bibliography, .unknown:
                    return false
                }
            }
            .prefix(12)
            .map { $0 }
    }

    private func readingOutlinePayload(
        article: Article,
        articleRevisionId: String?,
        selectedBlock: DocumentBlock?,
        visibleBlocks: [DocumentBlock]
    ) -> ResearchPlanJSONObject {
        let blockObjects: [ResearchPlanJSONValue] = visibleBlocks.map { block in
            .object([
                "id": .string(block.id),
                "block_uid": .string(block.blockUid),
                "block_type": .string(block.blockType.rawValue),
                "structural_path": .string(block.structuralPath),
                "content_hash": .string(block.contentHash),
                "source_markdown": .string(semanticSourceMarkdown(for: block))
            ])
        }
        var payload: ResearchPlanJSONObject = [
            "article_id": .string(article.id),
            "article_title": .string(article.title),
            "article_source": .string(article.source),
            "article_revision_id": articleRevisionId.map(ResearchPlanJSONValue.string) ?? .null,
            "visible_blocks": .array(blockObjects)
        ]
        if !article.externalId.isEmpty {
            payload["article_external_id"] = .string(article.externalId)
        }
        if let selectedBlock {
            payload["selected_block_uid"] = .string(selectedBlock.blockUid)
            payload["selected_block_type"] = .string(selectedBlock.blockType.rawValue)
            payload["selected_block_markdown"] = .string(selectedReaderText ?? semanticSourceMarkdown(for: selectedBlock))
        }
        return payload
    }

    private func readingOutlineCandidatePaper(
        article: Article,
        articleRevisionId: String?
    ) -> ResearchPlanJSONObject {
        var candidate: ResearchPlanJSONObject = [
            "id": .string(article.id),
            "title": .string(article.title),
            "source": .string(article.source),
            "article_revision_id": articleRevisionId.map(ResearchPlanJSONValue.string) ?? .null
        ]
        if !article.externalId.isEmpty {
            candidate["external_id"] = .string(article.externalId)
        }
        return candidate
    }

    private func backendResearchLibraryId(identifier: String, path: String?) async throws -> String {
        try await researchAPIClient.resolveLibraryId(identifier: identifier, path: path)
    }

    private func zoteroImportCandidate(from item: ZoteroItem) -> ZoteroImportCandidate {
        ZoteroImportCandidate(
            itemID: String(item.id),
            key: item.key,
            itemType: item.itemType,
            title: item.title ?? item.key,
            abstract: item.abstractNote,
            doi: item.doi,
            url: item.url,
            arxivIdentifier: item.arxiv?.identifier,
            arxivVersion: item.arxiv?.version,
            creators: item.creators.map(\.displayName),
            collections: item.collections.map(\.name),
            tags: item.tags,
            attachments: item.attachments.map { attachment in
                ZoteroImportAttachmentCandidate(
                    key: attachment.key,
                    contentType: attachment.contentType,
                    path: attachment.path,
                    resolvedFilePath: attachment.resolvedFileURL?.path
                )
            }
        )
    }

    private func researchPlanArticleRevisionId(for actionPlan: AgentActionPlan) -> String? {
        actionPlan.payload["article_revision_id"]
            ?? actionPlan.payload["articleRevisionId"]
            ?? selectedBlock?.articleRevisionId
            ?? selectedArticle?.activeRevisionId
            ?? activeRevisionId
    }

    private func validateReadingOutlineSkillReadiness() -> Bool {
        let requiredSlug = "paper-outline"
        guard let skill = researchSkills.first(where: { $0.slug == requiredSlug }) else {
            researchWorkbenchStatus = "Skill not indexed"
            researchWorkbenchError = "Index local research skills before preparing a paper-specific reading outline action."
            return false
        }
        guard skill.supportsPaperReading else {
            researchWorkbenchStatus = "Skill task mismatch"
            researchWorkbenchError = "\(skill.title) is indexed but does not declare paper reading support."
            return false
        }
        guard skill.isEnabled else {
            researchWorkbenchStatus = "Skill disabled"
            researchWorkbenchError = "\(skill.title) is indexed but disabled. Enable it in the research backend before preparing outline actions."
            return false
        }
        return true
    }

    private func readingOutlineExecutionResult(for actionPlan: AgentActionPlan) -> ResearchPlanJSONObject {
        let articleTitle = selectedArticle?.title
            ?? actionPlan.payload["topic"]
            ?? actionPlan.title
        let articleRevisionId = researchPlanArticleRevisionId(for: actionPlan) ?? "unselected-revision"
        let articleIdentifier = selectedArticle.map { article in
            article.externalId.isEmpty ? article.id : article.externalId
        } ?? actionPlan.payload["article_id"] ?? articleRevisionId
        let blocks = visibleReadingOutlineBlocks()
        let selectedText = selectedBlock.map { selectedReaderText ?? semanticSourceMarkdown(for: $0) }
        let claim = outlineSnippets(
            from: blocks,
            kinds: [.abstract, .paragraph],
            keywords: ["we ", "propose", "present", "show", "demonstrate", "prove", "introduce", "achieve"],
            fallbackKinds: [.abstract, .paragraph]
        )
        let method = outlineSnippets(
            from: blocks,
            kinds: [.section, .subsection, .paragraph, .algorithm],
            keywords: ["method", "approach", "algorithm", "model", "framework", "optimization", "training"],
            fallbackKinds: [.section, .subsection]
        )
        let equations = outlineSnippets(
            from: blocks,
            kinds: [.equation],
            keywords: [],
            fallbackKinds: [.equation]
        )
        let evidence = outlineSnippets(
            from: blocks,
            kinds: [.paragraph, .figure, .table],
            keywords: ["experiment", "result", "evaluation", "benchmark", "figure", "table", "outperform"],
            fallbackKinds: [.figure, .table]
        )
        let limitations = outlineSnippets(
            from: blocks,
            kinds: [.paragraph],
            keywords: ["limitation", "assumption", "future", "fail", "cannot", "only"],
            fallbackKinds: []
        )
        let followUp = readingOutlineFollowUps(
            articleTitle: articleTitle,
            selectedText: selectedText,
            hasEquations: !equations.isEmpty,
            hasEvidence: !evidence.isEmpty
        )
        let summary = readingOutlineSummary(
            articleTitle: articleTitle,
            claim: claim,
            method: method,
            equations: equations,
            evidence: evidence
        )
        let sourceRefs: [ResearchPlanJSONValue] = [articleIdentifier].map { .string($0) }
        let mastery: ResearchPlanJSONObject = [
            "paper_id": .string(articleIdentifier),
            "paper_title": .string(articleTitle),
            "claim": .array(claim.map(ResearchPlanJSONValue.string)),
            "method": .array(method.map(ResearchPlanJSONValue.string)),
            "equation": .array(equations.map(ResearchPlanJSONValue.string)),
            "evidence": .array(evidence.map(ResearchPlanJSONValue.string)),
            "limitation": .array(limitations.map(ResearchPlanJSONValue.string)),
            "follow_up": .array(followUp.map(ResearchPlanJSONValue.string))
        ]
        let outline: ResearchPlanJSONObject = [
            "id": .string("outline-\(articleRevisionId)"),
            "article_revision_id": .string(articleRevisionId),
            "title": .string("Reading outline: \(articleTitle)"),
            "status": .string("ready"),
            "summary": .string(summary),
            "questions": .array(followUp.map(ResearchPlanJSONValue.string)),
            "source_refs": .array(sourceRefs),
            "paper_mastery_outlines": .array([.object(mastery)]),
            "metadata": .object([
                "generated_by": .string("macos_reader_context"),
                "source_action_plan_id": .string(actionPlan.id),
                "block_count": .number(Double(blocks.count)),
                "selected_block_uid": selectedBlock.map { .string($0.blockUid) } ?? .null
            ])
        ]
        return [
            "status": .string("done"),
            "executor": .string("macos"),
            "outline_source": .string("visible_reader_blocks"),
            "reading_outline": .object(outline)
        ]
    }

    private func outlineSnippets(
        from blocks: [DocumentBlock],
        kinds: Set<DocumentBlockKind>,
        keywords: [String],
        fallbackKinds: Set<DocumentBlockKind>
    ) -> [String] {
        let keywordMatches = blocks
            .filter { kinds.contains($0.blockType) }
            .filter { block in
                guard !keywords.isEmpty else { return true }
                let lowercased = semanticSourceMarkdown(for: block).lowercased()
                return keywords.contains { lowercased.contains($0) }
            }
        let fallbackMatches = blocks.filter { fallbackKinds.contains($0.blockType) }
        return (keywordMatches.isEmpty ? fallbackMatches : keywordMatches)
            .map { outlineSnippet(from: $0) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .map { $0 }
    }

    private func outlineSnippet(from block: DocumentBlock) -> String {
        let text = semanticSourceMarkdown(for: block)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let prefix = "[\(block.blockUid)] "
        let budget = max(80, 260 - prefix.count)
        if text.count <= budget {
            return prefix + text
        }
        let endIndex = text.index(text.startIndex, offsetBy: budget)
        return prefix + text[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func semanticSourceMarkdown(for block: DocumentBlock) -> String {
        ReaderSemanticCopyFormatter.blockMarkdown(markdown: block.sourceMarkdown)
    }

    private func semanticWritingSource(for block: DocumentBlock) -> String {
        if let latex = block.sourceLatex?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latex.isEmpty {
            return latex
        }
        return semanticSourceMarkdown(for: block)
    }

    private func readingOutlineFollowUps(
        articleTitle: String,
        selectedText: String?,
        hasEquations: Bool,
        hasEvidence: Bool
    ) -> [String] {
        var questions = [
            "What is the main claim that \(articleTitle) asks the reader to accept?",
            "Which assumptions must hold before the method is valid?"
        ]
        if hasEquations {
            questions.append("Which equation carries the paper's core argument, and what does each symbol mean?")
        }
        if hasEvidence {
            questions.append("Which experiment or table is the strongest evidence, and what would weaken it?")
        }
        if let selectedText, !selectedText.isEmpty {
            questions.append("How does the selected block connect to the paper's claim and method?")
        }
        return Array(questions.prefix(5))
    }

    private func readingOutlineSummary(
        articleTitle: String,
        claim: [String],
        method: [String],
        equations: [String],
        evidence: [String]
    ) -> String {
        var parts = ["Master \(articleTitle) by tracing the claim, method, equations, evidence, and limits in the loaded reader blocks."]
        if let firstClaim = claim.first {
            parts.append("Start from \(firstClaim)")
        }
        if let firstMethod = method.first {
            parts.append("Then inspect \(firstMethod)")
        }
        if !equations.isEmpty {
            parts.append("Resolve the listed equations before moving to notes.")
        }
        if !evidence.isEmpty {
            parts.append("Use the evidence snippets to check whether the claim is actually supported.")
        }
        return parts.joined(separator: " ")
    }

    private func validateRecoveryContext(
        _ recoveryContext: ActionPlanRecoveryContext?,
        currentTargetPath: String?,
        currentBaseFileHash: String?
    ) -> Bool {
        do {
            try ActionPlanRecoveryTargetValidator().validate(
                context: recoveryContext,
                currentTargetPath: currentTargetPath,
                currentBaseFileHash: currentBaseFileHash
            )
            return true
        } catch {
            researchWorkbenchStatus = "Cannot regenerate"
            researchWorkbenchError = error.localizedDescription
            return false
        }
    }

    private func baseFileHash(at path: String) -> String {
        let text = (try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)) ?? ""
        return LocalFilePatchExecutor.contentHash(for: text)
    }

    private func researchActionStatusLabel(_ status: AgentActionStatus) -> String {
        switch status {
        case .draft:
            return "Draft"
        case .pendingApproval:
            return "Pending approval"
        case .approved:
            return "Approved"
        case .queued:
            return "Queued"
        case .rejected:
            return "Rejected"
        case .cancelled:
            return "Cancelled"
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        }
    }
}

extension AgentActionPlan {
    var isZoteroImportActionPlan: Bool {
        switch kind {
        case .downloadPaper, .importLibrary:
            return payload["zotero_item_id"] != nil
        case .writeObsidian,
             .editManuscript,
             .installSkill,
             .enableSkill,
             .runExternalTool,
             .providerCall,
             .writeLibraryBundle,
             .exportArticle,
             .notePatch,
             .writingPatch,
             .generateResearchOutline,
             .custom:
            return false
        }
    }
}
