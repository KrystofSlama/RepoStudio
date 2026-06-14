//
//  RepoStudioTests.swift
//  RepoStudioTests
//
//  Created by Kryštof Sláma on 28.05.2026.
//

import Testing
import Foundation
import AppKit
@testable import RepoStudio

struct RepoStudioTests {

    @Test func headingOnEmptyLineInsertsMarkerAtCursor() async throws {
        let result = MarkdownEditorView.MarkdownFormatter.apply(
            action: .heading2,
            to: "",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(result.text == "## ")
        #expect(result.selection == NSRange(location: 3, length: 0))
    }

    @Test func linePrefixKeepsCollapsedCursorAfterApplyingMarker() async throws {
        let result = MarkdownEditorView.MarkdownFormatter.apply(
            action: .bulletList,
            to: "hello",
            selection: NSRange(location: 2, length: 0)
        )

        #expect(result.text == "- hello")
        #expect(result.selection == NSRange(location: 4, length: 0))
    }

    @Test func linePrefixKeepsCollapsedCursorAfterRemovingMarker() async throws {
        let result = MarkdownEditorView.MarkdownFormatter.apply(
            action: .bulletList,
            to: "- hello",
            selection: NSRange(location: 4, length: 0)
        )

        #expect(result.text == "hello")
        #expect(result.selection == NSRange(location: 2, length: 0))
    }

    @Test func commitUsesAlreadyStagedIndexOnly() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder()
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        let file = ChangedFile(
            path: "Sources/App.swift",
            oldPath: nil,
            changeType: .modified,
            stageState: .staged,
            isMarkdown: false,
            isBinary: false
        )

        try await service.commit(
            files: [file],
            summary: "Update app",
            description: "Keep the dashboard fresh.",
            at: repoURL
        )

        let commands = await recorder.recordedCommands()
        #expect(commands == [
            ["-C", repoURL.path, "commit", "-m", "Update app", "-m", "Keep the dashboard fresh."]
        ])
    }

    @Test func stageAndUnstageUseGitIndexCommands() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder()
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })
        let file = ChangedFile(
            path: "Sources/App.swift",
            oldPath: nil,
            changeType: .modified,
            stageState: .unstaged,
            isMarkdown: false,
            isBinary: false
        )

        try await service.stageFiles([file], at: repoURL)
        try await service.unstageFiles([file], at: repoURL)

        let commands = await recorder.recordedCommands()
        #expect(commands == [
            ["-C", repoURL.path, "add", "-A", "--", "Sources/App.swift"],
            ["-C", repoURL.path, "restore", "--staged", "--", "Sources/App.swift"]
        ])
    }

    @Test func publishCurrentBranchPushesCurrentBranchToOrigin() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder(responses: [
            "symbolic-ref --short HEAD": "feature/git-ui\n"
        ])
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        try await service.publishCurrentBranch(remoteName: "origin", at: repoURL)

        let commands = await recorder.recordedCommands()
        #expect(commands == [
            ["-C", repoURL.path, "symbolic-ref", "--short", "HEAD"],
            ["-C", repoURL.path, "push", "-u", "origin", "feature/git-ui"]
        ])
    }

    @Test func pullUsesFastForwardOnly() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder()
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        try await service.pullCurrentBranch(at: repoURL)

        let commands = await recorder.recordedCommands()
        #expect(commands == [
            ["-C", repoURL.path, "pull", "--ff-only"]
        ])
    }

    @Test func branchParsingIdentifiesCurrentAndRemoteBranches() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder(responses: [
            "branch --all --format=%(HEAD)%09%(refname)%09%(refname:short)": """
            *\trefs/heads/main\tmain
             \trefs/heads/feature/git-ui\tfeature/git-ui
             \trefs/remotes/origin/main\torigin/main
             \trefs/remotes/origin/HEAD\torigin

            """
        ])
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        let branches = try await service.fetchBranches(at: repoURL)

        #expect(branches == [
            GitBranch(name: "main", isCurrent: true, isRemote: false),
            GitBranch(name: "feature/git-ui", isCurrent: false, isRemote: false),
            GitBranch(name: "origin/main", isCurrent: false, isRemote: true)
        ])
    }

    @Test func remoteBranchCheckoutAndLocalBranchDeleteUseSafeGitCommands() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder()
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        try await service.checkoutRemoteBranch(
            GitBranch(name: "origin/feature/git-ui", isCurrent: false, isRemote: true),
            at: repoURL
        )
        try await service.deleteBranch(
            GitBranch(name: "feature/old", isCurrent: false, isRemote: false),
            at: repoURL
        )

        let commands = await recorder.recordedCommands()
        #expect(commands == [
            ["-C", repoURL.path, "switch", "--track", "origin/feature/git-ui"],
            ["-C", repoURL.path, "branch", "-d", "feature/old"]
        ])
    }

    @Test func gitStatusParsingSeparatesStageStatesAndConflicts() throws {
        let files = try GitStatusParser().parse("""
         M README.md
        M  Sources/App.swift
        MM Package.swift
        R  Old.md -> New.md
         D Deleted.md
        ?? Notes.md
        UU Conflict.md

        """)

        #expect(files.map(\.path) == [
            "README.md",
            "Sources/App.swift",
            "Package.swift",
            "New.md",
            "Deleted.md",
            "Notes.md",
            "Conflict.md"
        ])
        #expect(files.map(\.changeType) == [
            .modified,
            .modified,
            .modified,
            .renamed,
            .deleted,
            .untracked,
            .conflicted
        ])
        #expect(files.map(\.stageState) == [
            .unstaged,
            .staged,
            .mixed,
            .staged,
            .unstaged,
            .unstaged,
            .conflicted
        ])
    }

    @Test func commitHistoryAndDetailsParseGitOutput() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder(responses: [
            "log -n 30 --date=iso-strict --pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e": """
            abc123def\u{1f}abc123d\u{1f}Ada Lovelace\u{1f}2026-06-13T10:00:00+02:00\u{1f}Update docs\u{1e}
            """,
            "show --no-ext-diff --name-status --date=iso-strict --format=%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1f%b%x1e abc123def": """
            abc123def\u{1f}abc123d\u{1f}Ada Lovelace\u{1f}2026-06-13T10:00:00+02:00\u{1f}Update docs\u{1f}Body text\u{1e}
            M\tREADME.md
            R100\tOld.md\tNew.md

            """,
            "show --no-ext-diff --format= --no-color --unified=3 abc123def": """
            diff --git a/README.md b/README.md
            --- a/README.md
            +++ b/README.md
            @@ -1 +1 @@
            -old
            +new

            """
        ])
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        let history = try await service.fetchCommitHistory(at: repoURL)
        let details = try await service.fetchCommitDetails(commitHash: "abc123def", at: repoURL)

        #expect(history.map(\.shortHash) == ["abc123d"])
        #expect(details.summary.subject == "Update docs")
        #expect(details.body == "Body text")
        #expect(details.changedFiles == [
            GitCommitChangedFile(path: "README.md", oldPath: nil, changeType: .modified),
            GitCommitChangedFile(path: "New.md", oldPath: "Old.md", changeType: .renamed)
        ])
        #expect(details.diffLines.isEmpty == false)
    }

    @Test func refreshingRemoteBranchesFetchesAndPrunesWhenRemotesExist() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder(responses: [
            "remote": "origin\n"
        ])
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        try await service.refreshRemoteBranches(at: repoURL)

        let commands = await recorder.recordedCommands()
        #expect(commands == [
            ["-C", repoURL.path, "remote"],
            ["-C", repoURL.path, "fetch", "--all", "--prune", "--quiet"]
        ])
    }

    @Test func refreshingRemoteBranchesSkipsFetchWhenNoRemotesExist() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder(responses: [
            "remote": ""
        ])
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        try await service.refreshRemoteBranches(at: repoURL)

        let commands = await recorder.recordedCommands()
        #expect(commands == [
            ["-C", repoURL.path, "remote"]
        ])
    }

    @MainActor
    @Test func appMenuDeduplicationKeepsBottomSettingsItem() throws {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: "RepoStudio", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let firstSettingsItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ",")
        firstSettingsItem.representedObject = "first"
        let secondSettingsItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ",")
        secondSettingsItem.representedObject = "second"

        appMenu.addItem(NSMenuItem(title: "About RepoStudio", action: nil, keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(firstSettingsItem)
        appMenu.addItem(secondSettingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Services", action: nil, keyEquivalent: ""))

        RepoStudioAppDelegate.removeDuplicateSettingsMenuItems(in: mainMenu)

        let settingsItems = appMenu.items.filter { $0.title == "Settings..." }
        #expect(settingsItems.count == 1)
        #expect(settingsItems.first?.representedObject as? String == "second")
    }

    @Test func remoteTrackingParsingMapsAheadBehindCounts() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder(responses: [
            "rev-parse --abbrev-ref --symbolic-full-name @{u}": "origin/main\n",
            "rev-list --left-right --count HEAD...@{u}": "2\t3\n"
        ])
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        let state = try await service.fetchRemoteTrackingState(at: repoURL)

        #expect(state == GitRemoteTrackingState(
            upstreamBranch: "origin/main",
            aheadCount: 2,
            behindCount: 3,
            isPublished: true
        ))
    }

    @Test func githubAccountStateReadsRemoteOwnerAndConfiguredUsername() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder(responses: [
            "remote get-url origin": "https://github.com/KrystofSlama/RepoStudio.git\n",
            "config --get credential.https://github.com.username": "KrystofSlama\n"
        ])
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        let state = try await service.fetchGitHubAccountState(at: repoURL)

        #expect(state == GitHubAccountState(
            remoteURL: "https://github.com/KrystofSlama/RepoStudio.git",
            remoteOwner: "KrystofSlama",
            credentialUsername: "KrystofSlama",
            isGitHubRemote: true
        ))
    }

    @Test func configuringGithubAccountWritesRepoCredentialUsername() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder()
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        try await service.configureGitHubCredentialUsername("KrystofSlama", at: repoURL)

        let commands = await recorder.recordedCommands()
        #expect(commands == [
            ["-C", repoURL.path, "config", "credential.https://github.com.username", "KrystofSlama"]
        ])
    }

    @Test func savingGithubCredentialApprovesTokenThroughCredentialHelper() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder()
        let inputRecorder = GitInputCommandRecorder()
        let service = GitCLIRepositoryService(
            commandRunner: { arguments in
                try await recorder.run(arguments)
            },
            inputCommandRunner: { arguments, standardInput in
                try await inputRecorder.run(arguments, standardInput: standardInput)
            }
        )

        try await service.saveGitHubCredential(username: "KrystofSlama", token: "github_pat_test", at: repoURL)

        let commands = await recorder.recordedCommands()
        #expect(commands == [
            ["-C", repoURL.path, "config", "credential.https://github.com.username", "KrystofSlama"]
        ])

        let inputCommands = await inputRecorder.recordedCommands()
        #expect(inputCommands == [
            RecordedGitInputCommand(
                arguments: ["-C", repoURL.path, "credential", "approve"],
                standardInput: """
                protocol=https
                host=github.com
                username=KrystofSlama
                password=github_pat_test

                """
            )
        ])
    }

    @MainActor
    @Test func dashboardCommitRequiresSummaryAndClearsOnSuccess() async throws {
        let service = FakeRepositoryService()
        let viewModel = DashboardViewModel(repositoryService: service)

        viewModel.openRepository(at: service.repoURL)
        await waitForDashboardTasks()

        #expect(viewModel.selectedCommitFileCount == 1)
        #expect(viewModel.canCommitSelectedFiles == false)

        viewModel.commitSummary = "Update docs"
        #expect(viewModel.canCommitSelectedFiles)

        viewModel.commitSelectedFiles()
        await waitForDashboardTasks()

        #expect(service.committedSummaries == ["Update docs"])
        #expect(viewModel.commitSummary.isEmpty)
        #expect(viewModel.changedFiles.isEmpty)
    }

    @MainActor
    @Test func dashboardCommitFailureSurfacesGitError() async throws {
        let service = FakeRepositoryService()
        service.commitError = DashboardError.gitCommandFailed(
            command: "git commit",
            message: "Author identity unknown"
        )
        let viewModel = DashboardViewModel(repositoryService: service)

        viewModel.openRepository(at: service.repoURL)
        await waitForDashboardTasks()
        viewModel.commitSummary = "Update docs"
        viewModel.commitSelectedFiles()
        await waitForDashboardTasks()

        #expect(viewModel.errorMessage == "Author identity unknown")
    }

    @MainActor
    @Test func dashboardStagesAndUnstagesFilesThroughService() async throws {
        let service = FakeRepositoryService()
        service.changedFiles = [
            ChangedFile(
                path: "README.md",
                oldPath: nil,
                changeType: .modified,
                stageState: .unstaged,
                isMarkdown: true,
                isBinary: false
            )
        ]
        let viewModel = DashboardViewModel(repositoryService: service)

        viewModel.openRepository(at: service.repoURL)
        await waitForDashboardTasks()

        #expect(service.stagedPaths == [["README.md"]])
        #expect(viewModel.selectedCommitFileCount == 1)

        viewModel.unstageFile(service.changedFiles[0])
        await waitForDashboardTasks()

        #expect(service.unstagedPaths == [["README.md"]])
        #expect(viewModel.selectedCommitFileCount == 0)

        viewModel.stageFile(service.changedFiles[0])
        await waitForDashboardTasks()

        #expect(service.stagedPaths == [["README.md"], ["README.md"]])
        #expect(viewModel.selectedCommitFileCount == 1)
    }

    @MainActor
    @Test func dashboardAutoStagesUnstagedFilesOnRefresh() async throws {
        let service = FakeRepositoryService()
        service.changedFiles = [
            ChangedFile(
                path: "README.md",
                oldPath: nil,
                changeType: .modified,
                stageState: .unstaged,
                isMarkdown: true,
                isBinary: false
            )
        ]
        let viewModel = DashboardViewModel(repositoryService: service)

        viewModel.openRepository(at: service.repoURL)
        await waitForDashboardTasks()

        #expect(service.stagedPaths == [["README.md"]])
        #expect(viewModel.changedFiles.first?.stageState == .staged)
        #expect(viewModel.canCommitSelectedFiles == false)

        viewModel.commitSummary = "Update docs"
        #expect(viewModel.canCommitSelectedFiles)
    }

    @MainActor
    @Test func dashboardUserUnstagedFilesAreNotAutoRestaged() async throws {
        let service = FakeRepositoryService()
        service.changedFiles = [
            ChangedFile(
                path: "README.md",
                oldPath: nil,
                changeType: .modified,
                stageState: .staged,
                isMarkdown: true,
                isBinary: false
            )
        ]
        let viewModel = DashboardViewModel(repositoryService: service)

        viewModel.openRepository(at: service.repoURL)
        await waitForDashboardTasks()
        viewModel.unstageFile(service.changedFiles[0])
        await waitForDashboardTasks()
        viewModel.refreshRepositoryState()
        await waitForDashboardTasks()

        #expect(service.unstagedPaths == [["README.md"]])
        #expect(service.stagedPaths.isEmpty)
        #expect(viewModel.changedFiles.first?.stageState == .unstaged)
        #expect(viewModel.selectedCommitFileCount == 0)
    }

    @MainActor
    @Test func dashboardDoesNotAutoStageConflicts() async throws {
        let service = FakeRepositoryService()
        service.changedFiles = [
            ChangedFile(
                path: "Conflict.md",
                oldPath: nil,
                changeType: .conflicted,
                stageState: .conflicted,
                isMarkdown: true,
                isBinary: false
            )
        ]
        let viewModel = DashboardViewModel(repositoryService: service)

        viewModel.openRepository(at: service.repoURL)
        await waitForDashboardTasks()

        #expect(service.stagedPaths.isEmpty)
        #expect(viewModel.hasConflictedFiles)
    }

    @MainActor
    @Test func dashboardHistoryViewOpensFromTopControlAndFileSelectionExits() async throws {
        let service = FakeRepositoryService()
        let viewModel = DashboardViewModel(repositoryService: service)

        viewModel.openRepository(at: service.repoURL)
        await waitForDashboardTasks()

        viewModel.showHistoryView()
        await waitForDashboardTasks()

        #expect(viewModel.isHistoryViewPresented)
        #expect(viewModel.selectedCommitHash == service.commitHistory.first?.hash)
        #expect(viewModel.selectedCommitDetails?.summary.hash == service.commitHistory.first?.hash)

        viewModel.selectFile(path: "README.md")

        #expect(viewModel.isHistoryViewPresented == false)
        #expect(viewModel.selectedCommitHash == nil)
    }

    @MainActor
    @Test func dashboardBranchDeletionGuardsCurrentBranchAndConfirmsLocalDelete() async throws {
        let service = FakeRepositoryService()
        let oldBranch = GitBranch(name: "feature/old", isCurrent: false, isRemote: false)
        service.branches = [
            GitBranch(name: "main", isCurrent: true, isRemote: false),
            oldBranch,
            GitBranch(name: "origin/main", isCurrent: false, isRemote: true)
        ]
        let viewModel = DashboardViewModel(repositoryService: service)

        viewModel.openRepository(at: service.repoURL)
        await waitForDashboardTasks()

        viewModel.requestDeleteBranch(GitBranch(name: "main", isCurrent: true, isRemote: false))
        #expect(viewModel.branchDeletionCandidate == nil)

        viewModel.requestDeleteBranch(oldBranch)
        #expect(viewModel.branchDeletionCandidate == oldBranch)

        viewModel.confirmDeleteBranch()
        await waitForDashboardTasks()

        #expect(service.deletedBranches == [oldBranch])
        #expect(viewModel.localBranches.contains(oldBranch) == false)
    }

    @MainActor
    @Test func dashboardConflictsDisableCommitAndSync() async throws {
        let service = FakeRepositoryService()
        service.changedFiles = [
            ChangedFile(
                path: "README.md",
                oldPath: nil,
                changeType: .conflicted,
                stageState: .conflicted,
                isMarkdown: true,
                isBinary: false
            )
        ]
        let viewModel = DashboardViewModel(repositoryService: service)

        viewModel.openRepository(at: service.repoURL)
        await waitForDashboardTasks()
        viewModel.commitSummary = "Resolve conflict"

        #expect(viewModel.hasConflictedFiles)
        #expect(viewModel.canCommitSelectedFiles == false)
        #expect(viewModel.canPerformPrimarySyncAction == false)

        viewModel.commitSelectedFiles()

        #expect(viewModel.errorMessage == "1 conflicted file(s). Resolve conflicts before committing, pulling, or pushing.")
    }

}

