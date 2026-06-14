//
//  RepositoryContext.swift
//  RepoStudio
//

import Foundation

struct RepositoryContext: Hashable {
    let repoURL: URL
    let repoName: String
    let branchName: String
}

struct GitBranch: Identifiable, Hashable {
    let name: String
    let isCurrent: Bool
    let isRemote: Bool

    var id: String {
        "\(isRemote ? "remote" : "local")|\(name)"
    }
}

struct GitRemoteTrackingState: Hashable {
    let upstreamBranch: String?
    let aheadCount: Int
    let behindCount: Int
    let isPublished: Bool

    static let unpublished = GitRemoteTrackingState(
        upstreamBranch: nil,
        aheadCount: 0,
        behindCount: 0,
        isPublished: false
    )
}

struct GitHubAccountState: Hashable {
    let remoteURL: String?
    let remoteOwner: String?
    let credentialUsername: String?
    let isGitHubRemote: Bool

    static let unavailable = GitHubAccountState(
        remoteURL: nil,
        remoteOwner: nil,
        credentialUsername: nil,
        isGitHubRemote: false
    )
}

struct GitCommitSummary: Identifiable, Hashable {
    let hash: String
    let shortHash: String
    let author: String
    let date: String
    let subject: String

    var id: String { hash }
}

struct GitCommitChangedFile: Identifiable, Hashable {
    let path: String
    let oldPath: String?
    let changeType: GitChangeType

    var id: String {
        "\(changeType.rawValue)|\(oldPath ?? "")|\(path)"
    }

    var displayPath: String {
        if let oldPath {
            return "\(oldPath) -> \(path)"
        }

        return path
    }
}

struct GitCommitDetails: Hashable {
    let summary: GitCommitSummary
    let body: String
    let changedFiles: [GitCommitChangedFile]
    let diffLines: [DiffLine]
}
