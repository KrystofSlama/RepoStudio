//
//  DashboardViewModel.swift
//  RepoStudio
//

import AppKit
import Combine
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    enum CanvasMode: String, CaseIterable, Identifiable {
        case editor
        case preview
        case split

        var id: String { rawValue }

        var title: String {
            switch self {
            case .editor:
                return "Editor"
            case .preview:
                return "Preview"
            case .split:
                return "Split"
            }
        }

        var symbolName: String {
            switch self {
            case .editor:
                return "doc.text"
            case .preview:
                return "eye"
            case .split:
                return "square.split.2x1"
            }
        }
    }

    struct FileTypeFilterOption: Identifiable, Hashable {
        let key: String
        let title: String

        var id: String { key }
    }

    //MARK: -Published State
    @Published private(set) var repositoryContext: RepositoryContext?
    @Published private(set) var changedFiles: [ChangedFile] = []
    @Published private(set) var repositoryFiles: [RepositoryFile] = []
    @Published private(set) var isGitRepository = false
    @Published private(set) var folderWorkspaceReason = "No git repository."
    @Published private(set) var selectedFile: ChangedFile?
    @Published private(set) var isOpeningRepository = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var recentRepositoryPaths: [String] = []
    @Published private(set) var selectedCommitFileIDs: Set<String> = []
    @Published private(set) var branches: [GitBranch] = []
    @Published private(set) var remoteTrackingState = GitRemoteTrackingState.unpublished
    @Published private(set) var activeGitOperationLabel: String?
    @Published private(set) var isGitOperationInProgress = false

    @Published var selectedFilePath: String?
    @Published var selectedFileTypeFilters: Set<String> = []
    @Published var searchText = ""
    @Published var canvasMode: CanvasMode = .split
    @Published var isInspectorVisible = true
    @Published var editorText = ""
    @Published var readOnlyPreviewText = ""
    @Published var commitSummary = ""
    @Published var commitDescription = ""
    @Published var isNewBranchSheetPresented = false
    @Published var newBranchName = ""
    @Published private(set) var selectedDiffLines: [DiffLine] = []
    @Published private(set) var isDiffLoading = false
    @Published var errorMessage: String?
    @Published var shouldOfferInstallToolsAction = false

    private let repositoryService: RepositoryService
    private var refreshTimer: Timer?
    private var saveTimer: Timer?
    private var diffLoadTask: Task<Void, Never>?
    private var diffSelectionKey: String?
    private var loadedContentSelectionKey: String?
    private var loadedDiffVersionKey: String?
    private var diffCache: [String: [DiffLine]] = [:]

    private var suppressNextRepositoryErrorAlert = false
    private var isEditorDirty = false
    private var isLoadingEditorTextFromDisk = false
    private var dirtyEditorFilePath: String?
    private var securityScopedRepositoryURL: URL?
    private var lastChangedFileIDs: Set<String> = []

    private let recentRepositoriesKey = "repoDraft.recentRepositories"
    private let repositoryBookmarksKey = "repoDraft.repositoryBookmarks"
    private let noGitRepositoryLabel = "No git repository"

    var groupedChangedFiles: [(GitChangeType, [ChangedFile])] {
        let grouped = Dictionary(grouping: filteredChangedFiles, by: { $0.changeType })
        return grouped
            .map { ($0.key, $0.value.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }) }
            .sorted { lhs, rhs in
                lhs.0.sortOrder < rhs.0.sortOrder
            }
    }

    var filteredChangedFiles: [ChangedFile] {
        filterChangedFiles(changedFiles)
    }

    var filteredRepositoryFiles: [RepositoryFile] {
        let filteredByType = repositoryFiles.filter { file in
            allowsByFileTypeFilter(path: file.path)
        }

        let filteredBySearch = applySearch(to: filteredByType.map(\.path))
        let filteredSet = Set(filteredBySearch)

        return filteredByType
            .filter { filteredSet.contains($0.path) }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    var selectedRepositoryFile: RepositoryFile? {
        guard let selectedFilePath else {
            return nil
        }

        return repositoryFiles.first(where: { $0.path == selectedFilePath })
    }

    var selectedFileURL: URL? {
        guard
            let repositoryContext,
            let selectedFilePath,
            selectedIsDeleted == false
        else {
            return nil
        }

        return repositoryContext.repoURL.appendingPathComponent(selectedFilePath)
    }

    var selectedFileDirectoryURL: URL? {
        selectedFileURL?.deletingLastPathComponent()
    }

    var selectedDisplayPath: String? {
        selectedFile?.displayPath ?? selectedFilePath
    }

    var selectedFileName: String {
        guard let selectedFilePath else {
            return ""
        }

        return URL(fileURLWithPath: selectedFilePath).lastPathComponent
    }

    var selectedStatusText: String {
        if isGitRepository == false {
            return "No Git"
        }

        if let changeType = selectedFile?.changeType {
            return changeType.displayName
        }

        return "Unchanged"
    }

    var selectedTypeText: String {
        if selectedIsMarkdown {
            return "Markdown"
        }

        if selectedIsImagePreviewable {
            return "Image"
        }

        if selectedIsVideoPreviewable {
            return "Video"
        }

        if selectedIsPDFPreviewable {
            return "PDF"
        }

        if selectedIsTextPreviewable {
            return "Text"
        }

        if selectedIsBinary {
            return "Binary"
        }

        return "Text"
    }

    var selectedTrackedText: String {
        if isGitRepository == false {
            return "No Git"
        }

        return selectedIsTracked ? "Tracked" : "Untracked"
    }

    var selectedOldPath: String? {
        selectedFile?.oldPath
    }

    var selectedIsMarkdown: Bool {
        selectedFile?.isMarkdown ?? selectedRepositoryFile?.isMarkdown ?? false
    }

    var selectedIsBinary: Bool {
        selectedFile?.isBinary ?? selectedRepositoryFile?.isBinary ?? false
    }

    var selectedIsTextPreviewable: Bool {
        guard let path = selectedFilePath else {
            return false
        }
        return Self.isTextPreviewable(path: path) && selectedIsBinary == false
    }

    var selectedIsEditableText: Bool {
        selectedIsMarkdown || selectedIsTextPreviewable
    }

    var selectedIsImagePreviewable: Bool {
        guard let path = selectedFilePath else {
            return false
        }

        return Self.isImagePreviewable(path: path)
    }

    var selectedIsVideoPreviewable: Bool {
        guard let path = selectedFilePath else {
            return false
        }

        return Self.isVideoPreviewable(path: path)
    }

    var selectedIsPDFPreviewable: Bool {
        guard let path = selectedFilePath else {
            return false
        }

        return Self.isPDFPreviewable(path: path)
    }

    var selectedIsDeleted: Bool {
        selectedFile?.changeType == .deleted
    }

    var selectedIsTracked: Bool {
        if let selectedFile {
            return selectedFile.changeType != .untracked
        }

        return selectedRepositoryFile?.isTracked ?? false
    }

    var sidebarCountSummary: String {
        if isGitRepository == false {
            return "\(repositoryFiles.count) file(s) · No Git"
        }

        return "\(repositoryFiles.count) file(s) · \(changedFiles.count) changed"
    }

    var localBranches: [GitBranch] {
        branches.filter { $0.isRemote == false }
    }

    var remoteBranches: [GitBranch] {
        branches.filter { $0.isRemote }
    }

    var selectedCommitFiles: [ChangedFile] {
        changedFiles.filter { selectedCommitFileIDs.contains($0.id) }
    }

    var selectedCommitFileCount: Int {
        selectedCommitFiles.count
    }

    var canCommitSelectedFiles: Bool {
        isGitRepository
            && isGitOperationInProgress == false
            && selectedCommitFileCount > 0
            && commitSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var commitButtonTitle: String {
        let branchName = repositoryContext?.branchName ?? "branch"
        return "Commit \(selectedCommitFileCount) file(s) to \(branchName)"
    }

    var syncStatusText: String {
        guard isGitRepository else {
            return "No Git"
        }

        if remoteTrackingState.isPublished == false {
            return "Unpublished branch"
        }

        if remoteTrackingState.aheadCount > 0, remoteTrackingState.behindCount > 0 {
            return "\(remoteTrackingState.aheadCount) ahead · \(remoteTrackingState.behindCount) behind"
        }

        if remoteTrackingState.aheadCount > 0 {
            return "\(remoteTrackingState.aheadCount) ahead"
        }

        if remoteTrackingState.behindCount > 0 {
            return "\(remoteTrackingState.behindCount) behind"
        }

        if let upstreamBranch = remoteTrackingState.upstreamBranch {
            return "Up to date with \(upstreamBranch)"
        }

        return "Up to date"
    }

    var primarySyncActionTitle: String {
        if let activeGitOperationLabel {
            return activeGitOperationLabel
        }

        if remoteTrackingState.isPublished == false {
            return "Publish Branch"
        }

        if remoteTrackingState.behindCount > 0 {
            return "Pull"
        }

        if remoteTrackingState.aheadCount > 0 {
            return "Push"
        }

        return "Refresh"
    }

    var primarySyncActionSymbolName: String {
        if remoteTrackingState.isPublished == false {
            return "square.and.arrow.up"
        }

        if remoteTrackingState.behindCount > 0 {
            return "arrow.down"
        }

        if remoteTrackingState.aheadCount > 0 {
            return "arrow.up"
        }

        return "arrow.clockwise"
    }

    var canPerformPrimarySyncAction: Bool {
        isGitRepository && isGitOperationInProgress == false && repositoryContext != nil
    }

    var windowTitle: String {
        repositoryContext?.repoName ?? "RepoStudio"
    }

    var fileTypeFilterOptions: [FileTypeFilterOption] {
        [
            FileTypeFilterOption(key: "md", title: "Markdown (.md)"),
            FileTypeFilterOption(key: "swift", title: "Swift (.swift)"),
            FileTypeFilterOption(key: "py", title: "Python (.py)"),
            FileTypeFilterOption(key: "html", title: "HTML (.html)"),
            FileTypeFilterOption(key: "css", title: "CSS (.css)"),
            FileTypeFilterOption(key: "js", title: "JavaScript (.js)"),
            FileTypeFilterOption(key: "ts", title: "TypeScript (.ts)"),
            FileTypeFilterOption(key: "json", title: "JSON (.json)"),
            FileTypeFilterOption(key: "yml", title: "YAML (.yml/.yaml)"),
            FileTypeFilterOption(key: "txt", title: "Text (.txt)"),
            FileTypeFilterOption(key: "png", title: "PNG (.png)"),
            FileTypeFilterOption(key: "jpg", title: "JPEG (.jpg/.jpeg)"),
            FileTypeFilterOption(key: "pdf", title: "PDF (.pdf)"),
            FileTypeFilterOption(key: "mp4", title: "Video (.mp4/.mov)"),
            FileTypeFilterOption(key: "_noext", title: "No Extension")
        ]
    }

    var fileTypeFilterSummary: String {
        if selectedFileTypeFilters.isEmpty {
            return "No Filter"
        }

        if selectedFileTypeFilters.count == 1, let selected = selectedFileTypeFilters.first {
            return displayName(forFilterKey: selected)
        }

        return "\(selectedFileTypeFilters.count) Types"
    }

    init(repositoryService: RepositoryService) {
        self.repositoryService = repositoryService
        loadRecentRepositories()
    }

    deinit {
        refreshTimer?.invalidate()
        saveTimer?.invalidate()
        diffLoadTask?.cancel()
        if let securityScopedRepositoryURL {
            securityScopedRepositoryURL.stopAccessingSecurityScopedResource()
        }
    }

    //MARK: -Public API
    func openRepository() {
        let panel = NSOpenPanel()
        panel.title = "Open Git Repository"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            openRepository(at: url)
        }
    }

    func openRepository(at url: URL, suppressErrorAlert: Bool = false) {
        suppressNextRepositoryErrorAlert = suppressErrorAlert
        Task {
            await openRepositoryFromURL(url)
        }
    }

    func openRecentRepository(at path: String) {
        openRepository(at: resolvedRepositoryURL(forPath: path))
    }

    func openRepository(atPath path: String, suppressErrorAlert: Bool = false) {
        openRepository(
            at: resolvedRepositoryURL(forPath: path),
            suppressErrorAlert: suppressErrorAlert
        )
    }

    func refreshRepositoryState() {
        guard let repoURL = repositoryContext?.repoURL else {
            return
        }

        Task {
            await refreshRepositoryState(at: repoURL)
        }
    }

    func selectFile(_ file: ChangedFile?) {
        persistEditorTextIfNeeded()
        selectedFile = file
        selectedFilePath = file?.path
        loadSelectedFileArtifacts()
    }

    func selectFile(path: String?) {
        persistEditorTextIfNeeded()
        selectedFilePath = path
        selectedFile = changedFiles.first(where: { $0.path == path })
        loadSelectedFileArtifacts()
    }

    func setCanvasMode(_ mode: CanvasMode) {
        canvasMode = mode
    }

    func toggleFileTypeFilter(_ key: String) {
        if selectedFileTypeFilters.contains(key) {
            selectedFileTypeFilters.remove(key)
        } else {
            selectedFileTypeFilters.insert(key)
        }
    }

    func isFileTypeFilterSelected(_ key: String) -> Bool {
        selectedFileTypeFilters.contains(key)
    }

    func clearFileTypeFilters() {
        selectedFileTypeFilters.removeAll()
    }

    func changeType(for path: String) -> GitChangeType? {
        changedFiles.first(where: { $0.path == path })?.changeType
    }

    func isCommitFileSelected(_ file: ChangedFile) -> Bool {
        selectedCommitFileIDs.contains(file.id)
    }

    func toggleCommitFileSelection(_ file: ChangedFile) {
        if selectedCommitFileIDs.contains(file.id) {
            selectedCommitFileIDs.remove(file.id)
        } else {
            selectedCommitFileIDs.insert(file.id)
        }
    }

    func commitSelectedFiles() {
        guard canCommitSelectedFiles else {
            return
        }

        let filesToCommit = selectedCommitFiles
        let summary = commitSummary
        let description = commitDescription

        runGitOperation(label: "Committing...") { [repositoryService] repoURL in
            try await repositoryService.commit(
                files: filesToCommit,
                summary: summary,
                description: description,
                at: repoURL
            )
        } onSuccess: { [weak self] in
            self?.commitSummary = ""
            self?.commitDescription = ""
        }
    }

    func showNewBranchSheet() {
        newBranchName = ""
        isNewBranchSheetPresented = true
    }

    func cancelNewBranchCreation() {
        newBranchName = ""
        isNewBranchSheetPresented = false
    }

    func createBranchFromPrompt() {
        let branchName = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard branchName.isEmpty == false else {
            return
        }

        isNewBranchSheetPresented = false
        newBranchName = ""
        createBranch(named: branchName)
    }

    func createBranch(named branchName: String) {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBranchName.isEmpty == false else {
            return
        }

        runGitOperation(label: "Creating branch...") { [repositoryService] repoURL in
            try await repositoryService.createBranch(named: trimmedBranchName, at: repoURL)
        }
    }

    func checkoutBranch(_ branch: GitBranch) {
        guard branch.isRemote == false, branch.isCurrent == false else {
            return
        }

        checkoutBranch(named: branch.name)
    }

    func checkoutBranch(named branchName: String) {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBranchName.isEmpty == false else {
            return
        }

        runGitOperation(label: "Switching branch...") { [repositoryService] repoURL in
            try await repositoryService.checkoutBranch(named: trimmedBranchName, at: repoURL)
        }
    }

    func performPrimarySyncAction() {
        guard canPerformPrimarySyncAction else {
            return
        }

        if remoteTrackingState.isPublished == false {
            runGitOperation(label: "Publishing...") { [repositoryService] repoURL in
                try await repositoryService.publishCurrentBranch(remoteName: "origin", at: repoURL)
            }
            return
        }

        if remoteTrackingState.behindCount > 0 {
            runGitOperation(label: "Pulling...") { [repositoryService] repoURL in
                try await repositoryService.pullCurrentBranch(at: repoURL)
            }
            return
        }

        if remoteTrackingState.aheadCount > 0 {
            runGitOperation(label: "Pushing...") { [repositoryService] repoURL in
                try await repositoryService.pushCurrentBranch(at: repoURL)
            }
            return
        }

        refreshRepositoryState()
    }

    func installXcodeCommandLineTools() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]

        do {
            try process.run()
        } catch {
            errorMessage = """
            Could not launch Xcode Command Line Tools installer.
            Open Terminal and run: xcode-select --install
            """
        }
    }

    func toggleInspector() {
        isInspectorVisible.toggle()
    }

    func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }

    func scheduleAutosaveForMarkdown() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistEditorTextIfNeeded()
            }
        }
    }

    func editorTextDidChange() {
        guard selectedIsEditableText, selectedIsDeleted == false else {
            return
        }

        guard isLoadingEditorTextFromDisk == false else {
            return
        }

        isEditorDirty = true
        dirtyEditorFilePath = selectedFilePath
        scheduleAutosaveForMarkdown()
    }

    //MARK: -Private Helpers
    private func openRepositoryFromURL(_ url: URL) async {
        guard isOpeningRepository == false else {
            return
        }

        isOpeningRepository = true
        defer {
            isOpeningRepository = false
        }

        let securedURL = prepareRepositoryURLForAccess(url)

        do {
            try await repositoryService.validateRepository(at: securedURL)
            clearSelectedFileState()
            let context = try await repositoryService.fetchRepositoryContext(at: securedURL)
            repositoryContext = context
            isGitRepository = true
            folderWorkspaceReason = "No git repository."
            errorMessage = nil
            shouldOfferInstallToolsAction = false
            addRecentRepository(securedURL.path)
            saveBookmarkIfPossible(for: securedURL)

            await refreshRepositoryState(at: securedURL)
            startRefreshTimer()
        } catch {
            if shouldOpenAsFolderWorkspace(for: error) {
                await openFolderWorkspace(at: securedURL, reason: folderWorkspaceReason(for: error))
                return
            }

            if suppressNextRepositoryErrorAlert {
                suppressNextRepositoryErrorAlert = false
                return
            }
            apply(error: error)
        }
        suppressNextRepositoryErrorAlert = false
    }

    private func openFolderWorkspace(at url: URL, reason: String) async {
        do {
            let files = try fetchFolderFiles(at: url)
            clearSelectedFileState()
            repositoryContext = RepositoryContext(
                repoURL: url,
                repoName: url.lastPathComponent,
                branchName: noGitRepositoryLabel
            )
            isGitRepository = false
            folderWorkspaceReason = reason
            errorMessage = nil
            shouldOfferInstallToolsAction = false
            changedFiles = []
            repositoryFiles = files
            branches = []
            remoteTrackingState = .unpublished
            reconcileCommitSelection()
            addRecentRepository(url.path)
            saveBookmarkIfPossible(for: url)

            startRefreshTimer()
        } catch {
            clearRepositoryStateAfterOpenFailure(reason: reason)
            if suppressNextRepositoryErrorAlert {
                suppressNextRepositoryErrorAlert = false
                return
            }
            apply(error: error)
        }

        suppressNextRepositoryErrorAlert = false
    }

    private func clearRepositoryStateAfterOpenFailure(reason: String) {
        clearSelectedFileState()
        repositoryContext = nil
        isGitRepository = false
        folderWorkspaceReason = reason
        changedFiles = []
        repositoryFiles = []
        branches = []
        remoteTrackingState = .unpublished
        reconcileCommitSelection()
        errorMessage = nil
        shouldOfferInstallToolsAction = false
    }

    private func refreshRepositoryState(at repoURL: URL) async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if isGitRepository {
                let context = try await repositoryService.fetchRepositoryContext(at: repoURL)
                let files = try await repositoryService.fetchChangedFiles(at: repoURL)
                let repositoryFiles = try await repositoryService.fetchRepositoryFiles(at: repoURL)
                let branches = try await repositoryService.fetchBranches(at: repoURL)
                let remoteTrackingState = try await repositoryService.fetchRemoteTrackingState(at: repoURL)

                self.repositoryContext = context
                self.changedFiles = files
                self.repositoryFiles = repositoryFiles
                self.branches = branches
                self.remoteTrackingState = remoteTrackingState
                reconcileCommitSelection()
            } else {
                let files = try fetchFolderFiles(at: repoURL)
                self.repositoryContext = RepositoryContext(
                    repoURL: repoURL,
                    repoName: repoURL.lastPathComponent,
                    branchName: noGitRepositoryLabel
                )
                self.changedFiles = []
                self.repositoryFiles = files
                self.branches = []
                self.remoteTrackingState = .unpublished
                reconcileCommitSelection()
            }

            reconcileSelectedFile()
            errorMessage = nil
            shouldOfferInstallToolsAction = false
        } catch {
            apply(error: error)
        }
    }

    private func runGitOperation(
        label: String,
        operation: @escaping (URL) async throws -> Void,
        onSuccess: (() -> Void)? = nil
    ) {
        guard
            let repoURL = repositoryContext?.repoURL,
            isGitRepository,
            isGitOperationInProgress == false
        else {
            return
        }

        persistEditorTextIfNeeded()
        isGitOperationInProgress = true
        activeGitOperationLabel = label

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                self.isGitOperationInProgress = false
                self.activeGitOperationLabel = nil
            }

            do {
                try await operation(repoURL)
                onSuccess?()
                await self.refreshRepositoryState(at: repoURL)
            } catch {
                self.apply(error: error)
            }
        }
    }

    private func reconcileCommitSelection() {
        let currentFileIDs = Set(changedFiles.map(\.id))
        let newFileIDs = currentFileIDs.subtracting(lastChangedFileIDs)

        if lastChangedFileIDs.isEmpty {
            selectedCommitFileIDs = currentFileIDs
        } else {
            selectedCommitFileIDs = selectedCommitFileIDs.intersection(currentFileIDs)
            selectedCommitFileIDs.formUnion(newFileIDs)
        }

        lastChangedFileIDs = currentFileIDs
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshRepositoryState()
            }
        }
    }

    private func reconcileSelectedFile() {
        let previousChangedSelectionID = selectedFile?.id
        let previousSelectedPath = selectedFilePath

        guard let selectedFilePath else {
            selectedFile = nil
            editorText = ""
            readOnlyPreviewText = ""
            clearSelectedDiffState()
            loadedContentSelectionKey = nil
            return
        }

        selectedFile = changedFiles.first(where: { $0.path == selectedFilePath })

        let fileExistsInRepositoryListing = repositoryFiles.contains(where: { $0.path == selectedFilePath })
        if fileExistsInRepositoryListing == false, selectedFile?.changeType != .deleted {
            self.selectedFilePath = nil
            self.selectedFile = nil
            editorText = ""
            readOnlyPreviewText = ""
            clearSelectedDiffState()
            loadedContentSelectionKey = nil
            isEditorDirty = false
            dirtyEditorFilePath = nil
            return
        }

        if shouldKeepDirtyEditorTextForSelectedFile() {
            return
        }

        let forceReload = previousSelectedPath != selectedFilePath
        loadSelectedFileArtifacts(
            forceContentReload: forceReload,
            previousChangedSelectionID: previousChangedSelectionID
        )
    }

    private func loadSelectedFileArtifacts(
        forceContentReload: Bool = true,
        previousChangedSelectionID: String? = nil
    ) {
        loadSelectedFileContent(forceReload: forceContentReload)
        loadSelectedFileDiff(previousChangedSelectionID: previousChangedSelectionID)
    }

    private func loadSelectedFileContent(forceReload: Bool) {
        let selectionKey = currentSelectionKey()
        if forceReload == false, selectionKey == loadedContentSelectionKey {
            return
        }

        guard let fileURL = selectedFileURL else {
            editorText = ""
            readOnlyPreviewText = ""
            isEditorDirty = false
            dirtyEditorFilePath = nil
            loadedContentSelectionKey = selectionKey
            return
        }

        guard selectedIsEditableText else {
            editorText = ""
            readOnlyPreviewText = ""
            isEditorDirty = false
            dirtyEditorFilePath = nil
            loadedContentSelectionKey = selectionKey
            return
        }

        do {
            let loadedText = try String(contentsOf: fileURL, encoding: .utf8)

            isLoadingEditorTextFromDisk = true
            editorText = loadedText
            isLoadingEditorTextFromDisk = false
            readOnlyPreviewText = selectedIsMarkdown ? "" : loadedText
            isEditorDirty = false
            dirtyEditorFilePath = nil
            loadedContentSelectionKey = selectionKey
        } catch {
            editorText = ""
            readOnlyPreviewText = ""
            isEditorDirty = false
            dirtyEditorFilePath = nil
            loadedContentSelectionKey = nil
            errorMessage = DashboardError.fileReadFailed(fileURL.path).localizedDescription
            shouldOfferInstallToolsAction = false
        }
    }

    private func loadSelectedFileDiff(previousChangedSelectionID: String? = nil) {
        guard let repositoryContext, let selectedFile else {
            clearSelectedDiffState()
            return
        }

        guard selectedFile.isBinary == false else {
            clearSelectedDiffState()
            return
        }

        let selectedFileID = selectedFile.id
        let selectedPath = selectedFile.path
        let repoURL = repositoryContext.repoURL
        let selectionKey = "\(repoURL.path)|\(selectedPath)"
        let versionKey = "\(selectionKey)|\(selectedFileID)"
        let oldSelectionID = previousChangedSelectionID ?? selectedFileID

        let isSameSelection = diffSelectionKey == selectionKey
        if isSameSelection == false {
            selectedDiffLines = []
        }
        diffSelectionKey = selectionKey

        if loadedDiffVersionKey == versionKey, oldSelectionID == selectedFileID {
            if let cached = diffCache[versionKey] {
                selectedDiffLines = cached
            }
            return
        }

        if let cached = diffCache[versionKey] {
            selectedDiffLines = cached
            loadedDiffVersionKey = versionKey
            if oldSelectionID == selectedFileID {
                return
            }
        }

        if isDiffLoading {
            return
        }

        diffLoadTask?.cancel()
        isDiffLoading = true

        diffLoadTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let diffLines = try await repositoryService.fetchDiffLines(at: repoURL, for: selectedFile)
                guard Task.isCancelled == false else {
                    return
                }

                if self.repositoryContext?.repoURL == repoURL,
                   self.selectedFile?.id == selectedFileID,
                   self.selectedFilePath == selectedPath {
                    self.selectedDiffLines = diffLines
                    self.diffCache[versionKey] = diffLines
                    self.loadedDiffVersionKey = versionKey
                    self.isDiffLoading = false
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }

                if self.repositoryContext?.repoURL == repoURL,
                   self.selectedFile?.id == selectedFileID,
                   self.selectedFilePath == selectedPath {
                    self.isDiffLoading = false
                }
            }
        }
    }

    private func clearSelectedDiffState() {
        diffLoadTask?.cancel()
        selectedDiffLines = []
        isDiffLoading = false
        diffSelectionKey = nil
        loadedDiffVersionKey = nil
    }

    private func persistEditorTextIfNeeded() {
        guard
            selectedIsEditableText,
            selectedIsDeleted == false,
            let fileURL = selectedFileURL,
            isEditorDirty
        else {
            return
        }

        do {
            try editorText.write(to: fileURL, atomically: false, encoding: .utf8)
            isEditorDirty = false
            dirtyEditorFilePath = nil
            loadedContentSelectionKey = currentSelectionKey()
            loadedDiffVersionKey = nil

            if let repoPath = repositoryContext?.repoURL.path, let selectedFilePath {
                let prefix = "\(repoPath)|\(selectedFilePath)|"
                diffCache = diffCache.filter { key, _ in
                    key.hasPrefix(prefix) == false
                }
            }
        } catch {
            errorMessage = DashboardError.fileWriteFailed(fileURL.path).localizedDescription
            shouldOfferInstallToolsAction = false
        }
    }

    private func loadRecentRepositories() {
        recentRepositoryPaths = UserDefaults.standard.stringArray(forKey: recentRepositoriesKey) ?? []
    }

    private func addRecentRepository(_ path: String) {
        var paths = recentRepositoryPaths.filter { $0 != path }
        paths.insert(path, at: 0)
        recentRepositoryPaths = Array(paths.prefix(8))
        UserDefaults.standard.set(recentRepositoryPaths, forKey: recentRepositoriesKey)
    }

    private func filterChangedFiles(_ files: [ChangedFile]) -> [ChangedFile] {
        let filteredByType = files.filter { file in
            allowsByFileTypeFilter(path: file.path)
        }

        let filteredBySearch = applySearch(to: filteredByType.map(\.path))
        let filteredSet = Set(filteredBySearch)

        return filteredByType
            .filter { filteredSet.contains($0.path) }
            .sorted {
                if $0.changeType.sortOrder == $1.changeType.sortOrder {
                    return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
                }
                return $0.changeType.sortOrder < $1.changeType.sortOrder
            }
    }

    private func applySearch(to paths: [String]) -> [String] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSearch.isEmpty == false else {
            return paths
        }

        return paths.filter { path in
            path.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private func allowsByFileTypeFilter(path: String) -> Bool {
        guard selectedFileTypeFilters.isEmpty == false else {
            return true
        }

        let extensionKey = normalizedExtensionKey(for: path)
        return selectedFileTypeFilters.contains(extensionKey)
    }

    private func normalizedExtensionKey(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ext.isEmpty {
            return "_noext"
        }

        if ext == "yaml" {
            return "yml"
        }

        if ext == "jpeg" {
            return "jpg"
        }

        if ext == "mov" || ext == "m4v" {
            return "mp4"
        }

        return ext
    }

    private func displayName(forFilterKey key: String) -> String {
        fileTypeFilterOptions.first(where: { $0.key == key })?.title ?? key.uppercased()
    }

    private func apply(error: Error) {
        if let dashboardError = error as? DashboardError {
            errorMessage = dashboardError.localizedDescription
            shouldOfferInstallToolsAction = dashboardError.isMissingXcodeCommandLineTools
            return
        }

        errorMessage = error.localizedDescription
        shouldOfferInstallToolsAction = false
    }

    private func shouldOpenAsFolderWorkspace(for error: Error) -> Bool {
        if let dashboardError = error as? DashboardError {
            switch dashboardError {
            case .invalidRepository:
                return true
            case .missingXcodeCommandLineTools:
                return true
            case .gitCommandFailed(_, let message):
                return message.localizedCaseInsensitiveContains("not a git repository")
                    || dashboardError.isMissingXcodeCommandLineTools
            default:
                return false
            }
        }

        return error.localizedDescription.localizedCaseInsensitiveContains("not a git repository")
    }

    private func folderWorkspaceReason(for error: Error) -> String {
        if let dashboardError = error as? DashboardError, dashboardError.isMissingXcodeCommandLineTools {
            return "Git features require Git. Install Xcode Command Line Tools to show repository status and diffs."
        }

        return "No git repository."
    }

    private func fetchFolderFiles(at rootURL: URL) throws -> [RepositoryFile] {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            throw DashboardError.fileReadFailed(rootURL.path)
        }

        let standardizedRootPath = rootURL.standardizedFileURL.path
        let rootPrefix = standardizedRootPath.hasSuffix("/") ? standardizedRootPath : "\(standardizedRootPath)/"

        var files: [RepositoryFile] = []

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys), values.isRegularFile == true else {
                continue
            }

            let standardizedFilePath = fileURL.standardizedFileURL.path
            guard standardizedFilePath.hasPrefix(rootPrefix) else {
                continue
            }

            let relativePath = String(standardizedFilePath.dropFirst(rootPrefix.count))
            guard relativePath.isEmpty == false else {
                continue
            }

            files.append(
                RepositoryFile(
                    path: relativePath,
                    isMarkdown: isMarkdownPath(relativePath),
                    isBinary: isBinaryPath(relativePath),
                    isTracked: false
                )
            )
        }

        return files.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func isMarkdownPath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).pathExtension.lowercased() == "md"
    }

    private func isBinaryPath(_ path: String) -> Bool {
        let extensionName = URL(fileURLWithPath: path).pathExtension.lowercased()
        let binaryExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "pdf", "zip", "jar",
            "xcassets", "mov", "mp4", "m4v", "ico", "icns"
        ]

        return binaryExtensions.contains(extensionName)
    }

    private func shouldKeepDirtyEditorTextForSelectedFile() -> Bool {
        guard selectedIsEditableText else {
            return false
        }

        return isEditorDirty && selectedFilePath == dirtyEditorFilePath
    }

    private func clearSelectedFileState() {
        selectedFilePath = nil
        selectedFile = nil
        selectedCommitFileIDs = []
        lastChangedFileIDs = []
        commitSummary = ""
        commitDescription = ""
        editorText = ""
        readOnlyPreviewText = ""
        clearSelectedDiffState()
        isEditorDirty = false
        isLoadingEditorTextFromDisk = false
        dirtyEditorFilePath = nil
        loadedContentSelectionKey = nil
        diffCache.removeAll()
    }

    private func prepareRepositoryURLForAccess(_ url: URL) -> URL {
        if let securityScopedRepositoryURL, securityScopedRepositoryURL != url {
            securityScopedRepositoryURL.stopAccessingSecurityScopedResource()
            self.securityScopedRepositoryURL = nil
        }

        let didStart = url.startAccessingSecurityScopedResource()
        if didStart {
            securityScopedRepositoryURL = url
        }

        return url
    }

    private func resolvedRepositoryURL(forPath path: String) -> URL {
        guard
            let bookmarks = UserDefaults.standard.dictionary(forKey: repositoryBookmarksKey) as? [String: Data],
            let bookmarkData = bookmarks[path]
        else {
            return URL(fileURLWithPath: path)
        }

        var isStale = false
        guard
            let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else {
            return URL(fileURLWithPath: path)
        }

        if isStale {
            saveBookmarkIfPossible(for: resolvedURL)
        }

        return resolvedURL
    }

    private func saveBookmarkIfPossible(for url: URL) {
        guard let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return
        }

        var bookmarks = UserDefaults.standard.dictionary(forKey: repositoryBookmarksKey) as? [String: Data] ?? [:]
        bookmarks[url.path] = bookmarkData
        UserDefaults.standard.set(bookmarks, forKey: repositoryBookmarksKey)
    }

    private func currentSelectionKey() -> String? {
        guard let repoURL = repositoryContext?.repoURL, let selectedFilePath else {
            return nil
        }

        return "\(repoURL.path)|\(selectedFilePath)"
    }

    private static let textPreviewableExtensions: Set<String> = [
        "md", "swift", "m", "mm", "h", "hpp", "c", "cpp", "cc",
        "json", "yaml", "yml", "xml", "html", "htm", "css", "js", "ts",
        "txt", "rst", "sh", "zsh", "bash", "plist", "pbxproj", "strings",
        "gitignore", "env", "toml", "ini", "cfg", "sql", "csv"
    ]

    private static let imagePreviewableExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp"
    ]

    private static let videoPreviewableExtensions: Set<String> = [
        "mov", "mp4", "m4v"
    ]

    private static func isTextPreviewable(path: String) -> Bool {
        let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()

        if textPreviewableExtensions.contains(ext) {
            return true
        }

        if ext.isEmpty {
            return fileName == "makefile" || fileName.hasPrefix(".")
        }

        return false
    }

    private static func isImagePreviewable(path: String) -> Bool {
        imagePreviewableExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private static func isVideoPreviewable(path: String) -> Bool {
        videoPreviewableExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private static func isPDFPreviewable(path: String) -> Bool {
        URL(fileURLWithPath: path).pathExtension.lowercased() == "pdf"
    }
}
