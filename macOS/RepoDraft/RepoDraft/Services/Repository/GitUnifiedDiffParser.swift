//
//  GitUnifiedDiffParser.swift
//  RepoDraft
//

import Foundation

//MARK: -Parsing
struct GitUnifiedDiffParser {
    private let hunkHeaderRegex = try? NSRegularExpression(
        pattern: #"@@ -([0-9]+)(?:,[0-9]+)? \+([0-9]+)(?:,[0-9]+)? @@"#
    )

    func parse(_ diffOutput: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var oldLineNumber: Int?
        var newLineNumber: Int?

        for (index, rawLine) in diffOutput
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .enumerated() {
            if rawLine.hasPrefix("@@") {
                let (oldStart, newStart) = parseHunkHeader(rawLine)
                oldLineNumber = oldStart
                newLineNumber = newStart

                lines.append(
                    DiffLine(
                        kind: .hunk,
                        oldLineNumber: nil,
                        newLineNumber: nil,
                        text: rawLine,
                        index: index
                    )
                )
                continue
            }

            if rawLine.hasPrefix("+"), rawLine.hasPrefix("+++") == false {
                lines.append(
                    DiffLine(
                        kind: .added,
                        oldLineNumber: nil,
                        newLineNumber: newLineNumber,
                        text: String(rawLine.dropFirst()),
                        index: index
                    )
                )
                if let currentNewLineNumber = newLineNumber {
                    newLineNumber = currentNewLineNumber + 1
                }
                continue
            }

            if rawLine.hasPrefix("-"), rawLine.hasPrefix("---") == false {
                lines.append(
                    DiffLine(
                        kind: .removed,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: nil,
                        text: String(rawLine.dropFirst()),
                        index: index
                    )
                )
                if let currentOldLineNumber = oldLineNumber {
                    oldLineNumber = currentOldLineNumber + 1
                }
                continue
            }

            if rawLine.hasPrefix(" ") {
                lines.append(
                    DiffLine(
                        kind: .context,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: newLineNumber,
                        text: String(rawLine.dropFirst()),
                        index: index
                    )
                )
                if let currentOldLineNumber = oldLineNumber {
                    oldLineNumber = currentOldLineNumber + 1
                }
                if let currentNewLineNumber = newLineNumber {
                    newLineNumber = currentNewLineNumber + 1
                }
                continue
            }

            lines.append(
                DiffLine(
                    kind: .meta,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    text: rawLine,
                    index: index
                )
            )
        }

        return lines
    }

    private func parseHunkHeader(_ header: String) -> (Int?, Int?) {
        guard
            let hunkHeaderRegex,
            let match = hunkHeaderRegex.firstMatch(
                in: header,
                range: NSRange(location: 0, length: (header as NSString).length)
            ),
            let oldRange = Range(match.range(at: 1), in: header),
            let newRange = Range(match.range(at: 2), in: header),
            let oldStart = Int(header[oldRange]),
            let newStart = Int(header[newRange])
        else {
            return (nil, nil)
        }

        return (oldStart, newStart)
    }
}
