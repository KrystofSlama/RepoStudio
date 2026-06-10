//
//  RepositoryService.swift
//  RepoStudio
//

import Foundation

//MARK: -Protocol
protocol RepositoryService {
    func validateRepository(at url: URL) async throws
    func fetchRepositoryContext(at url: URL) async throws -> RepositoryContext
    func fetchChangedFiles(at url: URL) async throws -> [ChangedFile]
    func fetchRepositoryFiles(at url: URL) async throws -> [RepositoryFile]
    func fetchDiffLines(at url: URL, for file: ChangedFile) async throws -> [DiffLine]
    func commit(files: [ChangedFile], summary: String, description: String, at url: URL) async throws
    func createBranch(named branchName: String, at url: URL) async throws
    func checkoutBranch(named branchName: String, at url: URL) async throws
    func fetchBranches(at url: URL) async throws -> [GitBranch]
    func pullCurrentBranch(at url: URL) async throws
    func pushCurrentBranch(at url: URL) async throws
    func publishCurrentBranch(remoteName: String, at url: URL) async throws
    func fetchRemoteTrackingState(at url: URL) async throws -> GitRemoteTrackingState
    func fetchGitHubAccountState(at url: URL) async throws -> GitHubAccountState
    func configureGitHubCredentialUsername(_ username: String?, at url: URL) async throws
    func saveGitHubCredential(username: String, token: String, at url: URL) async throws
}
