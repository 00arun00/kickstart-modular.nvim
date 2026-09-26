"""Dependency-free SVG plots of the explicitly requested, bounded table page."""

from html import escape
from math import hypot


def draw(rows, style, title, column=0, row_offset=0, col_offset=0):
    if style not in {"line", "histogram", "heatmap"}:
        raise ValueError("Choose line, histogram, or heatmap")
    if not rows or not any(rows):
        raise ValueError("No values in this page to plot")
    column = min(max(column, 0), len(rows[0]) - 1)
    points = [
        (i, r[column])
        for i, r in enumerate(rows)
        if column < len(r) and r[column] is not None
    ]
    values = (
        [v for r in rows for v in r if v is not None]
        if style == "heatmap"
        else [v for _, v in points]
    )
    if not values:
        raise ValueError("The selected column/page contains no finite numeric values")
    low, high = min(values), max(values)
    scale = max(abs(low), abs(high), 1)
    span = (high / scale - low / scale) or 1

    def normalize(v):
        return (v / scale - low / scale) / span

    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="480" viewBox="0 0 800 480">',
        '<rect width="800" height="480" rx="16" fill="#1e1e2e"/>',
        f'<text x="56" y="44" fill="#cdd6f4" font-family="sans-serif" font-size="21">{escape(title[:65])}</text>',
        f'<text x="56" y="72" fill="#a6adc8" font-family="sans-serif" font-size="13">{style.title()} · current page · rows {row_offset}–{row_offset + len(rows) - 1} · column {col_offset + column}</text>',
    ]

    def label(x, y, value, anchor="end"):
        parts.append(
            f'<text x="{x}" y="{y}" text-anchor="{anchor}" fill="#a6adc8" font-family="sans-serif" font-size="12">{value:.4g}</text>'
        )

    if style == "heatmap":
        width = max(len(r) for r in rows)
        for i, r in enumerate(rows):
            for j, v in enumerate(r):
                t = normalize(v) if v is not None else 0
                color = (
                    "#45475a"
                    if v is None
                    else f"#{int(49 + 154 * t):02x}{int(50 + 116 * t):02x}{int(68 + 179 * t):02x}"
                )
                parts.append(
                    f'<rect x="{72 + j * 660 / width:.2f}" y="{100 + i * 300 / len(rows):.2f}" width="{660 / width - 1:.2f}" height="{300 / len(rows) - 1:.2f}" fill="{color}"/>'
                )
        label(72, 424, col_offset, "start")
        label(732, 424, col_offset + width - 1)
        label(62, 112, row_offset)
        label(62, 400, row_offset + len(rows) - 1)
    else:
        for i in range(5):
            y = 100 + i * 75
            parts.append(
                f'<rect x="72" y="{y}" width="660" height="1" fill="#45475a"/>'
            )
            if style == "line":
                label(62, y + 4, (1 - i / 4) * high + (i / 4) * low)
        if style == "line":
            # Segments stop at missing/nonfinite values rather than bridging gaps.
            for i in range(1, len(rows)):
                a = rows[i - 1][column] if column < len(rows[i - 1]) else None
                b = rows[i][column] if column < len(rows[i]) else None
                if a is None or b is None:
                    continue
                x1, x2 = (
                    72 + (i - 1) * 660 / max(1, len(rows) - 1),
                    72 + i * 660 / max(1, len(rows) - 1),
                )
                y1, y2 = 400 - normalize(a) * 300, 400 - normalize(b) * 300
                length = hypot(x2 - x1, y2 - y1) or 1
                dx, dy = -(y2 - y1) * 1.5 / length, (x2 - x1) * 1.5 / length
                coords = " ".join(
                    f"{x:.2f},{y:.2f}"
                    for x, y in [
                        (x1 + dx, y1 + dy),
                        (x2 + dx, y2 + dy),
                        (x2 - dx, y2 - dy),
                        (x1 - dx, y1 - dy),
                    ]
                )
                # Filled polygons also work in ImageMagick builds with broken SVG strokes.
                parts.append(f'<polygon points="{coords}" fill="#89b4fa"/>')
            for i, v in points:
                parts.append(
                    f'<circle cx="{72 + i * 660 / max(1, len(rows) - 1):.2f}" cy="{400 - normalize(v) * 300:.2f}" r="3" fill="#cba6f7"/>'
                )
            label(72, 424, row_offset, "start")
            label(732, 424, row_offset + len(rows) - 1)
        else:
            bins = [0] * min(10, len(values))
            for v in values:
                bins[min(len(bins) - 1, int(normalize(v) * len(bins)))] += 1
            peak = max(bins)
            for i, count in enumerate(bins):
                h = count * 300 / peak
                parts.append(
                    f'<rect x="{72 + i * 660 / len(bins):.2f}" y="{400 - h:.2f}" width="{660 / len(bins) - 3:.2f}" height="{h:.2f}" rx="3" fill="#89b4fa"/>'
                )
            for i in range(5):
                label(62, 104 + i * 75, peak * (1 - i / 4))
            label(72, 424, low, "start")
            label(732, 424, high)
    parts.append(
        f'<text x="56" y="458" fill="#a6adc8" font-family="sans-serif" font-size="12">{len(values)} finite values · min {low:.5g} · max {high:.5g} · bounded preview, not the full dataset</text></svg>'
    )
    return "".join(parts)
