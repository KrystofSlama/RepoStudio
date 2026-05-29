//
//  MarkdownPreviewHelpers.swift
//  RepoDraft
//

import Foundation
import SwiftUI
import Textual

extension MarkdownPreviewView {
    //MARK: -Subviews
    struct MarkdownStructuredPreview: View {
        let markdownText: String
        let baseURL: URL?

        var body: some View {
            ScrollView {
                StructuredText(
                    markdown: MarkdownPreviewFormatter.preprocess(markdownText),
                    baseURL: baseURL
                )
                .textual.structuredTextStyle(.gitHub)
                .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
                .textual.textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.visible)
        }
    }

    //MARK: -Rows

    //MARK: -Formatting
    enum MarkdownPreviewFormatter {
        static func preprocess(_ markdown: String) -> String {
            var output = markdown
            output = convertHTMLImageTagsToMarkdown(output)
            output = removeParagraphAlignmentTags(output)
            return output
        }

        private static func convertHTMLImageTagsToMarkdown(_ text: String) -> String {
            guard let regex = try? NSRegularExpression(
                pattern: "<img\\s+[^>]*>",
                options: [.caseInsensitive]
            ) else {
                return text
            }

            let source = text as NSString
            let matches = regex.matches(
                in: text,
                range: NSRange(location: 0, length: source.length)
            )

            guard matches.isEmpty == false else {
                return text
            }

            var result = text
            for match in matches.reversed() {
                let imgTag = source.substring(with: match.range)
                guard let src = attributeValue(named: "src", in: imgTag) else {
                    continue
                }

                let alt = attributeValue(named: "alt", in: imgTag) ?? ""
                let markdownImage = "![\(alt)](\(src))"
                if let range = Range(match.range, in: result) {
                    result.replaceSubrange(range, with: markdownImage)
                }
            }

            return result
        }

        private static func removeParagraphAlignmentTags(_ text: String) -> String {
            let openingTagPattern = "<p\\s+align\\s*=\\s*['\"][^'\"]*['\"]\\s*>"
            let closingTagPattern = "</p>"

            var output = text
            output = output.replacingOccurrences(
                of: openingTagPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            output = output.replacingOccurrences(
                of: closingTagPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )

            return output
        }

        private static func attributeValue(named name: String, in tag: String) -> String? {
            let pattern = "\(name)\\s*=\\s*([\"'])(.*?)\\1"
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(
                    in: tag,
                    range: NSRange(location: 0, length: (tag as NSString).length)
                ),
                let valueRange = Range(match.range(at: 2), in: tag)
            else {
                return nil
            }

            return String(tag[valueRange])
        }
    }
}