actor GitCommandRecorder {
    private var commands: [[String]] = []
    private let responses: [String: String]

    init(responses: [String: String] = [:]) {
        self.responses = responses
    }

    func run(_ arguments: [String]) async throws -> String {
        commands.append(arguments)
        let commandKey = arguments.dropFirst(2).joined(separator: " ")
        return responses[commandKey] ?? ""
    }

    func recordedCommands() -> [[String]] {
        commands
    }
}

struct RecordedGitInputCommand: Equatable {
    let arguments: [String]
    let standardInput: String
}

actor GitInputCommandRecorder {
    private var commands: [RecordedGitInputCommand] = []

    func run(_ arguments: [String], standardInput: String) async throws -> String {
        commands.append(
            RecordedGitInputCommand(
                arguments: arguments,
                standardInput: standardInput
            )
        )
        return ""
    }

    func recordedCommands() -> [RecordedGitInputCommand] {
        commands
    }
}

final class FakeRepositoryService: RepositoryService {
    let repoURL = URL(fileURLWithPath: "/tmp/repostudio-fake")
    var changedFiles = [
        ChangedFile(
            path: "README.md",
            oldPath: nil,
            changeType: .modified,
            stageState: .staged,
            isMarkdown: true,
            isBinary: false
        )
    ]
    var branches = [
        GitBranch(name: "main", isCurrent: true, isRemote: false)
    ]
    var commitHistory = [
        GitCommitSummary(
            hash: "abc123def",
            shortHash: "abc123d",
            author: "Ada Lovelace",
            date: "2026-06-13T10:00:00+02:00",
            subject: "Initial commit"
        )
    ]
    var committedSummaries: [String] = []
    var stagedPaths: [[String]] = []
    var unstagedPaths: [[String]] = []
    var checkedOutRemoteBranches: [GitBranch] = []
    var deletedBranches: [GitBranch] = []
    var commitError: Error?

