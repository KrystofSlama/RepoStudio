//
//  RepositoryFile.swift
//  RepoStudio
//

import Foundation

struct RepositoryFile: Identifiable, Hashable {
    let path: String
    let isMarkdown: Bool
    let isBinary: Bool
    let isTracked: Bool

    var id: String {
        path
    }

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var relativeDirectory: String {
        let directory = (path as NSString).deletingLastPathComponent
        return directory == "." ? "" : directory
    }
}
