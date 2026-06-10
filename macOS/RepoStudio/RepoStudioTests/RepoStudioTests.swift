//
//  RepoStudioTests.swift
//  RepoStudioTests
//
//  Created by Kryštof Sláma on 28.05.2026.
//

import Testing
import Foundation
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

    @Test func commitRunsAddAndCommitForSelectedFiles() async throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repostudio-test")
        let recorder = GitCommandRecorder()
        let service = GitCLIRepositoryService(commandRunner: { arguments in
            try await recorder.run(arguments)
        })

        let file = ChangedFile(
            path: "Sources/App.swift",
            oldPath: nil,
            changeType: .modified,
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
            ["-C", repoURL.path, "add", "-A", "--", "Sources/App.swift"],
            ["-C", repoURL.path, "commit", "-m", "Update app", "-m", "Keep the dashboard fresh."]
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
             \trefs/remotes/origin/HEAD\torigin/HEAD

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
            isMarkdown: true,
            isBinary: false
        )
    ]
    var committedSummaries: [String] = []
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

    func createBranch(named branchName: String, at url: URL) async throws {}

    func checkoutBranch(named branchName: String, at url: URL) async throws {}

    func fetchBranches(at url: URL) async throws -> [GitBranch] {
        [
            GitBranch(name: "main", isCurrent: true, isRemote: false)
        ]
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
