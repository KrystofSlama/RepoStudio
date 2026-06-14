//
//  GitStatusParser.swift
//  RepoStudio
//

import Foundation

//MARK: -Parsing
struct GitStatusParser {
    func parse(_ statusOutput: String) throws -> [ChangedFile] {
        var parsedFiles: [ChangedFile] = []

        for line in statusOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if let changedFile = try parseLine(line) {
                parsedFiles.append(changedFile)
            }
        }

        return parsedFiles
    }

    private func parseLine(_ line: String) throws -> ChangedFile? {
        guard line.count >= 3 else {
            throw DashboardError.invalidGitOutput(line)
        }

        let statusCode = String(line.prefix(2))
        guard let changeType = GitChangeType.fromStatusCode(statusCode) else {
            return nil
        }
        let stageState = stageState(from: statusCode)

        let remainder = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let normalizedRemainder = remainder.replacingOccurrences(of: "\"", with: "")

        if changeType == .renamed {
            let renameParts = normalizedRemainder.components(separatedBy: " -> ")
            if renameParts.count == 2 {
                let oldPath = renameParts[0]
                let newPath = renameParts[1]
                return ChangedFile(
                    path: newPath,
                    oldPath: oldPath,
                    changeType: .renamed,
                    stageState: stageState,
                    isMarkdown: isMarkdownFile(path: newPath),
                    isBinary: isBinaryFile(path: newPath)
                )
            }
        }

        return ChangedFile(
            path: normalizedRemainder,
            oldPath: nil,
            changeType: changeType,
            stageState: stageState,
            isMarkdown: isMarkdownFile(path: normalizedRemainder),
            isBinary: isBinaryFile(path: normalizedRemainder)
        )
    }

    private func stageState(from statusCode: String) -> GitFileStageState {
        if statusCode == "??" {
            return .unstaged
        }

        if GitChangeType.fromStatusCode(statusCode) == .conflicted {
            return .conflicted
        }

        let indexStatus = statusCode.first ?? " "
        let workTreeStatus = statusCode.dropFirst().first ?? " "
        let hasStagedChanges = indexStatus != " "
        let hasUnstagedChanges = workTreeStatus != " "

        if hasStagedChanges, hasUnstagedChanges {
            return .mixed
        }

        if hasStagedChanges {
            return .staged
        }

        return .unstaged
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
}
