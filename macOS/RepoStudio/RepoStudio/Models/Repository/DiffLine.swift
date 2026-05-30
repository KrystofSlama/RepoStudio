//
//  DiffLine.swift
//  RepoStudio
//

import Foundation

enum DiffLineKind: String, Hashable {
    case meta
    case hunk
    case context
    case added
    case removed
}

struct DiffLine: Identifiable, Hashable {
    let kind: DiffLineKind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
    let index: Int

    var id: String {
        "\(index)|\(kind.rawValue)|\(oldLineNumber ?? -1)|\(newLineNumber ?? -1)|\(text)"
    }
}
