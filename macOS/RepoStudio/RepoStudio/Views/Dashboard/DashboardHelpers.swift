//
//  DashboardHelpers.swift
//  RepoStudio
//

import AppKit
import AVKit
import PDFKit
import SwiftUI

@MainActor
struct DashboardCommandActions {
    let recentRepositoryPaths: [String]
    let isRepositoryOpen: Bool
    let isInspectorVisible: Bool
    let primarySyncActionTitle: String
    let canPerformPrimarySyncAction: Bool
    let shouldShowPrimarySyncAction: Bool
    let canShowHistory: Bool

    let openRepository: () -> Void
    let openRecentRepository: (String) -> Void
    let refreshRepositoryState: () -> Void
    let performPrimarySyncAction: () -> Void
    let showNewBranchSheet: () -> Void
    let showHistory: () -> Void
    let toggleInspector: () -> Void
    let toggleSidebar: () -> Void
    let setCanvasMode: (DashboardViewModel.CanvasMode) -> Void

    init(viewModel: DashboardViewModel) {
        recentRepositoryPaths = viewModel.recentRepositoryPaths
        isRepositoryOpen = viewModel.repositoryContext != nil
        isInspectorVisible = viewModel.isInspectorVisible
        primarySyncActionTitle = viewModel.primarySyncActionTitle
        canPerformPrimarySyncAction = viewModel.canPerformPrimarySyncAction
        shouldShowPrimarySyncAction = viewModel.shouldShowPrimarySyncAction
        canShowHistory = viewModel.commitHistory.isEmpty == false

        openRepository = { [weak viewModel] in
            viewModel?.openRepository()
        }
        openRecentRepository = { [weak viewModel] path in
            viewModel?.openRecentRepository(at: path)
        }
        refreshRepositoryState = { [weak viewModel] in
            viewModel?.refreshRepositoryState(refreshRemoteBranches: true)
        }
        performPrimarySyncAction = { [weak viewModel] in
            viewModel?.performPrimarySyncAction()
        }
        showNewBranchSheet = { [weak viewModel] in
            viewModel?.showNewBranchSheet()
        }
        showHistory = { [weak viewModel] in
            viewModel?.showHistoryView()
        }
        toggleInspector = { [weak viewModel] in
            viewModel?.toggleInspector()
        }
        toggleSidebar = { [weak viewModel] in
            viewModel?.toggleSidebar()
        }
        setCanvasMode = { [weak viewModel] mode in
            viewModel?.setCanvasMode(mode)
        }
    }
}

private struct DashboardCommandActionsKey: FocusedValueKey {
    typealias Value = DashboardCommandActions
}

extension FocusedValues {
    var dashboardCommandActions: DashboardCommandActions? {
        get { self[DashboardCommandActionsKey.self] }
        set { self[DashboardCommandActionsKey.self] = newValue }
    }
}

struct DashboardToolbar: ToolbarContent {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            RepositoryToolbarTitle(viewModel: viewModel)
        }

        ToolbarItemGroup {
            if viewModel.isGitRepository {
                Button {
                    viewModel.performPrimarySyncAction()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.primarySyncActionSymbolName)
                        Text(viewModel.primarySyncActionTitle)
                    }
                }
                .disabled(viewModel.canPerformPrimarySyncAction == false)
                .help(viewModel.primarySyncActionTitle)
            }

            Picker("Mode", selection: Binding(
                get: { viewModel.canvasMode },
                set: { viewModel.setCanvasMode($0) }
            )) {
                ForEach(DashboardViewModel.CanvasMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Button {
                viewModel.toggleInspector()
            } label: {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
        }
    }
}

struct RepositoryToolbarTitle: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isBranchPopoverPresented = false
    @State private var branchSearchText = ""

    var body: some View {
        Button {
            isBranchPopoverPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isGitRepository ? "point.topleft.down.curvedto.point.bottomright.up" : "folder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.windowTitle)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(viewModel.repositoryContext?.branchName ?? "No Branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if viewModel.isGitRepository {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isGitRepository == false)
        .popover(isPresented: $isBranchPopoverPresented, arrowEdge: .top) {
            BranchSelectionPopover(
                viewModel: viewModel,
                searchText: $branchSearchText,
                isPresented: $isBranchPopoverPresented
            )
        }
        .help("Switch branches")
    }
}

