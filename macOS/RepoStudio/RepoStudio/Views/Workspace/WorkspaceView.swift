//
//  WorkspaceView.swift
//  RepoStudio
//

import AppKit
import SwiftUI

@MainActor
final class WorkspaceSession: Identifiable {
    let id = UUID()
    let viewModel: DashboardViewModel
    var repositoryPathHint: String?
    var didAutoPromptRepositoryPicker = false

    init(repositoryPathHint: String? = nil) {
        self.repositoryPathHint = repositoryPathHint
        viewModel = DashboardViewModel(repositoryService: GitCLIRepositoryService())
    }

    init(repositoryPathHint: String? = nil, repositoryService: RepositoryService) {
        self.repositoryPathHint = repositoryPathHint
        viewModel = DashboardViewModel(repositoryService: repositoryService)
    }
}

@MainActor
struct WorkspaceCommandActions {
    let recentRepositoryPaths: [String]
    let openRepositoryInNewTab: () -> Void
    let openRecentRepositoryInNewTab: (String) -> Void
}

private struct WorkspaceCommandActionsKey: FocusedValueKey {
    typealias Value = WorkspaceCommandActions
}

extension FocusedValues {
    var workspaceCommandActions: WorkspaceCommandActions? {
        get { self[WorkspaceCommandActionsKey.self] }
        set { self[WorkspaceCommandActionsKey.self] = newValue }
    }
}

@MainActor
struct WorkspaceView: View {
    //MARK: -State
    @Environment(\.scenePhase) var scenePhase
    @State var sessions: [WorkspaceSession] = []
    @State var selectedSessionID: WorkspaceSession.ID?
    @State var didBootstrapWorkspace = false

    let recentRepositoriesKey = "repoDraft.recentRepositories"
    let workspaceTabRepositoryPathsKey = "repoDraft.workspaceTabRepositoryPaths"
    let workspaceSelectedRepositoryPathKey = "repoDraft.workspaceSelectedRepositoryPath"

    //MARK: -Body
    var body: some View {
        workspaceCanvas
            .onAppear {
                bootstrapWorkspaceIfNeeded()
            }
            .onChange(of: selectedSessionID, initial: false) {
                promptForRepositoryIfNeeded()
                persistWorkspaceState()
            }
            .onChange(of: scenePhase, initial: false) {
                if scenePhase != .active {
                    persistWorkspaceState()
                }
            }
            .focusedSceneValue(
                \.workspaceCommandActions,
                workspaceCommandActions
            )
    }

    //MARK: -Actions
    var selectedSession: WorkspaceSession? {
        guard let selectedSessionID else {
            return sessions.first
        }

        return sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first
    }

    var recentRepositoryPaths: [String] {
        if let selectedSession, selectedSession.viewModel.recentRepositoryPaths.isEmpty == false {
            return selectedSession.viewModel.recentRepositoryPaths
        }

        return UserDefaults.standard.stringArray(forKey: recentRepositoriesKey) ?? []
    }

    var workspaceCommandActions: WorkspaceCommandActions {
        WorkspaceCommandActions(
            recentRepositoryPaths: recentRepositoryPaths,
            openRepositoryInNewTab: {
                openRepositoryInNewTab()
            },
            openRecentRepositoryInNewTab: { path in
                openRecentRepositoryInNewTab(path: path)
            }
        )
    }

    func bootstrapWorkspaceIfNeeded() {
        guard didBootstrapWorkspace == false else {
            return
        }

        didBootstrapWorkspace = true

        if restoreWorkspaceStateIfPossible() {
            scheduleFallbackPromptForEmptySelectedTab()
            return
        }

        if let lastRepositoryPath = recentRepositoryPaths.first {
            addRepositoryTab(path: lastRepositoryPath, select: true, suppressOpenErrorAlert: true)
            scheduleFallbackPromptForEmptySelectedTab()
        } else {
            addEmptyTab(select: true)
            promptForRepositoryIfNeeded()
        }
    }

    func addEmptyTab(select: Bool) {
        let session = WorkspaceSession(repositoryPathHint: nil)
        sessions.append(session)
        if select {
            selectedSessionID = session.id
        }
        persistWorkspaceState()
    }

