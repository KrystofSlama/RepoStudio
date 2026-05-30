//
//  ChangedFile.swift
//  RepoStudio
//

import Foundation

struct ChangedFile: Identifiable, Hashable {
    let path: String
    let oldPath: String?
    let changeType: GitChangeType
    let isMarkdown: Bool
    let isBinary: Bool

    var id: String {
        "\(changeType.rawValue)|\(oldPath ?? "")|\(path)"
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
}
