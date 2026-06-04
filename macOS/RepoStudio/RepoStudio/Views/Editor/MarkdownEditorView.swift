//
//  MarkdownEditorView.swift
//  RepoStudio
//

import SwiftUI

struct MarkdownEditorView: View {
    //MARK: -State
    @Binding var text: String
    let showsFormatToolbar: Bool
    @State var selectionRange = NSRange(location: 0, length: 0)
    @State var focusRequestID = UUID()

    init(text: Binding<String>, showsFormatToolbar: Bool = true) {
        _text = text
        self.showsFormatToolbar = showsFormatToolbar
    }

    //MARK: -Body
    var body: some View {
        VStack(spacing: 0) {
            if showsFormatToolbar {
                formatToolbar
                Divider()
            }
            MarkdownTextEditorRepresentable(
                text: $text,
                selectionRange: $selectionRange,
                focusRequestID: focusRequestID
            )
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    //MARK: -Actions
    func applyFormatAction(_ action: MarkdownFormatAction) {
        let safeSelection = clampedSelection(selectionRange, in: text)
        let result = MarkdownFormatter.apply(action: action, to: text, selection: safeSelection)
        text = result.text
        selectionRange = result.selection
        focusRequestID = UUID()
    }

    func clampedSelection(_ proposed: NSRange, in sourceText: String) -> NSRange {
        let maxLength = (sourceText as NSString).length
        guard maxLength >= 0 else {
            return NSRange(location: 0, length: 0)
        }

        let safeLocation = max(0, min(proposed.location, maxLength))
        let safeLength = max(0, min(proposed.length, maxLength - safeLocation))
        return NSRange(location: safeLocation, length: safeLength)
    }
}
