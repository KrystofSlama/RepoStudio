//
//  RepoStudioTests.swift
//  RepoStudioTests
//
//  Created by Kryštof Sláma on 28.05.2026.
//

import Testing
import Foundation
@testable import RepoStudio

struct RepoStudioTests {

    @Test func headingOnEmptyLineInsertsMarkerAtCursor() async throws {
        let result = MarkdownEditorView.MarkdownFormatter.apply(
            action: .heading2,
            to: "",
            selection: NSRange(location: 0, length: 0)
        )

        #expect(result.text == "## ")
        #expect(result.selection == NSRange(location: 3, length: 0))
    }

    @Test func linePrefixKeepsCollapsedCursorAfterApplyingMarker() async throws {
        let result = MarkdownEditorView.MarkdownFormatter.apply(
            action: .bulletList,
            to: "hello",
            selection: NSRange(location: 2, length: 0)
        )

        #expect(result.text == "- hello")
        #expect(result.selection == NSRange(location: 4, length: 0))
    }

    @Test func linePrefixKeepsCollapsedCursorAfterRemovingMarker() async throws {
        let result = MarkdownEditorView.MarkdownFormatter.apply(
            action: .bulletList,
            to: "- hello",
            selection: NSRange(location: 4, length: 0)
        )

        #expect(result.text == "hello")
        #expect(result.selection == NSRange(location: 2, length: 0))
    }

}
