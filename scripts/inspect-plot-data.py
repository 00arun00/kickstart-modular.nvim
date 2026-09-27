"""Extract bounded numeric plot data independently of the inspector table page."""

import math
import sys

MAX_CELLS = 100_000


def extract(value, category, options, metadata=False):
    import numpy as np

    if category not in ("array", "tensor", "dataframe", "series"):
        raise ValueError(
            "Plot setup supports numeric DataFrames, Series, NumPy arrays and tensors"
        )
    if category == "tensor" and (
        str(value.layout) != "torch.strided"
        or value.device.type == "meta"
        or value.is_quantized
    ):
        raise ValueError("Plotting requires a dense, non-meta tensor")
    if category == "series":
        value = value.to_frame()
    if category in ("array", "tensor"):
        shape = list(value.shape)
        if not shape:
            raise ValueError(
                "Open a 1D or 2D value (or choose a higher-dimensional slice)"
            )
        prefix = options.get("slice", [0] * max(0, len(shape) - 2))
        if len(prefix) != max(0, len(shape) - 2) or any(
            type(i) is not int or not 0 <= i < n for i, n in zip(prefix, shape)
        ):
            raise ValueError(
                "Invalid leading slice indices; choose the slice in the explorer first"
            )
        if prefix:
            value = value[tuple(prefix)]
        if len(value.shape) == 1:
            value = value.reshape(-1, 1)
        if category == "array" and value.dtype.kind not in "biuf":
            raise ValueError("Choose a real numeric array")
        if category == "tensor" and value.is_complex():
            raise ValueError(
                "Convert complex values to real/imaginary values explicitly"
            )
    rows, cols = value.shape
    descriptors = []
    for i in range(min(cols, 512)):
        if category in ("dataframe", "series"):
            dtype = value.dtypes.iloc[i]
            label = value.columns[i]
            label = (
                str(label)[:100]
                if type(label) in (str, int, float, bool)
                else f"column {i}"
            )
            numeric = dtype.kind in "biuf"
        else:
            label, numeric = ("value" if cols == 1 else str(i)), True
        descriptors.append({"id": i, "label": label, "numeric": numeric})
    schema = {
        "rows": rows,
        "columns": descriptors,
        "column_count": cols,
        "slice": prefix if category in ("array", "tensor") else [],
    }
    if metadata:
        return schema
    style = options.get("style", "line")
    if style not in ("line", "scatter", "histogram", "heatmap"):
        raise ValueError("Choose line, scatter, histogram or heatmap")
    numeric_ids = [c["id"] for c in descriptors if c["numeric"]]
    ys = options.get("ys", numeric_ids[:1])
    if (
        type(ys) is not list
        or not ys
        or any(type(i) is not int or i not in numeric_ids for i in ys)
    ):
        raise ValueError("Choose numeric Y columns by their zero-based column IDs")
    ys = list(dict.fromkeys(ys))
    if style != "heatmap" and len(ys) > 8:
        raise ValueError("Choose at most 8 Y series")
    x = options.get("x", -1)
    if type(x) is not int or (x != -1 and x not in numeric_ids):
        raise ValueError("X must be row position or a numeric column ID")
    start, stop = options.get("start", 0), options.get("stop", rows)
    if type(start) is not int or type(stop) is not int or not 0 <= start < stop <= rows:
        raise ValueError(
            f"Use a nonempty row range: 0 <= start < stop <= {rows} (stop exclusive)"
        )
    limit = options.get("limit", 5000)
    if type(limit) is not int or not 10 <= limit <= 20_000:
        raise ValueError("Point budget must be an integer from 10 to 20000")
    selected = list(
        dict.fromkeys(ys + ([x] if x >= 0 and style in ("line", "scatter") else []))
    )
    total = stop - start
    if style == "histogram":
        if total * len(selected) > MAX_CELLS:
            raise ValueError(
                "Exact histograms are limited to 100,000 selected values; narrow the row range or select fewer series"
            )
        count = total
    elif style == "heatmap":
        if limit < len(selected):
            raise ValueError(
                "Heatmap budget must include at least one row of all selected columns"
            )
        count = min(total, max(1, limit // len(selected)), MAX_CELLS // len(selected))
    else:
        count = min(total, limit, MAX_CELLS // len(selected))
    indices = (
        np.linspace(start, stop - 1, count, dtype=np.int64)
        if count < total
        else np.arange(start, stop)
    )
    if category in ("dataframe", "series"):
        block = value.iloc[indices, selected].to_numpy()
    elif category == "tensor":
        torch = sys.modules["torch"]
        # Advanced indexing bounds allocation before copying from GPU to CPU.
        ri = torch.tensor(indices, device=value.device)
        ci = torch.tensor(selected, device=value.device)
        block = (
            value[ri[:, None], ci[None, :]]
            .detach()
            .to(device="cpu", dtype=torch.float64)
            .numpy()
        )
    else:
        block = value[np.ix_(indices, selected)]
    mapping = {col: i for i, col in enumerate(selected)}
    labels = {d["id"]: f"{d['label']} [{d['id']}]" for d in descriptors}

    def number(v):
        try:
            f = float(v)
        except (TypeError, ValueError, OverflowError):
            return None
        if math.isfinite(f) and abs(f) > 1e150:
            raise ValueError(
                "Rescale values larger than 1e150 in Python before plotting"
            )
        return f if math.isfinite(f) else None

    records, skipped = [], 0
    if style == "histogram":
        bins = options.get("bins", 30)
        if type(bins) is not int or not 2 <= bins <= 200:
            raise ValueError("Histogram bins must be an integer from 2 to 200")
        all_finite = [number(v) for v in block.flat]
        all_finite = [v for v in all_finite if v is not None]
        edges = np.histogram_bin_edges(all_finite, bins=bins) if all_finite else None
        for col in ys:
            values = [number(v) for v in block[:, mapping[col]]]
            finite = [v for v in values if v is not None]
            skipped += len(values) - len(finite)
            if not finite:
                continue
            if max(abs(v) for v in finite) > 1e150:
                raise ValueError(
                    "Histogram values exceed the supported numeric range; rescale in Python"
                )
            counts, edges = np.histogram(finite, bins=edges)
            records.extend(
                {
                    "x": float(edges[i]),
                    "x2": float(edges[i + 1]),
                    "y": int(n),
                    "series": labels[col],
                }
                for i, n in enumerate(counts)
            )
    elif style == "heatmap":
        for i, row in enumerate(indices):
            for col in ys:
                y = number(block[i, mapping[col]])
                skipped += y is None
                records.append({"x": labels[col], "row": str(int(row)), "value": y})
    else:
        for col in ys:
            segment = 0
            for i, row in enumerate(indices):
                xv = float(row) if x == -1 else number(block[i, mapping[x]])
                y = number(block[i, mapping[col]])
                if xv is None or y is None:
                    segment += 1
                    skipped += 1
                    continue
                records.append(
                    {
                        "x": xv,
                        "y": y,
                        "order": int(row),
                        "series": labels[col],
                        "segment": str(col) + ":" + str(segment),
                    }
                )
    if not records or (
        style == "heatmap" and not any(r["value"] is not None for r in records)
    ):
        raise ValueError("No finite numeric values in the selected range")
    sampling = (
        "Complete range"
        if count == total
        else "Uniform row-position sampling (can miss spikes)"
    )
    caption = f"{rows:,} source rows · range [{start}, {stop}) · {count:,}/{total:,} rows · {sampling}"
    if skipped:
        caption += f" · {skipped:,} missing/nonfinite values"
    return {
        "schema": schema,
        "style": style,
        "records": records,
        "caption": caption,
        "sampled": count < total,
        "source_rows": rows,
        "range_rows": total,
        "emitted_rows": count,
        "skipped": skipped,
        "x_label": "Row position" if x == -1 else labels[x],
        "y_labels": [labels[y] for y in ys],
    }
