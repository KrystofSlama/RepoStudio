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

    let openRepository: () -> Void
    let openRecentRepository: (String) -> Void
    let refreshRepositoryState: () -> Void
    let performPrimarySyncAction: () -> Void
    let showNewBranchSheet: () -> Void
    let toggleInspector: () -> Void
    let toggleSidebar: () -> Void
    let setCanvasMode: (DashboardViewModel.CanvasMode) -> Void

    init(viewModel: DashboardViewModel) {
        recentRepositoryPaths = viewModel.recentRepositoryPaths
        isRepositoryOpen = viewModel.repositoryContext != nil
        isInspectorVisible = viewModel.isInspectorVisible
        primarySyncActionTitle = viewModel.primarySyncActionTitle
        canPerformPrimarySyncAction = viewModel.canPerformPrimarySyncAction

        openRepository = { [weak viewModel] in
            viewModel?.openRepository()
        }
        openRecentRepository = { [weak viewModel] path in
            viewModel?.openRecentRepository(at: path)
        }
        refreshRepositoryState = { [weak viewModel] in
            viewModel?.refreshRepositoryState()
        }
        performPrimarySyncAction = { [weak viewModel] in
            viewModel?.performPrimarySyncAction()
        }
        showNewBranchSheet = { [weak viewModel] in
            viewModel?.showNewBranchSheet()
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
        ToolbarItemGroup {
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

            Divider()

            Button(commandActions?.primarySyncActionTitle ?? "Sync") {
                commandActions?.performPrimarySyncAction()
            }
            .disabled(commandActions?.canPerformPrimarySyncAction != true)

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

extension DashboardView {
    //MARK: -Subviews
    var sidebar: some View {
        List {
            SidebarRepositoryHeader(viewModel: viewModel)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

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
                    Section("Git Changes · \(group.0.displayName)") {
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
        viewModel.selectFile(path: selection.path)
    }

    func syncSidebarSelectionWithViewModel() {
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
            if viewModel.selectedFilePath != nil {
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

                if let selectedPath = viewModel.selectedDisplayPath {
                    InfoRow(label: "Path", value: selectedPath)
                    InfoRow(label: "Status", value: viewModel.selectedStatusText)
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
    struct BranchPickerMenu: View {
        @ObservedObject var viewModel: DashboardViewModel

        var body: some View {
            Menu {
                Button("New Branch...") {
                    viewModel.showNewBranchSheet()
                }
                .disabled(viewModel.isGitOperationInProgress)

                Divider()

                if viewModel.localBranches.isEmpty {
                    Text("No Local Branches")
                } else {
                    ForEach(viewModel.localBranches) { branch in
                        Button {
                            viewModel.checkoutBranch(branch)
                        } label: {
                            HStack {
                                Text(branch.name)
                                if branch.isCurrent {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(branch.isCurrent || viewModel.isGitOperationInProgress)
                    }
                }

                if viewModel.remoteBranches.isEmpty == false {
                    Divider()
                    Text("Remote Branches")
                    ForEach(viewModel.remoteBranches) { branch in
                        Button(branch.name) {}
                            .disabled(true)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    Text("Branch")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .help("Switch or create branches")
        }
    }

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
                    Text("\(viewModel.selectedCommitFileCount) of \(viewModel.changedFiles.count) selected")
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
                }
            }
        }
    }

    struct SidebarRepositoryHeader: View {
        @ObservedObject var viewModel: DashboardViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Current Repository", systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.refreshRepositoryState()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh repository status")
                }

                if let context = viewModel.repositoryContext {
                    Text(context.repoName)
                        .font(.headline)

                    if viewModel.isGitRepository {
                        HStack(spacing: 8) {
                            BranchPickerMenu(viewModel: viewModel)

                            Button {
                                viewModel.performPrimarySyncAction()
                            } label: {
                                Label(viewModel.primarySyncActionTitle, systemImage: viewModel.primarySyncActionSymbolName)
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.canPerformPrimarySyncAction == false)
                            .help(viewModel.primarySyncActionTitle)
                        }

                        Text(context.branchName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(viewModel.syncStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(viewModel.folderWorkspaceReason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No repository open")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open Repository") {
                        viewModel.openRepository()
                    }
                }

                Text(viewModel.sidebarCountSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    viewModel.toggleCommitFileSelection(file)
                } label: {
                    Image(systemName: viewModel.isCommitFileSelected(file) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(viewModel.isCommitFileSelected(file) ? Color.accentColor : .secondary)
                        .frame(width: 18, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGitOperationInProgress)
                .help(viewModel.isCommitFileSelected(file) ? "Exclude from commit" : "Include in commit")

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
            }
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
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