    func validateRepository(at url: URL) async throws {}

    func fetchRepositoryContext(at url: URL) async throws -> RepositoryContext {
        RepositoryContext(repoURL: repoURL, repoName: "repostudio-fake", branchName: "main")
    }

    func fetchChangedFiles(at url: URL) async throws -> [ChangedFile] {
        changedFiles
    }

    func fetchRepositoryFiles(at url: URL) async throws -> [RepositoryFile] {
        [
            RepositoryFile(
                path: "README.md",
                isMarkdown: true,
                isBinary: false,
                isTracked: true
            )
        ]
    }

    func fetchDiffLines(at url: URL, for file: ChangedFile) async throws -> [DiffLine] {
        []
    }

    func commit(files: [ChangedFile], summary: String, description: String, at url: URL) async throws {
        if let commitError {
            throw commitError
        }

        committedSummaries.append(summary)
        changedFiles = []
    }

    func stageFiles(_ files: [ChangedFile], at url: URL) async throws {
        stagedPaths.append(files.map(\.path))
        changedFiles = changedFiles.map { file in
            guard files.contains(where: { $0.path == file.path }) else {
                return file
            }

            return ChangedFile(
                path: file.path,
                oldPath: file.oldPath,
                changeType: file.changeType,
                stageState: .staged,
                isMarkdown: file.isMarkdown,
                isBinary: file.isBinary
            )
        }
    }

