//
//  MarkdownPreviewView.swift
//  RepoStudio
//

import SwiftUI

struct MarkdownPreviewView: View {
    //MARK: -State
    let markdownText: String
    let baseURL: URL?

    //MARK: -Body
    var body: some View {
        MarkdownStructuredPreview(markdownText: markdownText, baseURL: baseURL)
    }

    //MARK: -Actions
}