    func addRepositoryTab(path: String, select: Bool, suppressOpenErrorAlert: Bool = false) {
        let session = WorkspaceSession(repositoryPathHint: path)
        sessions.append(session)
        if select {
            selectedSessionID = session.id
        }

        session.viewModel.openRepository(
            atPath: path,
            suppressErrorAlert: suppressOpenErrorAlert
        )
        persistWorkspaceState()
    }

    func addRepositoryTab(url: URL, select: Bool, suppressOpenErrorAlert: Bool = false) {
        let session = WorkspaceSession(repositoryPathHint: url.path)
        sessions.append(session)
        if select {
            selectedSessionID = session.id
        }

        session.viewModel.openRepository(
            at: url,
            suppressErrorAlert: suppressOpenErrorAlert
        )
        persistWorkspaceState()
    }

    func closeSession(_ id: WorkspaceSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            return
        }

        let isSelected = selectedSessionID == id
        sessions.remove(at: index)
        persistWorkspaceState()

        if sessions.isEmpty {
            addEmptyTab(select: true)
            promptForRepositoryIfNeeded()
            return
        }

        guard isSelected else {
            return
        }

        let fallbackIndex = min(index, sessions.count - 1)
        selectedSessionID = sessions[fallbackIndex].id
        promptForRepositoryIfNeeded()
    }

    func selectSession(_ id: WorkspaceSession.ID) {
        selectedSessionID = id
        promptForRepositoryIfNeeded()
    }

    func openRepositoryInNewTab() {
        let panel = NSOpenPanel()
        panel.title = "Open Git Repository"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        addRepositoryTab(url: url, select: true)
    }

    func openRecentRepositoryInNewTab(path: String) {
        addRepositoryTab(path: path, select: true)
    }

    func restoreWorkspaceStateIfPossible() -> Bool {
        guard let savedPaths = UserDefaults.standard.stringArray(forKey: workspaceTabRepositoryPathsKey), savedPaths.isEmpty == false else {
            return false
        }

        sessions.removeAll(keepingCapacity: true)

        for path in savedPaths {
            addRepositoryTab(path: path, select: false, suppressOpenErrorAlert: true)
        }

        let selectedPath = UserDefaults.standard.string(forKey: workspaceSelectedRepositoryPathKey)
        if let selectedPath,
           let matchingSession = sessions.first(where: { $0.repositoryPathHint == selectedPath }) {
            selectedSessionID = matchingSession.id
        } else {
            selectedSessionID = sessions.first?.id
        }

        return sessions.isEmpty == false
    }

    func scheduleFallbackPromptForEmptySelectedTab() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            promptForRepositoryIfNeeded()
        }
    }

    func promptForRepositoryIfNeeded() {
        guard let selectedSession else {
            return
        }

        if let repositoryPath = selectedSession.viewModel.repositoryContext?.repoURL.path {
            selectedSession.repositoryPathHint = repositoryPath
            persistWorkspaceState()
            return
        }

        if selectedSession.viewModel.isOpeningRepository {
            return
        }

        guard selectedSession.didAutoPromptRepositoryPicker == false else {
            return
        }

        selectedSession.didAutoPromptRepositoryPicker = true
        selectedSession.viewModel.openRepository()
    }

    func persistWorkspaceState() {
        let repositoryPaths = sessions.compactMap { session in
            session.viewModel.repositoryContext?.repoURL.path ?? session.repositoryPathHint
        }

        UserDefaults.standard.set(repositoryPaths, forKey: workspaceTabRepositoryPathsKey)

        let selectedPath = selectedSession?.viewModel.repositoryContext?.repoURL.path ?? selectedSession?.repositoryPathHint
        UserDefaults.standard.set(selectedPath, forKey: workspaceSelectedRepositoryPathKey)
    }

    func syncSelectedSessionRepositoryPathHint() {
        guard
            let selectedSession,
            let repoPath = selectedSession.viewModel.repositoryContext?.repoURL.path
        else {
            return
        }

        selectedSession.repositoryPathHint = repoPath
        persistWorkspaceState()
    }
}
