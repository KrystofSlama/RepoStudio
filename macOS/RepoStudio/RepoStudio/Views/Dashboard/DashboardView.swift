//
//  DashboardView.swift
//  RepoStudio
//

import SwiftUI

enum DashboardSidebarSelection: Hashable {
    case repositoryFile(path: String)
    case changedFile(fileID: String, path: String)
    case commit(hash: String)

    var path: String? {
        switch self {
        case .repositoryFile(let path):
            return path
        case .changedFile(_, let path):
            return path
        case .commit:
            return nil
        }
    }
}

struct DashboardView: View {
    //MARK: -State
    @ObservedObject var viewModel: DashboardViewModel
    @State var sidebarSelection: DashboardSidebarSelection?
    let topDetailBar: AnyView?

    init(viewModel: DashboardViewModel, topDetailBar: AnyView? = nil) {
        self.viewModel = viewModel
        self.topDetailBar = topDetailBar
    }

    //MARK: -Body
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            VStack(spacing: 0) {
                if let topDetailBar {
                    topDetailBar
                }

                HSplitView {
                    canvas
                        .frame(minWidth: 500)

                    if viewModel.isInspectorVisible {
                        inspector
                            .frame(minWidth: 250, idealWidth: 300, maxWidth: 360)
                    }
                }
            }
        }
        .toolbar {
            DashboardToolbar(viewModel: viewModel)
        }
        //.navigationTitle(viewModel.windowTitle)
        .focusedSceneValue(
            \.dashboardCommandActions,
            DashboardCommandActions(viewModel: viewModel)
        )
        .onAppear {
            syncSidebarSelectionWithViewModel()
        }
        .onChange(of: viewModel.selectedFilePath) {
            syncSidebarSelectionWithViewModel()
        }
        .onChange(of: viewModel.selectedCommitHash) {
            syncSidebarSelectionWithViewModel()
        }
        .onChange(of: viewModel.repositoryContext?.repoURL.path) {
            sidebarSelection = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            viewModel.reloadApplicationSettings()
        }
        .sheet(isPresented: $viewModel.isNewBranchSheetPresented) {
            NewBranchSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isGitHubAccountSheetPresented) {
            GitHubAccountSheet(viewModel: viewModel)
        }
        .alert(
            "Delete Branch?",
            isPresented: Binding(
                get: { viewModel.branchDeletionCandidate != nil },
                set: { value in
                    if value == false {
                        viewModel.cancelDeleteBranch()
                    }
                }
            )
        ) {
            Button("Delete Branch", role: .destructive) {
                viewModel.confirmDeleteBranch()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteBranch()
            }
        } message: {
            let branchName = viewModel.branchDeletionCandidate?.name ?? "this branch"
            Text("Delete local branch \(branchName)? This will not delete the remote branch.")
        }
        .alert(
            "Repository Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { value in
                    if value == false {
                        viewModel.errorMessage = nil
                        viewModel.shouldOfferInstallToolsAction = false
                        viewModel.shouldOfferGitHubTokenAction = false
                    }
                }
            )
        ) {
            if viewModel.shouldOfferInstallToolsAction {
                Button("Install Tools") {
                    viewModel.installXcodeCommandLineTools()
                }
            }

            if viewModel.shouldOfferGitHubTokenAction {
                Button("Add Token") {
                    viewModel.errorMessage = nil
                    viewModel.shouldOfferInstallToolsAction = false
                    viewModel.shouldOfferGitHubTokenAction = false
                    viewModel.showGitHubAccountSheet()
                }
            }

            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
                viewModel.shouldOfferInstallToolsAction = false
                viewModel.shouldOfferGitHubTokenAction = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    //MARK: -Actions
}
