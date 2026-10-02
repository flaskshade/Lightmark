# Markdown Stress Test Suite 🚀

This document is designed to test the parsing, rendering, and styling capabilities of your Markdown editor. It includes standard CommonMark, GitHub Flavored Markdown (GFM), and common extensions.

## 1. Typography & Inline Formatting

Let's start with the basics, but mixed together.

*   **Bold**, *Italic*, and ***Bold-Italic***.
*   __Bold__, _Italic_, and ___Bold-Italic___ using underscores.
*   ~~Strikethrough~~ (GFM).
*   Inline `code` with spaces: ` inline code `.
*   Inline code with backticks inside: `` `tick` `` or ``` ``double ticks`` ```.
*   Formatting inside words: un**believ**able, re*act*ion.
*   Combined nesting: **Bold with _italic_ and ~~strikethrough~~ and `code`**.
*   Escaped characters: \* \_ \[ \] \( \) \# \+ \- \. \! \\

## 2. Headers (Setext and ATX)

ATX Headers:
# H1
## H2
### H3
#### H4
##### H5
###### H6
####### H7 (This should just be text, not a header)

Setext Headers:
Level 1 Setext Header
=====================

Level 2 Setext Header
---------------------

## 3. Lists and Deep Nesting

This is where parsers often fail. Let's mix list types and deeply nest them.

1. First ordered item
2. Second ordered item
   * Unordered sub-item A
   * Unordered sub-item B
     1. Deeply nested ordered 1
     2. Deeply nested ordered 2
        *   Even deeper unordered
            - [ ] A task list item (GFM)
            - [ ] A completed task list item
            - [ ] Task with **formatting** and a [link](#)
        *   Back to the unordered list
   * Unordered sub-item C
3. Third ordered item, but the number is wrong in source:
8. The parser should render this as '4' in a continuous list.

## 4. Blockquotes & Complex Blocks

Blockquotes can contain other elements, and can be nested.

> This is a standard blockquote.
> It spans multiple lines.
>
> > This is a nested blockquote.
> > * It contains a list
> > * And some `code`
> >
> > > And goes even deeper.
> 
> Back to the first level.
> ### A Header inside a Blockquote
> ```python
> # Code block inside a blockquote
> def hello_world():
>     print("Hello, nested world!")
> ```

## 5. Code Blocks

Indented code block:

    function test() {
      console.log("This is an indented code block.");
    }

Fenced code blocks with language tags (for syntax highlighting):

```javascript
// A JavaScript snippet
const app = new Editor({
  os: 'macOS',
  awesome: true
});
```

```html
<!-- HTML snippet -->
<div class="wrapper">
  <span>Test</span>
</div>
```

Code block with no language, but containing markdown syntax (should NOT be parsed):

```
# This is not a header
**This is not bold**
```

## 6. Links and Images

*   [Standard Link](https://example.com)
*   [Link with title](https://example.com "This is a title tooltip")
*   [**Bold Link**](https://example.com)
*   Reference style links:
    *   [Link 1][ref1]
    *   [Link 2][ref2]
    *   [Implicit reference link][]

[ref1]: https://apple.com "Apple"
[ref2]: https://google.com
[Implicit reference link]: https://github.com

Images:
![Alt text for image](https://via.placeholder.com/150 "Optional Image Title")

Image acting as a link:
[![Placeholder](https://via.placeholder.com/50)](https://example.com)

## 7. Tables (GFM)

Tables with different alignments and inline formatting.

| Left-Aligned  | Center Aligned  | Right Aligned |
| :------------ |:---------------:| -----:|
| col 3 is      | some wordy text | $1600 |
| col 2 is      | centered        |   $12 |
| zebra stripes | are neat        |    $1 |
| **Bold**      | `Inline Code`   | [Link](#) |

## 8. Horizontal Rules

Various valid syntaxes:

---
***
___
- - -
* * *

## 9. Extended Syntax (May not be supported, but good to test)

### Footnotes
Here is a sentence that needs a footnote.[^1] And another one.[^2]

[^1]: This is the text of the first footnote.
[^2]: This is the second footnote. It can even contain multiple paragraphs.

    Like this indented paragraph here.

### Math / LaTeX
Inline math equation: $E = mc^2$ and $a^2 + b^2 = c^2$.

Block math equation:
$$
\frac{n!}{k!(n-k)!} = \binom{n}{k}
$$

$$
\int_{a}^{b} x^2 \,dx
$$

## 10. Raw HTML

Markdown allows raw HTML. Your editor should either render it securely or escape it depending on its configuration.

<details>
  <summary>Click to expand this HTML details block</summary>
  <p>This paragraph is wrapped in raw HTML tags, but contains **Markdown formatting** (depending on the parser, the markdown inside may or may not render).</p>
</details>

<div style="background-color: #f0f0f0; padding: 10px; border-radius: 5px;">
  A div with inline styles.
</div>

<!-- This is an HTML comment. It should be invisible in the rendered output. -->

---
**End of Stress Test.**