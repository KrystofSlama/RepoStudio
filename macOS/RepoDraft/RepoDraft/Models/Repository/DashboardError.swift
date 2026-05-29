//
//  DashboardError.swift
//  RepoDraft
//

import Foundation

enum DashboardError: LocalizedError, Equatable {
    case invalidRepository(URL)
    case gitCommandFailed(command: String, message: String)
    case missingXcodeCommandLineTools(details: String)
    case invalidGitOutput(String)
    case fileReadFailed(String)
    case fileWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepository(let url):
            return "\(url.lastPathComponent) is not a valid Git repository."
        case .gitCommandFailed(_, let message):
            return message.isEmpty ? "Git command failed." : message
        case .missingXcodeCommandLineTools(let details):
            let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return """
                RepoDraft requires Xcode Command Line Tools (Git).
                Install them and relaunch the app.
                """
            }
            return """
            RepoDraft requires Xcode Command Line Tools (Git).
            Install them and relaunch the app.
            Details: \(trimmed)
            """
        case .invalidGitOutput(let rawLine):
            return "Could not parse Git status line: \(rawLine)"
        case .fileReadFailed(let path):
            return "Could not read file at \(path)."
        case .fileWriteFailed(let path):
            return "Could not write file at \(path)."
        }
    }

    var isMissingXcodeCommandLineTools: Bool {
        switch self {
        case .missingXcodeCommandLineTools:
            return true
        case .gitCommandFailed(_, let message):
            let lowered = message.lowercased()
            return lowered.contains("xcode-select")
                || lowered.contains("command line tools")
                || lowered.contains("no developer tools")
                || lowered.contains("cannot be used within an app sandbox")
        default:
            return false
        }
    }
}
