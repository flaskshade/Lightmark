import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case code(language: String?, text: String)
    case list(ordered: Bool, start: Int, items: [String])
    case table(MarkdownTable)
    case rule
}

public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case leading, center, trailing
    }

    public let headers: [String]
    public let alignments: [Alignment]
    public let rows: [[String]]

    public init(headers: [String], alignments: [Alignment], rows: [[String]]) {
        self.headers = headers
        self.alignments = alignments
        self.rows = rows
    }
}

/// A small block parser for the reading surface. The source text remains authoritative.
/// Unsupported Markdown stays visible as text rather than being discarded.
public enum MarkdownParser {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if let fence = fenceMarker(line) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let language = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                index += 1
                var code: [String] = []
                while index < lines.count {
                    let nextLine = lines[index]
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.hasPrefix(fence) {
                        break
                    }
                    code.append(nextLine)
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language: language.isEmpty ? nil : language, text: code.joined(separator: "\n")))
                continue
            }

            if index + 1 < lines.count,
               let tableStart = tableHeader(line, delimiter: lines[index + 1]) {
                index += 2
                var rows: [[String]] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                      let row = splitTableRow(lines[index]), row.hasPipe {
                    let cells = Array(row.cells.prefix(tableStart.headers.count))
                    rows.append(cells + Array(repeating: "", count: tableStart.headers.count - cells.count))
                    index += 1
                }
                blocks.append(.table(MarkdownTable(headers: tableStart.headers,
                                                   alignments: tableStart.alignments,
                                                   rows: rows)))
                continue
            }

            if let heading = heading(line) {
                blocks.append(.heading(level: heading.0, text: heading.1))
                index += 1
                continue
            }

            if isRule(line) {
                blocks.append(.rule)
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let currentLine = lines[index]
                    let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix(">") {
                        quoted.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            if let first = listItem(line) {
                var items = [first.text]
                index += 1
                while index < lines.count,
                      let next = listItem(lines[index]),
                      next.ordered == first.ordered {
                    items.append(next.text)
                    index += 1
                }
                blocks.append(.list(ordered: first.ordered, start: first.number, items: items))
                continue
            }

            var paragraph = [line]
            index += 1
            while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty &&
                    setextHeadingLevel(lines[index]) == nil &&
                    !startsBlock(lines[index]) &&
                    !(index + 1 < lines.count && tableHeader(lines[index], delimiter: lines[index + 1]) != nil) {
                paragraph.append(lines[index])
                index += 1
            }
            if index < lines.count, let level = setextHeadingLevel(lines[index]) {
                blocks.append(.heading(level: level, text: paragraph.joined(separator: " ")))
                index += 1
            } else {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            }
        }
        return blocks
    }

    private static func startsBlock(_ line: String) -> Bool {
        fenceMarker(line) != nil || heading(line) != nil || isRule(line) ||
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">") || listItem(line) != nil
    }

    private static func fenceMarker(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let marks = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(marks.count), line.dropFirst(marks.count).first == " " else { return nil }
        return (marks.count, String(line.dropFirst(marks.count + 1)).trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, "-* _".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func setextHeadingLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first,
              first == "=" || first == "-",
              trimmed.allSatisfy({ $0 == first }) else { return nil }
        return first == "=" ? 1 : 2
    }

    private static func listItem(_ line: String) -> (ordered: Bool, number: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return (false, 1, String(trimmed.dropFirst(2)))
        }
        let digits = trimmed.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, let number = Int(digits),
              trimmed.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return (true, number, String(trimmed.dropFirst(digits.count + 2)))
    }

    private struct TableRow {
        let cells: [String]
        let hasPipe: Bool
    }

    private static func tableHeader(_ line: String, delimiter: String) -> (headers: [String], alignments: [MarkdownTable.Alignment])? {
        guard let header = splitTableRow(line), let separator = splitTableRow(delimiter),
              header.hasPipe || separator.hasPipe,
              !header.cells.isEmpty, header.cells.count == separator.cells.count else { return nil }

        var alignments: [MarkdownTable.Alignment] = []
        for cell in separator.cells {
            let characters = Array(cell)
            let left = characters.first == ":"
            let right = characters.last == ":"
            let dashes = characters.filter { $0 == "-" }.count
            guard dashes >= 1,
                  characters.count == dashes + (left ? 1 : 0) + (right ? 1 : 0) else { return nil }
            alignments.append(left && right ? .center : right ? .trailing : .leading)
        }
        return (header.cells, alignments)
    }

    /// Pipes inside escaped text or a backtick code span are cell content.
    private static func splitTableRow(_ line: String) -> TableRow? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let characters = Array(text)
        var cells: [String] = []
        var current = ""
        var hasPipe = false
        var escaped = false
        var codeFenceLength = 0
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if escaped {
                current.append(character)
                escaped = false
                index += 1
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                index += 1
                continue
            }
            if character == "`" {
                var end = index
                while end < characters.count && characters[end] == "`" { end += 1 }
                let runLength = end - index
                if codeFenceLength == 0 { codeFenceLength = runLength }
                else if codeFenceLength == runLength { codeFenceLength = 0 }
                current += String(repeating: "`", count: runLength)
                index = end
                continue
            }
            if character == "|" && codeFenceLength == 0 {
                hasPipe = true
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        if hasPipe && cells.first == "" && characters.first == "|" { cells.removeFirst() }
        if hasPipe && cells.last == "" && characters.last == "|" { cells.removeLast() }
        return TableRow(cells: cells, hasPipe: hasPipe)
    }
}
