# A document should read as a document

A useful reading view has a clear hierarchy, an easy line length, and a steady
vertical rhythm. This paragraph includes **strong emphasis**, *a quieter aside*,
`inline_code`, a [normal link](https://example.com/reading), and mathematics
$\alpha+\beta=\gamma$ without turning them into separate layout systems.

## A second-level section

The heading should leave enough space above it to show a change of subject,
while remaining close enough to this paragraph to belong to it. Long lines
should wrap naturally instead of stretching across the full width of a
maximized reading pane. A reader should not have to search for the beginning
of each line after looking back from its end.

### A third-level section

This heading must remain distinguishable from both body text and a second-level
heading. Changing the nesting level should not accidentally make it larger.

#### A fourth-level section

A fourth-level heading should still be visible, but should not compete with
the title. Its following paragraph includes a footnote.[^rhythm]

> **A useful quotation.** The quotation's inset and rule should explain its
> relationship to the main text. Long content must remain readable when it
> wraps onto several lines, and its padding should feel intentional.

## Lists and reading order

1. Establish the claim.
2. Explain the reasoning in a sentence long enough to wrap in a narrow pane,
   without confusing its continuation with a new item.
   - Include a supporting observation.
   - Include a second observation with $p(x\mid y)$ inline.
3. End the argument.

- [ ] A pending task.
- [x] A completed task.

---

## Code and the surrounding explanation

The code panel should fit the available measure and leave a clean boundary
before and after its content. It should not expand a short snippet to an
unnecessary page-height box.

```python
def normalize(value, mean, scale):
    """Preserve the mathematical meaning in a practical calculation."""
    if scale <= 0:
        raise ValueError("scale must be positive")
    return (value - mean) / scale
```

This is the final paragraph. It should remain visible after the code, and its
first line should not collide with the code panel or footer.

[^rhythm]: A footnote belongs to the same reading system, with a smaller but
    still legible size and a recognizable return to the main document.
