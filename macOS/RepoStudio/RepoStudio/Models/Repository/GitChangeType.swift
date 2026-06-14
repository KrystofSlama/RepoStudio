//
//  GitChangeType.swift
//  RepoStudio
//

import Foundation

enum GitChangeType: String, CaseIterable, Hashable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case untracked = "?"
    case conflicted = "U"

    var displayName: String {
        switch self {
        case .modified:
            return "Modified"
        case .added:
            return "Added"
        case .deleted:
            return "Deleted"
        case .renamed:
            return "Renamed"
        case .untracked:
            return "New"
        case .conflicted:
            return "Conflicted"
        }
    }

    var badgeText: String {
        switch self {
        case .modified:
            return "M"
        case .added:
            return "A"
        case .deleted:
            return "D"
        case .renamed:
            return "R"
        case .untracked:
            return "N"
        case .conflicted:
            return "!"
        }
    }

    var sortOrder: Int {
        switch self {
        case .modified:
            return 0
        case .added:
            return 1
        case .deleted:
            return 2
        case .renamed:
            return 3
        case .untracked:
            return 4
        case .conflicted:
            return 5
        }
    }

    static func fromStatusCode(_ statusCode: String) -> GitChangeType? {
        if statusCode == "??" {
            return .untracked
        }

        if isConflictStatusCode(statusCode) {
            return .conflicted
        }

        if statusCode.contains("R") {
            return .renamed
        }

        if statusCode.contains("A") {
            return .added
        }

        if statusCode.contains("D") {
            return .deleted
        }

        if statusCode.contains("M") || statusCode.contains("C") || statusCode.contains("T") || statusCode.contains("U") {
            return .modified
        }

        return nil
    }

    private static func isConflictStatusCode(_ statusCode: String) -> Bool {
        let conflictCodes: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        return conflictCodes.contains(statusCode) || statusCode.contains("U")
    }
}

enum GitFileStageState: String, CaseIterable, Hashable {
    case staged
    case unstaged
    case mixed
    case conflicted

    var displayName: String {
        switch self {
        case .staged:
            return "Staged"
        case .unstaged:
            return "Unstaged"
        case .mixed:
            return "Partially Staged"
        case .conflicted:
            return "Conflicts"
        }
    }

    var sortOrder: Int {
        switch self {
        case .conflicted:
            return 0
        case .staged:
            return 1
        case .mixed:
            return 2
        case .unstaged:
            return 3
        }
    }

    var hasStagedChanges: Bool {
        self == .staged || self == .mixed
    }

    var hasUnstagedChanges: Bool {
        self == .unstaged || self == .mixed
    }
}
