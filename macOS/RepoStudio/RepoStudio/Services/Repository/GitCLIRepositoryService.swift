//
//  GitCLIRepositoryService.swift
//  RepoStudio
//

import Foundation

//MARK: -Implementation
struct GitCLIRepositoryService: RepositoryService {
    typealias GitCommandRunner = ([String]) async throws -> String

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

    init(
        parser: GitStatusParser = GitStatusParser(),
        diffParser: GitUnifiedDiffParser = GitUnifiedDiffParser(),
        commandRunner: @escaping GitCommandRunner = GitCLIRepositoryService.defaultCommandRunner
    ) {
        self.parser = parser
        self.diffParser = diffParser
        self.commandRunner = commandRunner
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

        let paths = commitPaths(for: files)
        guard paths.isEmpty == false else {
            return
        }

        try await runRepositoryCommand(
            in: url,
            command: ["add", "-A", "--"] + paths
        )

        var commitCommand = ["commit", "-m", trimmedSummary]
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDescription.isEmpty == false {
            commitCommand.append(contentsOf: ["-m", trimmedDescription])
        }

        try await runRepositoryCommand(in: url, command: commitCommand)
    }

    func createBranch(named branchName: String, at url: URL) async throws {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBranchName.isEmpty == false else {
            return
        }

        try await runRepositoryCommand(
            in: url,
            command: ["switch", "-c", trimmedBranchName]
        )
    }

    func checkoutBranch(named branchName: String, at url: URL) async throws {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBranchName.isEmpty == false else {
            return
        }

        try await runRepositoryCommand(
            in: url,
            command: ["switch", trimmedBranchName]
        )
    }

    func fetchBranches(at url: URL) async throws -> [GitBranch] {
        let output = try await runRepositoryCommand(
            in: url,
            command: ["branch", "--all", "--format=%(HEAD)%09%(refname)%09%(refname:short)"]
        )

        return parseBranches(output)
    }

    func pullCurrentBranch(at url: URL) async throws {
        try await runRepositoryCommand(
            in: url,
            command: ["pull", "--ff-only"]
        )
    }

    func pushCurrentBranch(at url: URL) async throws {
        try await runRepositoryCommand(
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
        try await runRepositoryCommand(
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
                guard shortName.isEmpty == false, shortName.hasSuffix("/HEAD") == false else {
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

    private func runRepositoryCommand(in repoURL: URL, command: [String]) async throws -> String {
        let arguments = ["-C", repoURL.path] + command
        return try await runGitCommand(arguments: arguments)
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

    private static func commandLineToolsLikelyMissing(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("xcode-select")
            || lowered.contains("command line tools")
            || lowered.contains("no developer tools")
            || lowered.contains("invalid active developer path")
            || lowered.contains("tool 'git' requires xcode")
    }

    private static func runProcess(executablePath: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let standardOutputPipe = Pipe()
            let standardErrorPipe = Pipe()
            process.standardOutput = standardOutputPipe
            process.standardError = standardErrorPipe

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
