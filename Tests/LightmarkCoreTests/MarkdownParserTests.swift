import Foundation
import Testing
@testable import LightmarkCore

@Test func parsesRepresentativeDocument() {
    let source = """
    # Notes

    A **small** edit with a [link](https://example.com).

    - one
    - two

    ```swift
    let value = 1
    ```

    > A useful quote
    """
    #expect(MarkdownParser.parse(source) == [
        .heading(level: 1, text: "Notes"),
        .paragraph("A **small** edit with a [link](https://example.com)."),
        .list(ordered: false, start: 1, items: ["one", "two"]),
        .code(language: "swift", text: "let value = 1"),
        .quote("A useful quote")
    ])
}

@Test func preservesUnclosedFenceAndUnknownSyntax() {
    #expect(MarkdownParser.parse("~~~\ncode\n# still code") == [
        .code(language: nil, text: "code\n# still code")
    ])
    #expect(MarkdownParser.parse("| a | b |") == [.paragraph("| a | b |")])
}

@Test func parsesIndentedCodeFencesAndQuotes() {
    let source = """
       ```python
       print("hello")
       ```

    > Blockquote line 1
    > Blockquote line 2
    """
    #expect(MarkdownParser.parse(source) == [
        .code(language: "python", text: "   print(\"hello\")"),
        .quote("Blockquote line 1\nBlockquote line 2")
    ])
}

@Test func parsesAlignedTablesAndDividers() {
    let source = """
    ### Step 1: translate a food score into a source tier

    The model uses the existing score bands:

    | Food nutrient score | Customer source label | Internal tier | Base signal |
    |---:|---|---:|---:|
    | `8.0–10.0` | Excellent source | `leading` | 3 |
    | `< 4.0` | Limited source | `limited` | 0 |

    ---

    After the divider.
    """
    #expect(MarkdownParser.parse(source) == [
        .heading(level: 3, text: "Step 1: translate a food score into a source tier"),
        .paragraph("The model uses the existing score bands:"),
        .table(MarkdownTable(
            headers: ["Food nutrient score", "Customer source label", "Internal tier", "Base signal"],
            alignments: [.trailing, .leading, .trailing, .trailing],
            rows: [
                ["`8.0–10.0`", "Excellent source", "`leading`", "3"],
                ["`< 4.0`", "Limited source", "`limited`", "0"]
            ]
        )),
        .rule,
        .paragraph("After the divider.")
    ])
}

@Test func supportsCommonTableVariantsWithoutEatingPlainText() {
    let source = """
    Before the table.
    Name | Value
    :--- | ---:
    A \\| B | `x|y`
    Short |

    Not a table | yet
    ordinary paragraph
    """
    #expect(MarkdownParser.parse(source) == [
        .paragraph("Before the table."),
        .table(MarkdownTable(headers: ["Name", "Value"],
                             alignments: [.leading, .trailing],
                             rows: [["A \\| B", "`x|y`"], ["Short", ""]])),
        .paragraph("Not a table | yet\nordinary paragraph")
    ])
}

@Test func distinguishesSetextHeadingsFromStandaloneDividers() {
    #expect(MarkdownParser.parse("Title\n=\n\nSection\n---\n\n* * *") == [
        .heading(level: 1, text: "Title"),
        .heading(level: 2, text: "Section"),
        .rule
    ])
}

@Test func parsesMinimalDashTableDelimiters() {
    let source = """
    | Col A | Col B | Col C |
    | - | :-: | -: |
    | 1 | 2 | 3 |
    """
    #expect(MarkdownParser.parse(source) == [
        .table(MarkdownTable(
            headers: ["Col A", "Col B", "Col C"],
            alignments: [.leading, .center, .trailing],
            rows: [["1", "2", "3"]]
        ))
    ])
}