struct BranchSelectionPopover: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var searchText: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Find", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if let currentBranch = viewModel.localBranches.first(where: { $0.isCurrent }) {
                branchSection(title: "Current Branch") {
                    BranchPopoverRow(branch: currentBranch, subtitle: viewModel.syncStatusText, isCurrent: true) {}
                }
            }

            if filteredLocalBranches.isEmpty == false {
                branchSection(title: "Branches") {
                    ForEach(filteredLocalBranches) { branch in
                        BranchPopoverRow(branch: branch, subtitle: nil, isCurrent: branch.isCurrent) {
                            viewModel.checkoutBranch(branch)
                            isPresented = false
                        }
                        .disabled(branch.isCurrent || viewModel.isGitOperationInProgress)
                        .contextMenu {
                            if branch.isCurrent == false {
                                Button("Delete Local Branch", role: .destructive) {
                                    viewModel.requestDeleteBranch(branch)
                                    isPresented = false
                                }
                                .disabled(viewModel.isGitOperationInProgress)
                            }
                        }
                    }
                }
            }

            if filteredRemoteBranches.isEmpty == false {
                branchSection(title: "Remote Branches") {
                    ForEach(filteredRemoteBranches) { branch in
                        BranchPopoverRow(branch: branch, subtitle: "Checkout tracking branch", isCurrent: false) {
                            viewModel.checkoutBranch(branch)
                            isPresented = false
                        }
                        .disabled(viewModel.isGitOperationInProgress)
                    }
                }
            }

            Divider()

            Button("New Branch...") {
                viewModel.showNewBranchSheet()
                isPresented = false
            }
            .disabled(viewModel.isGitOperationInProgress)
        }
        .padding(18)
        .frame(width: 430)
    }

    private var filteredLocalBranches: [GitBranch] {
        filtered(viewModel.localBranches.filter { $0.isCurrent == false })
    }

    private var filteredRemoteBranches: [GitBranch] {
        filtered(viewModel.remoteBranches)
    }

    private func filtered(_ branches: [GitBranch]) -> [GitBranch] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSearch.isEmpty == false else {
            return branches
        }

        return branches.filter { branch in
            branch.name.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    @ViewBuilder
    private func branchSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                content()
            }
        }
    }
}

struct BranchPopoverRow: View {
    let branch: GitBranch
    let subtitle: String?
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(branch.name)
                        .font(.body)
                        .lineLimit(1)

