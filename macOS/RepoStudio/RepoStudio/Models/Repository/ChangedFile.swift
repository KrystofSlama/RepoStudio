//
//  ChangedFile.swift
//  RepoStudio
//

import Foundation

struct ChangedFile: Identifiable, Hashable {
    let path: String
    let oldPath: String?
    let changeType: GitChangeType
    let stageState: GitFileStageState
    let isMarkdown: Bool
    let isBinary: Bool

    var id: String {
        "\(stageState.rawValue)|\(changeType.rawValue)|\(oldPath ?? "")|\(path)"
    }

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var relativeDirectory: String {
        let directory = (path as NSString).deletingLastPathComponent
        return directory == "." ? "" : directory
    }

    var displayPath: String {
        if let oldPath {
            return "\(oldPath) -> \(path)"
        }

        return path
    }

    var statusPaths: [String] {
        var paths: [String] = []
        if let oldPath, oldPath.isEmpty == false {
            paths.append(oldPath)
        }
        if path.isEmpty == false {
            paths.append(path)
        }
        return paths
    }

    var canStage: Bool {
        stageState.hasUnstagedChanges
    }

    var canUnstage: Bool {
        stageState.hasStagedChanges
    }
}
