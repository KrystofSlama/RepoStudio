//
//  GitCLIRepositoryService.swift
//  RepoStudio
//

import Foundation

//MARK: -Implementation
struct GitCLIRepositoryService: RepositoryService {
    typealias GitCommandRunner = ([String]) async throws -> String
    typealias GitInputCommandRunner = ([String], String) async throws -> String

    private static let gitExecutableCandidates: [String] = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
        "/usr/bin/git"
    ]

    private let parser: GitStatusParser
    private let diffParser: GitUnifiedDiffParser
    private let commandRunner: GitCommandRunner
    private let inputCommandRunner: GitInputCommandRunner

    init(
        parser: GitStatusParser = GitStatusParser(),
        diffParser: GitUnifiedDiffParser = GitUnifiedDiffParser(),
        commandRunner: @escaping GitCommandRunner = GitCLIRepositoryService.defaultCommandRunner,
        inputCommandRunner: @escaping GitInputCommandRunner = GitCLIRepositoryService.defaultInputCommandRunner
    ) {
        self.parser = parser
        self.diffParser = diffParser
        self.commandRunner = commandRunner
        self.inputCommandRunner = inputCommandRunner
    }

    func validateRepository(at url: URL) async throws {
        let output = try await runRepositoryCommand(
            in: url,
            command: ["rev-parse", "--is-inside-work-tree"]
        )

        if output.trimmingCharacters(in: .whitespacesAndNewlines) != "true" {
            throw DashboardError.invalidRepository(url)
        }
    }

    func fetchRepositoryContext(at url: URL) async throws -> RepositoryContext {
        try await validateRepository(at: url)

        let repoName = url.lastPathComponent
        let branchName = try await fetchBranchName(in: url)

        return RepositoryContext(
            repoURL: url,
            repoName: repoName,
            branchName: branchName
        )
    }

    func fetchChangedFiles(at url: URL) async throws -> [ChangedFile] {
        let output = try await runRepositoryCommand(
            in: url,
            command: ["status", "--porcelain=v1", "--renames", "--untracked-files=all"]
        )

        return try parser.parse(output)
    }

    func fetchRepositoryFiles(at url: URL) async throws -> [RepositoryFile] {
        let trackedOutput = try await runRepositoryCommand(
            in: url,
            command: ["ls-files"]
        )
        let untrackedOutput = try await runRepositoryCommand(
            in: url,
            command: ["ls-files", "--others", "--exclude-standard"]
        )

        let trackedPaths = parsePathLines(trackedOutput)
        let untrackedPaths = parsePathLines(untrackedOutput)
        let untrackedSet = Set(untrackedPaths)

        var seenPaths = Set<String>()
        var files: [RepositoryFile] = []

        for path in (trackedPaths + untrackedPaths).sorted() {
            guard !path.isEmpty else {
                continue
            }

            if seenPaths.insert(path).inserted {
                files.append(
                    RepositoryFile(
                        path: path,
                        isMarkdown: isMarkdownFile(path: path),
                        isBinary: isBinaryFile(path: path),
                        isTracked: !untrackedSet.contains(path)
                    )
                )
            }
        }

        return files
    }

    func fetchDiffLines(at url: URL, for file: ChangedFile) async throws -> [DiffLine] {
        guard file.isBinary == false else {
            return []
        }

        if file.changeType == .untracked {
            return try buildSyntheticNewFileDiffLines(at: url, path: file.path)
        }

        let unifiedDiff = try await fetchUnifiedDiffOutput(at: url, path: file.path)
        if unifiedDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if file.changeType == .added {
                return try buildSyntheticNewFileDiffLines(at: url, path: file.path)
            }
            return []
        }

        return diffParser.parse(unifiedDiff)
    }

    func commit(files: [ChangedFile], summary: String, description: String, at url: URL) async throws {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSummary.isEmpty == false, files.isEmpty == false else {
            return
        }

        var commitCommand = ["commit", "-m", trimmedSummary]
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDescription.isEmpty == false {
            commitCommand.append(contentsOf: ["-m", trimmedDescription])
        }

        _ = try await runRepositoryCommand(in: url, command: commitCommand)
    }

    func stageFiles(_ files: [ChangedFile], at url: URL) async throws {
        let paths = commitPaths(for: files)
        guard paths.isEmpty == false else {
            return
        }

        _ = try await runRepositoryCommand(
            in: url,
            command: ["add", "-A", "--"] + paths
        )
    }

    func unstageFiles(_ files: [ChangedFile], at url: URL) async throws {
        let paths = commitPaths(for: files)
        guard paths.isEmpty == false else {
            return
        }

        _ = try await runRepositoryCommand(
            in: url,
            command: ["restore", "--staged", "--"] + paths
        )
    }

    func stashChanges(message: String, at url: URL) async throws {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let stashMessage = trimmedMessage.isEmpty ? "RepoStudio work in progress" : trimmedMessage

        _ = try await runRepositoryCommand(
            in: url,
            command: ["stash", "push", "--include-untracked", "--message", stashMessage]
        )
    }

    func restoreStashedChanges(for branchName: String, at url: URL) async throws -> Bool {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBranchName.isEmpty == false else {
            return false
        }

        let stashListOutput = try await runRepositoryCommand(
            in: url,
            command: ["stash", "list", "--format=%gd%x00%gs"]
        )

        guard let stashRef = repoStudioStashRef(for: trimmedBranchName, in: stashListOutput) else {
            return false
        }

        _ = try await runRepositoryCommand(
            in: url,
            command: ["stash", "apply", stashRef]
        )
        _ = try await runRepositoryCommand(
            in: url,
            command: ["stash", "drop", stashRef]
        )
        return true
    }

    func createBranch(named branchName: String, at url: URL) async throws {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBranchName.isEmpty == false else {
            return
        }

        _ = try await runRepositoryCommand(
            in: url,
            command: ["switch", "-c", trimmedBranchName]
        )
    }

    func checkoutBranch(named branchName: String, at url: URL) async throws {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBranchName.isEmpty == false else {
            return
        }

        _ = try await runRepositoryCommand(
            in: url,
            command: ["switch", trimmedBranchName]
        )
    }

    func checkoutRemoteBranch(_ branch: GitBranch, at url: URL) async throws {
        guard branch.isRemote, branch.name.isEmpty == false else {
            return
        }

        _ = try await runRepositoryCommand(
            in: url,
            command: ["switch", "--track", branch.name]
        )
    }

    func deleteBranch(_ branch: GitBranch, at url: URL) async throws {
        guard branch.isRemote == false, branch.isCurrent == false, branch.name.isEmpty == false else {
            return
        }

        _ = try await runRepositoryCommand(
            in: url,
            command: ["branch", "-d", branch.name]
        )
    }

    func refreshRemoteBranches(at url: URL) async throws {
        let remoteOutput = try await runRepositoryCommand(
            in: url,
            command: ["remote"]
        )
        let remoteNames = parsePathLines(remoteOutput)
        guard remoteNames.isEmpty == false else {
            return
        }

        _ = try await runRepositoryCommand(
            in: url,
            command: ["fetch", "--all", "--prune", "--quiet"]
        )
    }

    func fetchBranches(at url: URL) async throws -> [GitBranch] {
        let output = try await runRepositoryCommand(
            in: url,
            command: ["branch", "--all", "--format=%(HEAD)%09%(refname)%09%(refname:short)"]
        )

        return parseBranches(output)
    }

    func fetchCommitHistory(at url: URL) async throws -> [GitCommitSummary] {
        let output: String
        do {
            output = try await runRepositoryCommand(
                in: url,
                command: [
                    "log",
                    "-n", "30",
                    "--date=iso-strict",
                    "--pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e"
                ]
            )
        } catch let error as DashboardError {
            if isEmptyHistoryError(error) {
                return []
            }
            throw error
        }

        return parseCommitHistory(output)
    }

    func fetchCommitDetails(commitHash: String, at url: URL) async throws -> GitCommitDetails {
        let trimmedHash = commitHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedHash.isEmpty == false else {
            throw DashboardError.invalidGitOutput(commitHash)
        }

        let metadataOutput = try await runRepositoryCommand(
            in: url,
            command: [
                "show",
                "--no-ext-diff",
                "--name-status",
                "--date=iso-strict",
                "--format=%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1f%b%x1e",
                trimmedHash
            ]
        )
        let patchOutput = try await runRepositoryCommand(
            in: url,
            command: [
                "show",
                "--no-ext-diff",
                "--format=",
                "--no-color",
                "--unified=3",
                trimmedHash
            ]
        )

        return try parseCommitDetails(metadataOutput, diffOutput: patchOutput)
    }

    func pullCurrentBranch(at url: URL) async throws {
        _ = try await runRepositoryCommand(
            in: url,
            command: ["pull", "--ff-only"]
        )
    }

    func pushCurrentBranch(at url: URL) async throws {
        _ = try await runRepositoryCommand(
            in: url,
            command: ["push"]
        )
    }

    func publishCurrentBranch(remoteName: String, at url: URL) async throws {
        let trimmedRemoteName = remoteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedRemoteName.isEmpty == false else {
            return
        }

        let currentBranchName = try await fetchBranchName(in: url)
        _ = try await runRepositoryCommand(
            in: url,
            command: ["push", "-u", trimmedRemoteName, currentBranchName]
        )
    }

    func fetchRemoteTrackingState(at url: URL) async throws -> GitRemoteTrackingState {
        let upstreamOutput: String
        do {
            upstreamOutput = try await runRepositoryCommand(
                in: url,
                command: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]
            )
        } catch let error as DashboardError {
            if isMissingUpstreamError(error) {
                return .unpublished
            }
            throw error
        }

        let upstreamBranch = upstreamOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard upstreamBranch.isEmpty == false else {
            return .unpublished
        }

        let countOutput = try await runRepositoryCommand(
            in: url,
            command: ["rev-list", "--left-right", "--count", "HEAD...@{u}"]
        )

        let counts = parseAheadBehindCounts(countOutput)
        return GitRemoteTrackingState(
            upstreamBranch: upstreamBranch,
            aheadCount: counts.ahead,
            behindCount: counts.behind,
            isPublished: true
        )
    }

    func fetchGitHubAccountState(at url: URL) async throws -> GitHubAccountState {
        guard let remoteURL = try await runOptionalRepositoryCommand(
            in: url,
            command: ["remote", "get-url", "origin"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines), remoteURL.isEmpty == false else {
            return .unavailable
        }

        let remoteOwner = parseGitHubOwner(from: remoteURL)
        let isGitHubRemote = remoteOwner != nil
        guard isGitHubRemote else {
            return GitHubAccountState(
                remoteURL: remoteURL,
                remoteOwner: nil,
                credentialUsername: nil,
                isGitHubRemote: false
            )
        }

        let credentialUsername = try await fetchConfiguredGitHubCredentialUsername(in: url)

        return GitHubAccountState(
            remoteURL: remoteURL,
            remoteOwner: remoteOwner,
            credentialUsername: credentialUsername,
            isGitHubRemote: true
        )
    }

    func configureGitHubCredentialUsername(_ username: String?, at url: URL) async throws {
        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedUsername.isEmpty {
            do {
                _ = try await runRepositoryCommand(
                    in: url,
                    command: ["config", "--unset", "credential.https://github.com.username"]
                )
            } catch {
                // It is fine if the repo did not have a GitHub username override yet.
            }
            return
        }

        _ = try await runRepositoryCommand(
            in: url,
            command: ["config", "credential.https://github.com.username", trimmedUsername]
        )
    }

    func saveGitHubCredential(username: String, token: String, at url: URL) async throws {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.isEmpty == false, trimmedToken.isEmpty == false else {
            return
        }

        try await configureGitHubCredentialUsername(trimmedUsername, at: url)

        let credentialInput = """
        protocol=https
        host=github.com
        username=\(trimmedUsername)
        password=\(trimmedToken)

        """

        _ = try await runRepositoryCommand(
            in: url,
            command: ["credential", "approve"],
            standardInput: credentialInput
        )
    }

    func configureGlobalGitHubCredentialUsername(_ username: String?) async throws {
        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedUsername.isEmpty {
            _ = try await runGitCommand(
                arguments: ["config", "--global", "--unset", "credential.https://github.com.username"]
            )
            return
        }

        _ = try await runGitCommand(
            arguments: ["config", "--global", "credential.https://github.com.username", trimmedUsername]
        )
    }

    func saveGlobalGitHubCredential(username: String, token: String, setAsDefault: Bool) async throws {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.isEmpty == false else {
            return
        }

        if setAsDefault {
            try await configureGlobalGitHubCredentialUsername(trimmedUsername)
        }

        guard trimmedToken.isEmpty == false else {
            return
        }

        _ = try await runGitCommand(
            arguments: ["credential", "approve"],
            standardInput: gitHubCredentialInput(username: trimmedUsername, token: trimmedToken)
        )
    }

    func rejectGlobalGitHubCredential(username: String) async throws {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedUsername.isEmpty == false else {
            return
        }

        _ = try await runGitCommand(
            arguments: ["credential", "reject"],
            standardInput: gitHubCredentialInput(username: trimmedUsername, token: nil)
        )
    }

    private func fetchBranchName(in repoURL: URL) async throws -> String {
        do {
            let branchOutput = try await runRepositoryCommand(
                in: repoURL,
                command: ["symbolic-ref", "--short", "HEAD"]
            )
            let branchName = branchOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !branchName.isEmpty {
                return branchName
            }
        } catch {
            // Detached HEAD fallback.
        }

        let hashOutput = try await runRepositoryCommand(
            in: repoURL,
            command: ["rev-parse", "--short", "HEAD"]
        )
        return hashOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitPaths(for files: [ChangedFile]) -> [String] {
        var seenPaths = Set<String>()
        var paths: [String] = []

        for file in files {
            if let oldPath = file.oldPath, oldPath.isEmpty == false, seenPaths.insert(oldPath).inserted {
                paths.append(oldPath)
            }

            if file.path.isEmpty == false, seenPaths.insert(file.path).inserted {
                paths.append(file.path)
            }
        }

        return paths
    }

    private func repoStudioStashRef(for branchName: String, in output: String) -> String? {
        let expectedSubjectPrefix = "On \(branchName): RepoStudio: WIP on \(branchName) before switching to "

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let columns = line.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false)
            guard columns.count == 2 else {
                continue
            }

            let stashRef = String(columns[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = String(columns[1])
            if stashRef.isEmpty == false, subject.hasPrefix(expectedSubjectPrefix) {
                return stashRef
            }
        }

        return nil
    }

    private func parseBranches(_ output: String) -> [GitBranch] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> GitBranch? in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 3 else {
                    return nil
                }

                let headMarker = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let fullRefName = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let shortName = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)
                guard shortName.isEmpty == false,
                      shortName.hasSuffix("/HEAD") == false,
                      fullRefName.hasSuffix("/HEAD") == false else {
                    return nil
                }

                return GitBranch(
                    name: shortName,
                    isCurrent: headMarker == "*",
                    isRemote: fullRefName.hasPrefix("refs/remotes/")
                )
            }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent {
                    return lhs.isCurrent
                }

                if lhs.isRemote != rhs.isRemote {
                    return rhs.isRemote
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func parseAheadBehindCounts(_ output: String) -> (ahead: Int, behind: Int) {
        let parts = output
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)

        guard parts.count >= 2 else {
            return (0, 0)
        }

        return (
            ahead: Int(parts[0]) ?? 0,
            behind: Int(parts[1]) ?? 0
        )
    }

    private func parseCommitHistory(_ output: String) -> [GitCommitSummary] {
        output
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { record -> GitCommitSummary? in
                let columns = record.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 5 else {
                    return nil
                }

                return GitCommitSummary(
                    hash: columns[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    shortHash: columns[1].trimmingCharacters(in: .whitespacesAndNewlines),
                    author: columns[2].trimmingCharacters(in: .whitespacesAndNewlines),
                    date: columns[3].trimmingCharacters(in: .whitespacesAndNewlines),
                    subject: columns[4].trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { $0.hash.isEmpty == false }
    }

    private func parseCommitDetails(_ metadataOutput: String, diffOutput: String) throws -> GitCommitDetails {
        let parts = metadataOutput.split(separator: "\u{1e}", maxSplits: 1, omittingEmptySubsequences: false)
        guard let header = parts.first else {
            throw DashboardError.invalidGitOutput(metadataOutput)
        }

        let columns = header.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 6 else {
            throw DashboardError.invalidGitOutput(metadataOutput)
        }

        let summary = GitCommitSummary(
            hash: columns[0].trimmingCharacters(in: .whitespacesAndNewlines),
            shortHash: columns[1].trimmingCharacters(in: .whitespacesAndNewlines),
            author: columns[2].trimmingCharacters(in: .whitespacesAndNewlines),
            date: columns[3].trimmingCharacters(in: .whitespacesAndNewlines),
            subject: columns[4].trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let body = columns[5].trimmingCharacters(in: .whitespacesAndNewlines)
        let nameStatusOutput = parts.count > 1 ? String(parts[1]) : ""
        let changedFiles = parseCommitChangedFiles(nameStatusOutput)
        let diffLines = diffParser.parse(diffOutput.trimmingCharacters(in: .whitespacesAndNewlines))

        return GitCommitDetails(
            summary: summary,
            body: body,
            changedFiles: changedFiles,
            diffLines: diffLines
        )
    }

    private func parseCommitChangedFiles(_ output: String) -> [GitCommitChangedFile] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> GitCommitChangedFile? in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 2 else {
                    return nil
                }

                let status = columns[0]
                let changeType = GitChangeType.fromStatusCode(status.padding(toLength: 2, withPad: " ", startingAt: 0)) ?? .modified
                if status.hasPrefix("R"), columns.count >= 3 {
                    return GitCommitChangedFile(
                        path: columns[2],
                        oldPath: columns[1],
                        changeType: .renamed
                    )
                }

                return GitCommitChangedFile(
                    path: columns[1],
                    oldPath: nil,
                    changeType: changeType
                )
            }
    }

    private func isMissingUpstreamError(_ error: DashboardError) -> Bool {
        guard case let .gitCommandFailed(_, message) = error else {
            return false
        }

        let lowered = message.lowercased()
        return lowered.contains("no upstream configured")
            || lowered.contains("no upstream branch")
            || lowered.contains("upstream branch")
            || lowered.contains("@{u}")
    }

    private func isEmptyHistoryError(_ error: DashboardError) -> Bool {
        guard case let .gitCommandFailed(_, message) = error else {
            return false
        }

        let lowered = message.lowercased()
        return lowered.contains("does not have any commits yet")
            || lowered.contains("your current branch") && lowered.contains("does not have any commits")
            || lowered.contains("bad default revision 'head'")
            || lowered.contains("ambiguous argument 'head'")
    }

    private func fetchConfiguredGitHubCredentialUsername(in repoURL: URL) async throws -> String? {
        if let specificUsername = try await runOptionalRepositoryCommand(
            in: repoURL,
            command: ["config", "--get", "credential.https://github.com.username"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines), specificUsername.isEmpty == false {
            return specificUsername
        }

        if let genericUsername = try await runOptionalRepositoryCommand(
            in: repoURL,
            command: ["config", "--get", "credential.username"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines), genericUsername.isEmpty == false {
            return genericUsername
        }

        return nil
    }

    private func parseGitHubOwner(from remoteURL: String) -> String? {
        let trimmedRemoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmedRemoteURL),
           url.host?.localizedCaseInsensitiveCompare("github.com") == .orderedSame {
            return firstPathComponent(from: url.path)
        }

        if trimmedRemoteURL.hasPrefix("git@github.com:") {
            let path = String(trimmedRemoteURL.dropFirst("git@github.com:".count))
            return firstPathComponent(from: path)
        }

        if trimmedRemoteURL.localizedCaseInsensitiveContains("@github.com/"),
           let path = trimmedRemoteURL.components(separatedBy: "@github.com/").last {
            return firstPathComponent(from: path)
        }

        return nil
    }

    private func firstPathComponent(from path: String) -> String? {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let firstComponent = normalizedPath.split(separator: "/").first.map(String.init)
        return firstComponent?.isEmpty == false ? firstComponent : nil
    }

    private func gitHubCredentialInput(username: String, token: String?) -> String {
        var lines = [
            "protocol=https",
            "host=github.com",
            "username=\(username)"
        ]

        if let token, token.isEmpty == false {
            lines.append("password=\(token)")
        }

        return lines.joined(separator: "\n") + "\n\n"
    }

    private func runRepositoryCommand(in repoURL: URL, command: [String]) async throws -> String {
        let arguments = ["-C", repoURL.path] + command
        return try await runGitCommand(arguments: arguments)
    }

    private func runRepositoryCommand(in repoURL: URL, command: [String], standardInput: String) async throws -> String {
        let arguments = ["-C", repoURL.path] + command
        return try await runGitCommand(arguments: arguments, standardInput: standardInput)
    }

    private func runOptionalRepositoryCommand(in repoURL: URL, command: [String]) async throws -> String? {
        do {
            return try await runRepositoryCommand(in: repoURL, command: command)
        } catch let error as DashboardError {
            guard case .gitCommandFailed = error else {
                throw error
            }
            return nil
        }
    }

    private func parsePathLines(_ output: String) -> [String] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isMarkdownFile(path: String) -> Bool {
        URL(fileURLWithPath: path).pathExtension.lowercased() == "md"
    }

    private func isBinaryFile(path: String) -> Bool {
        let extensionName = URL(fileURLWithPath: path).pathExtension.lowercased()
        let binaryExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "pdf", "zip", "jar",
            "xcassets", "mov", "mp4", "m4v", "ico", "icns"
        ]

        return binaryExtensions.contains(extensionName)
    }

    private func fetchUnifiedDiffOutput(at repoURL: URL, path: String) async throws -> String {
        do {
            return try await runRepositoryCommand(
                in: repoURL,
                command: ["diff", "--no-color", "--unified=3", "HEAD", "--", path]
            )
        } catch let error as DashboardError {
            if case let .gitCommandFailed(_, message) = error,
               message.localizedCaseInsensitiveContains("ambiguous argument 'HEAD'") {
                return try await runRepositoryCommand(
                    in: repoURL,
                    command: ["diff", "--no-color", "--unified=3", "--", path]
                )
            }
            throw error
        }
    }

    private func buildSyntheticNewFileDiffLines(at repoURL: URL, path: String) throws -> [DiffLine] {
        let fileURL = repoURL.appendingPathComponent(path)
        let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
        let fileLines = fileContents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let hunkHeader = "@@ -0,0 +1,\(max(fileLines.count, 1)) @@"

        let headerLines = [
            "diff --git a/\(path) b/\(path)",
            "--- /dev/null",
            "+++ b/\(path)",
            hunkHeader
        ]

        var synthetic = headerLines.joined(separator: "\n")
        synthetic += "\n"
        synthetic += fileLines.map { "+\($0)" }.joined(separator: "\n")

        return diffParser.parse(synthetic)
    }

    private func runGitCommand(arguments: [String]) async throws -> String {
        do {
            return try await commandRunner(arguments)
        } catch let dashboardError as DashboardError {
            throw dashboardError
        } catch {
            throw DashboardError.gitCommandFailed(
                command: "git \(arguments.joined(separator: " "))",
                message: error.localizedDescription
            )
        }
    }

    private func runGitCommand(arguments: [String], standardInput: String) async throws -> String {
        do {
            return try await inputCommandRunner(arguments, standardInput)
        } catch let dashboardError as DashboardError {
            throw dashboardError
        } catch {
            throw DashboardError.gitCommandFailed(
                command: "git \(arguments.joined(separator: " "))",
                message: error.localizedDescription
            )
        }
    }

    private static func defaultCommandRunner(arguments: [String]) async throws -> String {
        var attemptedPaths = Set<String>()
        let fileManager = FileManager.default
        var candidatePaths = gitExecutableCandidates.filter { fileManager.isExecutableFile(atPath: $0) }
        candidatePaths.append(contentsOf: gitExecutableCandidates)
        candidatePaths = candidatePaths.filter { attemptedPaths.insert($0).inserted }

        var fallbackError: DashboardError = .gitCommandFailed(
            command: "git \(arguments.joined(separator: " "))",
            message: "Unable to locate a runnable Git executable."
        )

        for executablePath in candidatePaths {
            do {
                return try await runProcess(executablePath: executablePath, arguments: arguments)
            } catch let dashboardError as DashboardError {
                fallbackError = dashboardError
                if shouldTryNextExecutable(for: dashboardError) {
                    continue
                }
                throw dashboardError
            } catch {
                fallbackError = .gitCommandFailed(
                    command: "git \(arguments.joined(separator: " "))",
                    message: error.localizedDescription
                )
            }
        }

        let fallbackMessage: String
        if case let .gitCommandFailed(_, message) = fallbackError, message.isEmpty == false {
            fallbackMessage = message
        } else {
            fallbackMessage = "Unable to locate a runnable Git executable."
        }

        throw DashboardError.missingXcodeCommandLineTools(details: fallbackMessage)
    }

    private static func defaultInputCommandRunner(arguments: [String], standardInput: String) async throws -> String {
        var attemptedPaths = Set<String>()
        let fileManager = FileManager.default
        var candidatePaths = gitExecutableCandidates.filter { fileManager.isExecutableFile(atPath: $0) }
        candidatePaths.append(contentsOf: gitExecutableCandidates)
        candidatePaths = candidatePaths.filter { attemptedPaths.insert($0).inserted }

        var fallbackError: DashboardError = .gitCommandFailed(
            command: "git \(arguments.joined(separator: " "))",
            message: "Unable to locate a runnable Git executable."
        )

        for executablePath in candidatePaths {
            do {
                return try await runProcess(
                    executablePath: executablePath,
                    arguments: arguments,
                    standardInput: standardInput
                )
            } catch let dashboardError as DashboardError {
                fallbackError = dashboardError
                if shouldTryNextExecutable(for: dashboardError) {
                    continue
                }
                throw dashboardError
            } catch {
                fallbackError = .gitCommandFailed(
                    command: "git \(arguments.joined(separator: " "))",
                    message: error.localizedDescription
                )
            }
        }

        let fallbackMessage: String
        if case let .gitCommandFailed(_, message) = fallbackError, message.isEmpty == false {
            fallbackMessage = message
        } else {
            fallbackMessage = "Unable to locate a runnable Git executable."
        }

        throw DashboardError.missingXcodeCommandLineTools(details: fallbackMessage)
    }

    private static func commandLineToolsLikelyMissing(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("xcode-select")
            || lowered.contains("command line tools")
            || lowered.contains("no developer tools")
            || lowered.contains("invalid active developer path")
            || lowered.contains("tool 'git' requires xcode")
    }

    private static func runProcess(executablePath: String, arguments: [String]) async throws -> String {
        try await runProcess(executablePath: executablePath, arguments: arguments, standardInput: nil)
    }

    private static func runProcess(executablePath: String, arguments: [String], standardInput: String?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["GIT_TERMINAL_PROMPT"] = "0"
            process.environment = environment

            let standardOutputPipe = Pipe()
            let standardErrorPipe = Pipe()
            process.standardOutput = standardOutputPipe
            process.standardError = standardErrorPipe
            let standardInputPipe: Pipe?
            if standardInput != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                standardInputPipe = pipe
            } else {
                standardInputPipe = nil
            }

            process.terminationHandler = { task in
                let outputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorMessage = String(data: errorData, encoding: .utf8) ?? ""
                let normalizedErrorMessage = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)

                if task.terminationStatus == 0 {
                    continuation.resume(returning: output)
                    return
                }

                continuation.resume(
                    throwing: DashboardError.gitCommandFailed(
                        command: "git \(arguments.joined(separator: " "))",
                        message: normalizedErrorMessage
                    )
                )
            }

            do {
                try process.run()
                if let standardInput,
                   let inputData = standardInput.data(using: .utf8),
                   let fileHandle = standardInputPipe?.fileHandleForWriting {
                    fileHandle.write(inputData)
                    try? fileHandle.close()
                }
            } catch {
                continuation.resume(
                    throwing: DashboardError.gitCommandFailed(
                        command: "git \(arguments.joined(separator: " "))",
                        message: error.localizedDescription
                    )
                )
            }
        }
    }

    private static func shouldTryNextExecutable(for error: DashboardError) -> Bool {
        guard case let .gitCommandFailed(_, message) = error else {
            return false
        }

        let lowered = message.lowercased()
        return lowered.contains("cannot be used within an app sandbox")
            || lowered.contains("operation not permitted")
            || lowered.contains("permission denied")
            || lowered.contains("launch path not accessible")
            || lowered.contains("doesn’t exist")
            || lowered.contains("doesn't exist")
            || lowered.contains("no such file or directory")
            || lowered.contains("could not be found")
            || commandLineToolsLikelyMissing(message)
    }
}