                    if let subtitle, subtitle.isEmpty == false {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
struct DashboardCommands: Commands {
    @FocusedValue(\.dashboardCommandActions) private var commandActions
    @FocusedValue(\.workspaceCommandActions) private var workspaceCommandActions

    private let privacyPolicyURL = URL(string: "https://repo-studio.com/privacy-policy")
    private let termsOfUseURL = URL(string: "https://repo-studio.com/terms-of-use")
    private let supportURL = URL(string: "https://repo-studio.com/support")

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Repository...") {
                openRepositoryFromCommands()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Menu("Open Recent") {
                if recentRepositoryPaths.isEmpty == false {
                    ForEach(recentRepositoryPaths, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) {
                            openRecentRepositoryFromCommands(path: path)
                        }
                    }
                } else {
                    Text("No Recent Repositories")
                }
            }
            .disabled(recentRepositoryPaths.isEmpty)

            Divider()

            Button("Refresh Repository") {
                commandActions?.refreshRepositoryState()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(commandActions?.isRepositoryOpen != true)
        }

        CommandMenu("Repository") {
            Button("Open Repository...") {
                openRepositoryFromCommands()
            }

            Button("Refresh Status") {
                commandActions?.refreshRepositoryState()
            }
            .disabled(commandActions?.isRepositoryOpen != true)

            Button("History") {
                commandActions?.showHistory()
            }
            .disabled(commandActions?.canShowHistory != true)

            Divider()

            if commandActions?.shouldShowPrimarySyncAction == true {
                Button(commandActions?.primarySyncActionTitle ?? "Sync") {
                    commandActions?.performPrimarySyncAction()
                }
                .disabled(commandActions?.canPerformPrimarySyncAction != true)
            }

            Button("New Branch...") {
                commandActions?.showNewBranchSheet()
            }
            .disabled(commandActions?.canPerformPrimarySyncAction != true)
        }

        CommandMenu("View") {
            Button("Toggle Sidebar") {
                commandActions?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(commandActions == nil)

            Button(commandActions?.isInspectorVisible == true ? "Hide Inspector" : "Show Inspector") {
                commandActions?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(commandActions == nil)

            Divider()

            Button("Editor Mode") {
                commandActions?.setCanvasMode(.editor)
            }
            .keyboardShortcut("1", modifiers: [.command])
            .disabled(commandActions == nil)

            Button("Preview Mode") {
                commandActions?.setCanvasMode(.preview)
            }
            .keyboardShortcut("2", modifiers: [.command])
            .disabled(commandActions == nil)

            Button("Split Mode") {
                commandActions?.setCanvasMode(.split)
            }
            .keyboardShortcut("3", modifiers: [.command])
            .disabled(commandActions == nil)
        }

        CommandGroup(after: .help) {
            Divider()

            Button("Privacy Policy") {
                openExternalURL(privacyPolicyURL)
            }

            Button("Terms of Use") {
                openExternalURL(termsOfUseURL)
            }

            Button("Support") {
                openExternalURL(supportURL)
            }
        }
    }

    private var recentRepositoryPaths: [String] {
        if let workspaceCommandActions, workspaceCommandActions.recentRepositoryPaths.isEmpty == false {
            return workspaceCommandActions.recentRepositoryPaths
        }

        return commandActions?.recentRepositoryPaths ?? []
    }

    private func openRepositoryFromCommands() {
        if let workspaceCommandActions {
            workspaceCommandActions.openRepositoryInNewTab()
            return
        }

        commandActions?.openRepository()
    }

    private func openRecentRepositoryFromCommands(path: String) {
        if let workspaceCommandActions {
            workspaceCommandActions.openRecentRepositoryInNewTab(path)
            return
        }

        commandActions?.openRecentRepository(path)
    }

    private func openExternalURL(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

struct NewBranchSheet: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Branch")
                .font(.headline)

            TextField("Branch name", text: $viewModel.newBranchName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.createBranchFromPrompt()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.cancelNewBranchCreation()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Branch") {
                    viewModel.createBranchFromPrompt()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

struct SwitchBranchSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    let request: DashboardViewModel.BranchSwitchRequest

    private var changeCountText: String {
        request.changedFileCount == 1 ? "1 changed file" : "\(request.changedFileCount) changed files"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Switch Branch")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.cancelBranchSwitch()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }

            Text("You have \(changeCountText) on \(request.currentBranchName). What should RepoStudio do before switching to \(request.targetBranchName)?")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                branchSwitchOption(
                    title: "Leave changes on \(request.currentBranchName)",
                    subtitle: "Your work will be saved in Git stash before switching branches.",
                    symbolName: "tray.and.arrow.down",
                    action: viewModel.confirmBranchSwitchLeavingChanges
                )

                Divider()

                branchSwitchOption(
                    title: "Bring changes to \(request.targetBranchName)",
                    subtitle: "RepoStudio will try to switch branches with your current work.",
                    symbolName: "arrow.triangle.branch",
                    action: viewModel.confirmBranchSwitchBringingChanges
                )
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.7))
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.cancelBranchSwitch()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 470)
    }

    private func branchSwitchOption(
        title: String,
        subtitle: String,
        symbolName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

struct GitHubAccountSheet: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var hasUsername: Bool {
        viewModel.gitHubAccountUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var hasToken: Bool {
        viewModel.gitHubAccountToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GitHub Account")
                .font(.headline)

            TextField("GitHub username", text: $viewModel.gitHubAccountUsername)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.applyGitHubAccountFromPrompt()
                }

            SecureField("Personal access token", text: $viewModel.gitHubAccountToken)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if hasToken {
                        viewModel.applyGitHubCredentialFromPrompt()
                    } else {
                        viewModel.applyGitHubAccountFromPrompt()
                    }
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.cancelGitHubAccountSelection()
                }
                .keyboardShortcut(.cancelAction)

                Button("Use Account") {
                    viewModel.applyGitHubAccountFromPrompt()
                }
                .disabled(hasUsername == false)

                Button("Save Token") {
                    viewModel.applyGitHubCredentialFromPrompt()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hasUsername == false || hasToken == false)
            }
        }
        .padding(18)
        .frame(width: 400)
    }
}

