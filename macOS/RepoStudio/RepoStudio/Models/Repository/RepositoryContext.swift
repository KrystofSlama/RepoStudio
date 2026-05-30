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
