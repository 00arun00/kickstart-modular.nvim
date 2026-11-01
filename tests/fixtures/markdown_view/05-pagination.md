# A long mixed document

This note deliberately crosses page boundaries. Read the continuous layout
first, then compare the paginated layout. Tables, code, and equations should
stay within the page body, with clear continuation and no lost content.

## An opening argument

Every block has a role. Prose establishes context, equations expose structure,
tables compare values, and code makes an operation concrete. Page boundaries
should respect those roles without creating excessive empty space or hiding
the last line behind a footer.

$$
\frac{\partial p_t(x)}{\partial t}+\nabla\cdot\bigl(p_t(x)u_t(x)\bigr)=0
$$

## A table that continues

| Row | Description | Result |
|:---|:---|---:|
| 01 | Each row has enough explanation to wrap at a narrow reading width. | 1 |
| 02 | A repeated table header should make continuation understandable. | 4 |
| 03 | The last line must remain above the page footer. | 9 |
| 04 | Equations such as $x^2+y^2$ remain part of their table cell. | 16 |
| 05 | A reader should not need to infer which column continues. | 25 |
| 06 | Some descriptions are longer, but no row may vanish. | 36 |
| 07 | Numerical alignment should remain stable between pages. | 49 |
| 08 | All content belongs inside the reading area. | 64 |
| 09 | Narrow columns should still provide a readable measure. | 81 |
| 10 | Rows may continue, with a clear sense of the table structure. | 100 |
| 11 | A short row can follow a wrapped row without collision. | 121 |
| 12 | The final row has a distinct ending marker: TABLE_END. | 144 |

## A code block that continues

```python
values = []
for step in range(24):
    value = step * step
    values.append(value)
    # A readable comment explains the operation without becoming the headline.

def summarize(values):
    total = sum(values)
    count = len(values)
    mean = total / count if count else 0
    return {
        "count": count,
        "total": total,
        "mean": mean,
    }

summary = summarize(values)
print("count", summary["count"])
print("total", summary["total"])
print("mean", summary["mean"])
print("CODE_END")
```

## The final equation

The end of the document should have the same alignment and spacing as its
beginning, even if a page break lands immediately before the display.

$$
\int_{-\infty}^{\infty}\frac{1}{\sqrt{2\pi}}e^{-x^2/2}\,dx=1
$$

The ending marker is DOCUMENT_END. It must be present in both layouts.
