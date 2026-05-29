//
//  GitChangeType.swift
//  RepoDraft
//

import Foundation

enum GitChangeType: String, CaseIterable, Hashable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case untracked = "?"

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
        }
    }

    static func fromStatusCode(_ statusCode: String) -> GitChangeType? {
        if statusCode == "??" {
            return .untracked
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
}
