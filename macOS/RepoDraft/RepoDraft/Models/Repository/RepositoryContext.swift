//
//  RepositoryContext.swift
//  RepoDraft
//

import Foundation

struct RepositoryContext: Hashable {
    let repoURL: URL
    let repoName: String
    let branchName: String
}
