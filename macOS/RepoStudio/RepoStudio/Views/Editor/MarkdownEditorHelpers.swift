//
//  MarkdownEditorHelpers.swift
//  RepoStudio
//

import AppKit
import Foundation
import SwiftUI

extension MarkdownEditorView {
    //MARK: -Subviews
    var formatToolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MarkdownFormatAction.allCases) { action in
                    Button {
                        applyFormatAction(action)
                    } label: {
                        Label(action.title, systemImage: action.symbolName)
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .help(action.helpText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.never)
        .background(.ultraThinMaterial)
    }

    //MARK: -Rows
    enum MarkdownFormatAction: String, CaseIterable, Identifiable {
        case heading1
        case heading2
        case bold
        case italic
        case inlineCode
        case codeBlock
        case quote
        case bulletList
        case checklist
        case link
        case table

        var id: String { rawValue }

        var title: String {
            switch self {
            case .heading1:
                return "H1"
            case .heading2:
                return "H2"
            case .bold:
                return "Bold"
            case .italic:
                return "Italic"
            case .inlineCode:
                return "Code"
            case .codeBlock:
                return "Code Block"
            case .quote:
                return "Quote"
            case .bulletList:
                return "List"
            case .checklist:
                return "Checklist"
            case .link:
                return "Link"
            case .table:
                return "Table"
            }
        }

        var symbolName: String {
            switch self {
            case .heading1:
                return "textformat.size.larger"
            case .heading2:
                return "textformat.size"
            case .bold:
                return "bold"
            case .italic:
                return "italic"
            case .inlineCode:
                return "chevron.left.forwardslash.chevron.right"
            case .codeBlock:
                return "terminal"
            case .quote:
                return "text.quote"
            case .bulletList:
                return "list.bullet"
            case .checklist:
                return "checklist"
            case .link:
                return "link"
            case .table:
                return "tablecells"
            }
        }

        var helpText: String {
            switch self {
            case .heading1:
                return "Toggle heading level 1"
            case .heading2:
                return "Toggle heading level 2"
            case .bold:
                return "Bold selected text"
            case .italic:
                return "Italicize selected text"
            case .inlineCode:
                return "Inline code on selected text"
            case .codeBlock:
                return "Insert fenced code block"
            case .quote:
                return "Toggle quote block"
            case .bulletList:
                return "Toggle bullet list"
            case .checklist:
                return "Toggle checklist"
            case .link:
                return "Insert markdown link"
            case .table:
                return "Insert table template"
            }
        }
    }

    struct MarkdownEditResult {
        let text: String
        let selection: NSRange
    }

    struct MarkdownTextEditorRepresentable: NSViewRepresentable {
        @Binding var text: String
        @Binding var selectionRange: NSRange
        let focusRequestID: UUID

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = true
            scrollView.backgroundColor = .textBackgroundColor

            let textView = NSTextView()
            textView.isEditable = true
            textView.isSelectable = true
            textView.isRichText = false
            textView.allowsUndo = true
            textView.usesFindBar = true
            textView.usesInspectorBar = false
            textView.usesRuler = false
            textView.smartInsertDeleteEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.importsGraphics = false
            textView.drawsBackground = true
            textView.backgroundColor = .textBackgroundColor
            textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            textView.textContainerInset = NSSize(width: 12, height: 12)

            textView.isHorizontallyResizable = true
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )

            textView.string = text
            textView.setSelectedRange(selectionRange)
            textView.delegate = context.coordinator

            scrollView.documentView = textView
            context.coordinator.textView = textView
            context.coordinator.lastFocusRequestID = focusRequestID

            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = context.coordinator.textView else {
                return
            }

            let currentText = textView.string
            let safeSelection = clampedSelection(selectionRange, in: text)

            if currentText != text {
                context.coordinator.isProgrammaticUpdate = true
                textView.string = text
                context.coordinator.isProgrammaticUpdate = false
            }

            if NSEqualRanges(textView.selectedRange(), safeSelection) == false {
                context.coordinator.isProgrammaticUpdate = true
                textView.setSelectedRange(safeSelection)
                context.coordinator.isProgrammaticUpdate = false
            }

            if context.coordinator.lastFocusRequestID != focusRequestID {
                context.coordinator.lastFocusRequestID = focusRequestID
                textView.window?.makeFirstResponder(textView)
                textView.scrollRangeToVisible(safeSelection)
            }
        }

        func clampedSelection(_ proposed: NSRange, in sourceText: String) -> NSRange {
            let maxLength = (sourceText as NSString).length
            let safeLocation = max(0, min(proposed.location, maxLength))
            let safeLength = max(0, min(proposed.length, maxLength - safeLocation))
            return NSRange(location: safeLocation, length: safeLength)
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            var parent: MarkdownTextEditorRepresentable
            weak var textView: NSTextView?
            var isProgrammaticUpdate = false
            var lastFocusRequestID: UUID?

            init(_ parent: MarkdownTextEditorRepresentable) {
                self.parent = parent
            }

            func textDidChange(_ notification: Notification) {
                guard isProgrammaticUpdate == false,
                      let textView = notification.object as? NSTextView else {
                    return
                }

                parent.text = textView.string
                parent.selectionRange = textView.selectedRange()
            }

            func textViewDidChangeSelection(_ notification: Notification) {
                guard isProgrammaticUpdate == false,
                      let textView = notification.object as? NSTextView else {
                    return
                }

                parent.selectionRange = textView.selectedRange()
            }
        }
    }

    //MARK: -Formatting
    enum MarkdownFormatter {
        static func apply(action: MarkdownFormatAction, to source: String, selection: NSRange) -> MarkdownEditResult {
            switch action {
            case .heading1:
                return toggleLinePrefix("# ", in: source, selection: selection)
            case .heading2:
                return toggleLinePrefix("## ", in: source, selection: selection)
            case .bold:
                return wrapSelection("**", suffix: "**", placeholder: "bold text", in: source, selection: selection)
            case .italic:
                return wrapSelection("*", suffix: "*", placeholder: "italic text", in: source, selection: selection)
            case .inlineCode:
                return wrapSelection("`", suffix: "`", placeholder: "code", in: source, selection: selection)
            case .codeBlock:
                return codeBlock(in: source, selection: selection)
            case .quote:
                return toggleLinePrefix("> ", in: source, selection: selection)
            case .bulletList:
                return toggleLinePrefix("- ", in: source, selection: selection)
            case .checklist:
                return toggleLinePrefix("- [ ] ", in: source, selection: selection)
            case .link:
                return link(in: source, selection: selection)
            case .table:
                return table(in: source, selection: selection)
            }
        }

        private static func wrapSelection(
            _ prefix: String,
            suffix: String,
            placeholder: String,
            in source: String,
            selection: NSRange
        ) -> MarkdownEditResult {
            let sourceNSString = source as NSString
            let selectedText = selection.length > 0 ? sourceNSString.substring(with: selection) : placeholder
            let replacement = "\(prefix)\(selectedText)\(suffix)"
            let newText = sourceNSString.replacingCharacters(in: selection, with: replacement)

            let selectionLocation = selection.location + (prefix as NSString).length
            let selectionLength = (selectedText as NSString).length
            let newSelection = NSRange(location: selectionLocation, length: selectionLength)

            return MarkdownEditResult(text: newText, selection: newSelection)
        }

        private static func toggleLinePrefix(_ prefix: String, in source: String, selection: NSRange) -> MarkdownEditResult {
            let sourceNSString = source as NSString
            let lineRange = sourceNSString.lineRange(for: selection)
            let block = sourceNSString.substring(with: lineRange)
            let lines = block.components(separatedBy: "\n")
            let markerLength = (prefix as NSString).length

            let shouldUnprefix = lines.allSatisfy { line in
                line.isEmpty || line.hasPrefix(prefix)
            }

            let transformedLines = lines.map { line -> String in
                guard line.isEmpty == false else {
                    return line
                }

                if shouldUnprefix {
                    if line.hasPrefix(prefix) {
                        return String(line.dropFirst(markerLength))
                    }
                    return line
                }

                return prefix + line
            }

            let replacement = transformedLines.joined(separator: "\n")
            let newText = sourceNSString.replacingCharacters(in: lineRange, with: replacement)
            let newSelection = NSRange(location: lineRange.location, length: (replacement as NSString).length)

            return MarkdownEditResult(text: newText, selection: newSelection)
        }

        private static func codeBlock(in source: String, selection: NSRange) -> MarkdownEditResult {
            let sourceNSString = source as NSString
            let selectedText = selection.length > 0 ? sourceNSString.substring(with: selection) : "code"
            let replacement = "```swift\n\(selectedText)\n```"
            let newText = sourceNSString.replacingCharacters(in: selection, with: replacement)

            let selectionLocation = selection.location + ("```swift\n" as NSString).length
            let selectionLength = (selectedText as NSString).length
            let newSelection = NSRange(location: selectionLocation, length: selectionLength)

            return MarkdownEditResult(text: newText, selection: newSelection)
        }

        private static func link(in source: String, selection: NSRange) -> MarkdownEditResult {
            let sourceNSString = source as NSString
            let selectedText = selection.length > 0 ? sourceNSString.substring(with: selection) : "link text"
            let replacement = "[\(selectedText)](https://)"
            let newText = sourceNSString.replacingCharacters(in: selection, with: replacement)

            let urlPrefixLength = ("[\(selectedText)](" as NSString).length
            let newSelection = NSRange(location: selection.location + urlPrefixLength, length: ("https://" as NSString).length)

            return MarkdownEditResult(text: newText, selection: newSelection)
        }

        private static func table(in source: String, selection: NSRange) -> MarkdownEditResult {
            let sourceNSString = source as NSString
            let replacement = """
            | Column 1 | Column 2 | Column 3 |
            | --- | --- | --- |
            | Value | Value | Value |
            """
            let newText = sourceNSString.replacingCharacters(in: selection, with: replacement)

            let startLocation = selection.location + ("| " as NSString).length
            let newSelection = NSRange(location: startLocation, length: ("Column 1" as NSString).length)

            return MarkdownEditResult(text: newText, selection: newSelection)
        }
    }
}
