# Advanced Markdown

## Flowchart

```mermaid
flowchart LR
    Open[Open Markdown] --> Read[Read]
    Read --> Edit{Make changes?}
    Edit -->|Yes| Save[Save]
    Edit -->|No| Close[Close]
    Save --> Close
```

## Sequence diagram

```mermaid
sequenceDiagram
    participant User
    participant Lightmark
    User->>Lightmark: Open file
    Lightmark-->>User: Show document
    User->>Lightmark: Edit and close
    Lightmark-->>User: Save changes?
```

## Definition lists

Markdown
: A readable plain-text document format.

Mermaid
: Diagrams described in fenced code blocks.

## Highlights and scientific notation

==Remember this==. Water: H~2~O. Area: x^2^.