    func unstageFiles(_ files: [ChangedFile], at url: URL) async throws {
        unstagedPaths.append(files.map(\.path))
        changedFiles = changedFiles.map { file in
            guard files.contains(where: { $0.path == file.path }) else {
                return file
            }

            return ChangedFile(
                path: file.path,
                oldPath: file.oldPath,
                changeType: file.changeType,
                stageState: .unstaged,
                isMarkdown: file.isMarkdown,
                isBinary: file.isBinary
            )
        }
    }

    func createBranch(named branchName: String, at url: URL) async throws {}

    func checkoutBranch(named branchName: String, at url: URL) async throws {}

    func checkoutRemoteBranch(_ branch: GitBranch, at url: URL) async throws {
        checkedOutRemoteBranches.append(branch)
    }

    func deleteBranch(_ branch: GitBranch, at url: URL) async throws {
        deletedBranches.append(branch)
        branches.removeAll { $0 == branch }
    }

    func refreshRemoteBranches(at url: URL) async throws {}

    func fetchBranches(at url: URL) async throws -> [GitBranch] {
        branches
    }

    func fetchCommitHistory(at url: URL) async throws -> [GitCommitSummary] {
        commitHistory
    }

    func fetchCommitDetails(commitHash: String, at url: URL) async throws -> GitCommitDetails {
        GitCommitDetails(
            summary: commitHistory.first(where: { $0.hash == commitHash }) ?? GitCommitSummary(
                hash: commitHash,
                shortHash: String(commitHash.prefix(7)),
                author: "Ada Lovelace",
                date: "2026-06-13T10:00:00+02:00",
                subject: "Commit"
            ),
            body: "",
            changedFiles: [],
            diffLines: []
        )
    }

    func pullCurrentBranch(at url: URL) async throws {}

    func pushCurrentBranch(at url: URL) async throws {}

    func publishCurrentBranch(remoteName: String, at url: URL) async throws {}

    func fetchRemoteTrackingState(at url: URL) async throws -> GitRemoteTrackingState {
        GitRemoteTrackingState(
            upstreamBranch: "origin/main",
            aheadCount: 0,
            behindCount: 0,
            isPublished: true
        )
    }

    func fetchGitHubAccountState(at url: URL) async throws -> GitHubAccountState {
        GitHubAccountState(
            remoteURL: "https://github.com/KrystofSlama/RepoStudio.git",
            remoteOwner: "KrystofSlama",
            credentialUsername: nil,
            isGitHubRemote: true
        )
    }

    func configureGitHubCredentialUsername(_ username: String?, at url: URL) async throws {}

    func saveGitHubCredential(username: String, token: String, at url: URL) async throws {}
}

func waitForDashboardTasks() async {
    for _ in 0..<5 {
        await Task.yield()
    }

    try? await Task.sleep(nanoseconds: 30_000_000)
}