extension DashboardView {
    //MARK: -Subviews
    var sidebar: some View {
        List {
            Section {
                TextField("Search (.md or filename)", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)

                SidebarFileTypeFilterMenu(viewModel: viewModel)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            Section("Files") {
                if repositoryTreeRoots.isEmpty {
                    Text("No files match search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(repositoryTreeRoots) { node in
                        SidebarRepositoryTreeRow(
                            node: node,
                            viewModel: viewModel,
                            selectedRow: sidebarSelection,
                            onSelect: { selection in
                                selectSidebarRow(selection)
                            }
                        )
                    }
                }
            }

            if viewModel.isGitRepository == false {
                Section("Git Changes") {
                    Text(viewModel.folderWorkspaceReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.groupedChangedFiles.isEmpty {
                Section("Git Changes") {
                    Text("No changed files match search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.groupedChangedFiles, id: \.0) { group in
                    Section {
                        ForEach(group.1) { file in
                            SidebarChangedFileRow(
                                file: file,
                                viewModel: viewModel,
                                selection: .changedFile(fileID: file.id, path: file.path),
                                isSelected: sidebarSelection == .changedFile(fileID: file.id, path: file.path),
                                onSelect: { selection in
                                    selectSidebarRow(selection)
                                }
                            )
                        }
                    } header: {
                        SidebarStageGroupHeader(
                            stageState: group.0,
                            files: group.1,
                            viewModel: viewModel
                        )
                    }
                }
            }

            if viewModel.isGitRepository {
                Section("Commit") {
                    SidebarCommitPanel(viewModel: viewModel)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        }
        .listStyle(.sidebar)
    }

    func selectSidebarRow(_ selection: DashboardSidebarSelection) {
        sidebarSelection = selection

        switch selection {
        case .repositoryFile, .changedFile:
            viewModel.selectFile(path: selection.path)
        case .commit(let hash):
            if let commit = viewModel.commitHistory.first(where: { $0.hash == hash }) {
                viewModel.selectCommit(commit)
            }
        }
    }

    func syncSidebarSelectionWithViewModel() {
        if let selectedCommitHash = viewModel.selectedCommitHash {
            sidebarSelection = .commit(hash: selectedCommitHash)
            return
        }

        guard let selectedPath = viewModel.selectedFilePath else {
            sidebarSelection = nil
            return
        }

        if let sidebarSelection, sidebarSelection.path == selectedPath {
            return
        }

        if let changedFile = viewModel.selectedFile {
            sidebarSelection = .changedFile(fileID: changedFile.id, path: selectedPath)
            return
        }

        sidebarSelection = .repositoryFile(path: selectedPath)
    }

    var repositoryTreeRoots: [RepositoryTreeNode] {
        RepositoryTreeNode.build(from: viewModel.filteredRepositoryFiles)
    }

    var canvas: some View {
        Group {
            if viewModel.isHistoryViewPresented {
                commitHistoryCanvas
            } else if viewModel.selectedFilePath != nil {
                if viewModel.selectedIsDeleted {
                    if shouldShowDiffCanvas {
                        diffCanvas(fileName: viewModel.selectedFileName)
                    } else {
                        deletedFileCanvas(fileName: viewModel.selectedFileName)
                    }
                } else if viewModel.selectedIsImagePreviewable {
                    imagePreviewCanvas(fileName: viewModel.selectedFileName)
                } else if viewModel.selectedIsVideoPreviewable {
                    videoPreviewCanvas(fileName: viewModel.selectedFileName)
                } else if viewModel.selectedIsPDFPreviewable {
                    pdfPreviewCanvas(fileName: viewModel.selectedFileName)
                } else if viewModel.selectedIsMarkdown {
                    markdownCanvas
                } else if viewModel.selectedIsEditableText {
                    textEditorCanvas(fileName: viewModel.selectedFileName)
                } else if shouldShowDiffCanvas {
                    diffCanvas(fileName: viewModel.selectedFileName)
                } else {
                    nonMarkdownCanvas(fileName: viewModel.selectedFileName)
                }
            } else {
                EmptyCanvasState()
            }
        }
    }

    var commitHistoryCanvas: some View {
        HSplitView {
            historyCommitList
                .frame(minWidth: 420, idealWidth: 420, maxWidth: 420)

            commitDetailsPane
                .frame(minWidth: 420)
        }
        .navigationTitle("History")
    }

    var historyCommitList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if viewModel.commitHistory.isEmpty {
                    Text("No commits on this branch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(16)
                } else {
                    ForEach(viewModel.commitHistory) { commit in
                        Button {
                            viewModel.selectCommit(commit)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(commit.shortHash)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(commit.subject)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(3)
                                Text(commit.author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(
                                viewModel.selectedCommitHash == commit.hash
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
        }
        .background(.thinMaterial)
    }

    var commitDetailsPane: some View {
        Group {
            if viewModel.isCommitDetailsLoading {
                ProgressView("Loading commit...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let details = viewModel.selectedCommitDetails {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(details.summary.subject)
                                .font(.title2.weight(.semibold))
                                .textSelection(.enabled)

                            HStack(spacing: 12) {
                                Text(details.summary.shortHash)
                                    .font(.callout.monospaced())
                                Text(details.summary.author)
                                Text(details.summary.date)
                            }
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                            if details.body.isEmpty == false {
                                Text(details.body)
                                    .textSelection(.enabled)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Changed Files")
                                .font(.headline)

                            ForEach(details.changedFiles) { file in
                                HStack(spacing: 8) {
                                    ChangeBadge(changeType: file.changeType)
                                    Text(file.displayPath)
                                        .lineLimit(1)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Diff")
                                .font(.headline)

                            if details.diffLines.isEmpty {
                                Text("No textual diff available for this commit.")
                                    .foregroundStyle(.secondary)
                            } else {
                                UnifiedDiffView(lines: details.diffLines)
                                    .frame(minHeight: 360)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(details.summary.shortHash)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                    Text("Select a commit")
                        .font(.headline)
                    Text("Pick a commit from History to inspect its metadata and diff.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var markdownCanvas: some View {
        Group {
            switch viewModel.canvasMode {
            case .editor:
                MarkdownEditorView(text: $viewModel.editorText)
                    .onChange(of: viewModel.editorText) {
                        viewModel.editorTextDidChange()
                    }
            case .preview:
                MarkdownPreviewView(
                    markdownText: viewModel.editorText,
                    baseURL: viewModel.selectedFileDirectoryURL
                )
            case .split:
                HSplitView {
                    MarkdownEditorView(text: $viewModel.editorText)
                        .onChange(of: viewModel.editorText) {
                            viewModel.editorTextDidChange()
                        }
                    MarkdownPreviewView(
                        markdownText: viewModel.editorText,
                        baseURL: viewModel.selectedFileDirectoryURL
                    )
                }
            }
        }
    }

    func nonMarkdownCanvas(fileName: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
            Text(fileName)
                .font(.headline)
            Text("Preview is not available for this file type.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func textEditorCanvas(fileName: String) -> some View {
        Group {
            if shouldShowDiffCanvas {
                HSplitView {
                    plainTextEditor
                    diffCanvas(fileName: fileName)
                }
            } else {
                plainTextEditor
            }
        }
        .navigationTitle(fileName)
    }

    var plainTextEditor: some View {
        MarkdownEditorView(text: $viewModel.editorText, showsFormatToolbar: false)
            .id(readOnlyCanvasIdentity)
            .overlay(alignment: .topTrailing) {
                Text("Text Editor")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
            }
            .onChange(of: viewModel.editorText) {
                viewModel.editorTextDidChange()
            }
    }

    func imagePreviewCanvas(fileName: String) -> some View {
        FileImagePreview(fileURL: viewModel.selectedFileURL, fileName: fileName)
            .id(readOnlyCanvasIdentity)
            .navigationTitle(fileName)
    }

    func videoPreviewCanvas(fileName: String) -> some View {
        FileVideoPreview(fileURL: viewModel.selectedFileURL, fileName: fileName)
            .id(readOnlyCanvasIdentity)
            .navigationTitle(fileName)
    }

    func pdfPreviewCanvas(fileName: String) -> some View {
        FilePDFPreview(fileURL: viewModel.selectedFileURL, fileName: fileName)
            .id(readOnlyCanvasIdentity)
            .navigationTitle(fileName)
    }

    func diffCanvas(fileName: String) -> some View {
        Group {
            if viewModel.isDiffLoading, viewModel.selectedDiffLines.isEmpty {
                ProgressView("Loading diff...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.selectedDiffLines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 28))
                    Text("No textual diff available")
                        .font(.headline)
                    Text("This file may be unchanged in text content or binary.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                UnifiedDiffView(lines: viewModel.selectedDiffLines)
                    .id(diffCanvasIdentity)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                if viewModel.isDiffLoading, viewModel.selectedDiffLines.isEmpty == false {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("Diff")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .padding(10)
        }
        .navigationTitle(fileName)
    }

    func deletedFileCanvas(fileName: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 28))
            Text(fileName)
                .font(.headline)
            Text("This file is deleted in the current working tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var shouldShowDiffCanvas: Bool {
        guard
            viewModel.selectedFile != nil,
            viewModel.selectedIsBinary == false,
            viewModel.selectedIsMarkdown == false || viewModel.selectedIsDeleted
        else {
            return false
        }

        return viewModel.isDiffLoading || viewModel.selectedDiffLines.isEmpty == false
    }

    var readOnlyCanvasIdentity: String {
        let repoPath = viewModel.repositoryContext?.repoURL.path ?? "repo"
        let filePath = viewModel.selectedFilePath ?? "none"
        return "readonly|\(repoPath)|\(filePath)"
    }

    var diffCanvasIdentity: String {
        let repoPath = viewModel.repositoryContext?.repoURL.path ?? "repo"
        let selectedFileID = viewModel.selectedFile?.id ?? "none"
        return "diff|\(repoPath)|\(selectedFileID)"
    }

    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inspector")
                    .font(.headline)

                if let context = viewModel.repositoryContext {
                    InfoRow(label: "Repository", value: context.repoName)
                    InfoRow(label: "Branch", value: context.branchName)
                } else {
                    Text("No repository selected")
                        .foregroundStyle(.secondary)
                }

                Divider()

                if let details = viewModel.selectedCommitDetails {
                    InfoRow(label: "Commit", value: details.summary.hash)
                    InfoRow(label: "Author", value: details.summary.author)
                    InfoRow(label: "Date", value: details.summary.date)
                    InfoRow(label: "Files", value: "\(details.changedFiles.count)")
                } else if let selectedPath = viewModel.selectedDisplayPath {
                    InfoRow(label: "Path", value: selectedPath)
                    InfoRow(label: "Status", value: viewModel.selectedStatusText)
                    InfoRow(label: "Stage", value: viewModel.selectedStageText)
                    InfoRow(label: "Type", value: viewModel.selectedTypeText)
                    InfoRow(label: "Tracking", value: viewModel.selectedTrackedText)

                    if let oldPath = viewModel.selectedOldPath {
                        InfoRow(label: "Renamed From", value: oldPath)
                    }
                } else {
                    Text("Select a file to inspect metadata.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Next panels")
                        .font(.subheadline)
                        .bold()
                    Text("Diff Inspector is active in the canvas for changed text files.")
                        .foregroundStyle(.secondary)
                    Text("AI Commit Panel (coming next milestone)")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .background(.thinMaterial)
    }

    //MARK: -Rows
    struct SidebarCommitPanel: View {
        @ObservedObject var viewModel: DashboardViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Summary (required)", text: $viewModel.commitSummary)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isGitOperationInProgress)

                TextEditor(text: $viewModel.commitDescription)
                    .font(.body)
                    .frame(minHeight: 80, idealHeight: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .disabled(viewModel.isGitOperationInProgress)

                HStack {
                    Text("\(viewModel.selectedCommitFileCount) staged of \(viewModel.changedFiles.count) changed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    viewModel.commitSelectedFiles()
                } label: {
                    HStack {
                        if viewModel.activeGitOperationLabel == "Committing..." {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.commitButtonTitle)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.canCommitSelectedFiles == false)

                if viewModel.changedFiles.isEmpty {
                    Text("No changes to commit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if viewModel.selectedCommitFileCount == 0 {
                    Text("Stage files before committing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let conflictWarningText = viewModel.conflictWarningText {
                    Label(conflictWarningText, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    struct RepositoryTreeNode: Identifiable, Hashable {
        struct MutableTreeNode {
            var path: String
            var name: String
            var file: RepositoryFile?
            var children: [String: MutableTreeNode] = [:]
        }

        let path: String
        let name: String
        let file: RepositoryFile?
        let children: [RepositoryTreeNode]

        var id: String { path }
        var isDirectory: Bool { file == nil || !children.isEmpty }

        static func build(from files: [RepositoryFile]) -> [RepositoryTreeNode] {
            var root = MutableTreeNode(path: "", name: "", file: nil, children: [:])

            for file in files {
                let components = file.path.split(separator: "/").map(String.init)
                guard components.isEmpty == false else {
                    continue
                }

                var currentPath = ""
                insert(file: file, components: components, index: 0, currentPath: &currentPath, into: &root)
            }

            return root.children.values
                .map { finalize($0) }
                .sorted { sortNodes(lhs: $0, rhs: $1) }
        }

        private static func insert(
            file: RepositoryFile,
            components: [String],
            index: Int,
            currentPath: inout String,
            into node: inout MutableTreeNode
        ) {
            let name = components[index]
            currentPath = currentPath.isEmpty ? name : "\(currentPath)/\(name)"

            if node.children[name] == nil {
                node.children[name] = MutableTreeNode(path: currentPath, name: name, file: nil, children: [:])
            }

            guard var child = node.children[name] else {
                return
            }

            let isLeaf = index == components.count - 1
            if isLeaf {
                child.file = file
                node.children[name] = child
                return
            }

            insert(file: file, components: components, index: index + 1, currentPath: &currentPath, into: &child)
            node.children[name] = child
        }

        private static func finalize(_ node: MutableTreeNode) -> RepositoryTreeNode {
            let finalizedChildren = node.children.values
                .map { finalize($0) }
                .sorted { sortNodes(lhs: $0, rhs: $1) }

            return RepositoryTreeNode(
                path: node.path,
                name: node.name,
                file: finalizedChildren.isEmpty ? node.file : nil,
                children: finalizedChildren
            )
        }

        private static func sortNodes(lhs: RepositoryTreeNode, rhs: RepositoryTreeNode) -> Bool {
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    struct SidebarRepositoryTreeRow: View {
        let node: RepositoryTreeNode
        @ObservedObject var viewModel: DashboardViewModel
        let selectedRow: DashboardSidebarSelection?
        let onSelect: (DashboardSidebarSelection) -> Void

        var body: some View {
            if node.isDirectory {
                DisclosureGroup {
                    ForEach(node.children) { child in
                        SidebarRepositoryTreeRow(
                            node: child,
                            viewModel: viewModel,
                            selectedRow: selectedRow,
                            onSelect: onSelect
                        )
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 22, height: 22)
                        Text(node.name)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            } else if let file = node.file {
                SidebarRepositoryFileRow(
                    file: file,
                    changeType: viewModel.changeType(for: file.path),
                    selection: .repositoryFile(path: file.path),
                    isSelected: selectedRow == .repositoryFile(path: file.path),
                    onSelect: onSelect
                )
            }
        }
    }

    struct SidebarChangedFileRow: View {
        let file: ChangedFile
        @ObservedObject var viewModel: DashboardViewModel
        let selection: DashboardSidebarSelection
        let isSelected: Bool
        let onSelect: (DashboardSidebarSelection) -> Void

        var body: some View {
            HStack(spacing: 6) {
                Button {
                    onSelect(selection)
                } label: {
                    HStack(spacing: 4) {
                        ChangeBadge(changeType: file.changeType)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.fileName)
                                .lineLimit(1)
                            Text(file.relativeDirectory.isEmpty ? file.path : file.relativeDirectory)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)

                if file.stageState == .conflicted {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .help("Resolve conflict before committing or syncing")
                } else {
                    if file.canStage {
                        Button {
                            viewModel.stageFile(file)
                        } label: {
                            Image(systemName: "plus.square")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 18, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isGitOperationInProgress)
                        .help("Stage file")
                    }

                    if file.canUnstage {
                        Button {
                            viewModel.unstageFile(file)
                        } label: {
                            Image(systemName: "minus.square")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 18, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isGitOperationInProgress)
                        .help("Unstage file")
                    }
                }
            }
            .padding(.trailing, 10)
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
    }

    struct SidebarStageGroupHeader: View {
        let stageState: GitFileStageState
        let files: [ChangedFile]
        @ObservedObject var viewModel: DashboardViewModel

        private var stageableFiles: [ChangedFile] {
            files.filter { $0.canStage && $0.stageState != .conflicted }
        }

        private var unstageableFiles: [ChangedFile] {
            files.filter { $0.canUnstage && $0.stageState != .conflicted }
        }

        var body: some View {
            HStack(spacing: 8) {
                Text(stageState.displayName)
                Text("\(files.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()

                if stageableFiles.isEmpty == false {
                    Button {
                        viewModel.stageFiles(stageableFiles)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isGitOperationInProgress)
                    .help("Stage all in group")
                }

                if unstageableFiles.isEmpty == false {
                    Button {
                        viewModel.unstageFiles(unstageableFiles)
                    } label: {
                        Image(systemName: "minus.square.on.square")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isGitOperationInProgress)
                    .help("Unstage all in group")
                }
            }
            .padding(.trailing, 10)
        }
    }

    struct SidebarFileTypeFilterMenu: View {
        @ObservedObject var viewModel: DashboardViewModel

        var body: some View {
            HStack(spacing: 10) {
                Text("Filter")
                    .font(.body.weight(.semibold))

                Menu {
                    Button {
                        viewModel.clearFileTypeFilters()
                    } label: {
                        HStack {
                            Text("No Filter")
                            Spacer()
                            if viewModel.selectedFileTypeFilters.isEmpty {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(viewModel.fileTypeFilterOptions) { option in
                        Button {
                            viewModel.toggleFileTypeFilter(option.key)
                        } label: {
                            HStack {
                                Text(option.title)
                                Spacer()
                                if viewModel.isFileTypeFilterSelected(option.key) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(viewModel.fileTypeFilterSummary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                }

                Spacer(minLength: 0)
            }
        }
    }

    struct SidebarRepositoryFileRow: View {
        let file: RepositoryFile
        let changeType: GitChangeType?
        let selection: DashboardSidebarSelection
        let isSelected: Bool
        let onSelect: (DashboardSidebarSelection) -> Void

        var body: some View {
            Button {
                onSelect(selection)
            } label: {
                HStack(spacing: 4) {
                    if let changeType {
                        ChangeBadge(changeType: changeType)
                    } else {
                        Image(systemName: file.isMarkdown ? "doc.text" : "doc")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.fileName)
                            .lineLimit(1)
                        Text(file.relativeDirectory.isEmpty ? file.path : file.relativeDirectory)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        }
    }

    struct EmptyCanvasState: View {
        var body: some View {
            VStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 28))
                Text("Select a file")
                    .font(.headline)
                Text("Open a folder and pick a file from the sidebar.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    struct InfoRow: View {
        let label: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    struct ChangeBadge: View {
        let changeType: GitChangeType

        var body: some View {
            Text(changeType.badgeText)
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .foregroundStyle(.white)
        }

        private var backgroundColor: Color {
            switch changeType {
            case .modified:
                return .yellow
            case .added:
                return .green
            case .deleted:
                return .red
            case .renamed:
                return .orange
            case .untracked:
                return .green
            case .conflicted:
                return .red
            }
        }
    }

    struct LineNumberedTextView: View {
        let text: String

        var body: some View {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        LineNumberedTextRow(
                            lineNumber: index + 1,
                            lineText: line
                        )
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
            .background(Color(nsColor: .textBackgroundColor))
            .textSelection(.enabled)
        }

        private var lines: [String] {
            let splitLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            return splitLines.isEmpty ? [""] : splitLines
        }
    }

    struct LineNumberedTextRow: View {
        let lineNumber: Int
        let lineText: String

        var body: some View {
            HStack(spacing: 0) {
                Text("\(lineNumber)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
                    .padding(.trailing, 10)

                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 1)
                    .padding(.vertical, 2)

                Text(lineText.isEmpty ? " " : lineText)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 10)
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct FileImagePreview: View {
        let fileURL: URL?
        let fileName: String

        var body: some View {
            Group {
                if let fileURL, let image = NSImage(contentsOf: fileURL) {
                    ScrollView([.vertical, .horizontal]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(24)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                } else {
                    unavailablePreview(fileName: fileName, systemImage: "photo")
                }
            }
            .overlay(alignment: .topTrailing) {
                previewBadge("Image")
            }
        }
    }

    struct FileVideoPreview: View {
        let fileURL: URL?
        let fileName: String

        var body: some View {
            Group {
                if let fileURL {
                    VideoPlayer(player: AVPlayer(url: fileURL))
                        .background(.black)
                } else {
                    unavailablePreview(fileName: fileName, systemImage: "play.rectangle")
                }
            }
            .overlay(alignment: .topTrailing) {
                previewBadge("Video")
            }
        }
    }

    struct FilePDFPreview: View {
        let fileURL: URL?
        let fileName: String

        var body: some View {
            Group {
                if let fileURL {
                    PDFPreviewRepresentable(fileURL: fileURL)
                } else {
                    unavailablePreview(fileName: fileName, systemImage: "doc.richtext")
                }
            }
            .overlay(alignment: .topTrailing) {
                previewBadge("PDF")
            }
        }
    }

    struct PDFPreviewRepresentable: NSViewRepresentable {
        let fileURL: URL

        func makeNSView(context: Context) -> PDFView {
            let pdfView = PDFView()
            pdfView.autoScales = true
            pdfView.displayMode = .singlePageContinuous
            pdfView.displaysPageBreaks = true
            pdfView.document = PDFDocument(url: fileURL)
            return pdfView
        }

        func updateNSView(_ pdfView: PDFView, context: Context) {
            if pdfView.document?.documentURL != fileURL {
                pdfView.document = PDFDocument(url: fileURL)
            }
        }
    }

    static func previewBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .padding(10)
    }

    static func unavailablePreview(fileName: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
            Text(fileName)
                .font(.headline)
            Text("Preview could not be loaded.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    struct UnifiedDiffView: View {
        let lines: [DiffLine]

        var body: some View {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        UnifiedDiffRow(line: line)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
            .background(Color(nsColor: .textBackgroundColor))
            .textSelection(.enabled)
        }
    }

    struct UnifiedDiffRow: View {
        let line: DiffLine

        var body: some View {
            HStack(spacing: 0) {
                lineNumberCell(line.oldLineNumber)
                lineNumberCell(line.newLineNumber)

                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 1)
                    .padding(.vertical, 2)

                Text(prefixText)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(prefixColor)
                    .frame(width: 18, alignment: .center)
                    .padding(.leading, 8)

                Text(lineText)
                    .font(.system(size: 14, weight: line.kind == .hunk ? .semibold : .regular, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(textColor)
                    .padding(.leading, 2)
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
        }

        private var lineText: String {
            line.text.isEmpty ? " " : line.text
        }

        private var prefixText: String {
            switch line.kind {
            case .added:
                return "+"
            case .removed:
                return "-"
            case .context:
                return " "
            case .hunk, .meta:
                return " "
            }
        }

        private var prefixColor: Color {
            switch line.kind {
            case .added:
                return .green
            case .removed:
                return .red
            case .hunk:
                return .blue
            case .meta, .context:
                return .secondary
            }
        }

        private var textColor: Color {
            switch line.kind {
            case .meta:
                return .secondary
            case .hunk:
                return .blue
            default:
                return .primary
            }
        }

        private var backgroundColor: Color {
            switch line.kind {
            case .added:
                return Color.green.opacity(0.14)
            case .removed:
                return Color.red.opacity(0.14)
            case .hunk:
                return Color.blue.opacity(0.12)
            default:
                return Color.clear
            }
        }

        private func lineNumberCell(_ number: Int?) -> some View {
            Text(number.map(String.init) ?? "")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
                .padding(.trailing, 10)
        }
    }

    //MARK: -Formatting
}
