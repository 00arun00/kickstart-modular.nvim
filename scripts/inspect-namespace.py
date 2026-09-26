"""Bounded kernel inspection with structural paths, table views and explicit renderers."""

import inspect
import itertools
import json
import math
import operator
import runpy
import sys
import types
from pathlib import Path

ROWS, COLS, VARIABLES = 20, 8, 100


def text(value, limit=100):
    if type(value) is str:
        return value[:limit] + (
            f"… [truncated at {limit} characters]" if len(value) > limit else ""
        )
    if type(value) in (int, float, bool, complex, type(None)):
        try:
            return str(value)[:limit]
        except ValueError:
            return "<large integer>"
    np = sys.modules.get("numpy")
    if np and isinstance(value, np.generic) and value.dtype.kind in "biufcSU":
        return text(value.item(), limit)
    return "<" + type(value).__name__ + ">"


def kind(value):
    torch = sys.modules.get("torch")
    if torch and type(value) in (torch.Tensor, torch.nn.Parameter):
        return "tensor"
    np = sys.modules.get("numpy")
    if np and type(value) is np.ndarray:
        return "array"
    pd = sys.modules.get("pandas")
    if pd and type(value) in (pd.DataFrame, pd.Series):
        return "dataframe" if type(value) is pd.DataFrame else "series"
    return "object"


def table_rows(result, rows):
    """Keep exact value text separate from compact float presentation."""
    np = sys.modules.get("numpy")

    def display(value):
        if type(value) is float or (np and isinstance(value, np.floating)):
            return format(value, ".6g")
        return text(value, 4000)

    result["rows"] = [[text(v, 4000) for v in row] for row in rows]
    result["display_rows"] = [[display(v) for v in row] for row in rows]


def fields(value):
    # Bypass user __getattribute__, and never evaluate a property/slot descriptor.
    descriptor = inspect.getattr_static(type(value), "__dict__", None)
    if isinstance(descriptor, types.GetSetDescriptorType):
        try:
            result = object.__getattribute__(value, "__dict__")
        except AttributeError:
            return None
        if type(result) is dict:
            return result
    return None


def describe(name, value):
    category = kind(value)
    item = {"name": name, "type": type(value).__name__, "kind": category, "summary": ""}
    pil = sys.modules.get("PIL.Image")
    if pil and isinstance(value, pil.Image):
        item["image"] = True
    if category in ("tensor", "array", "dataframe", "series"):
        item["shape"] = list(value.shape)
        if category != "dataframe":
            item["dtype"] = str(value.dtype)
        if category == "tensor":
            item.update(
                device=str(value.device),
                requires_grad=bool(value.requires_grad),
                layout=str(value.layout),
            )
    elif type(value) in (list, tuple, dict, set, frozenset, str, bytes):
        item["size"] = len(value)
        item["summary"] = (
            f"{len(value)} items" if type(value) is not str else text(value)
        )
    else:
        item["summary"] = text(value)
    return item


def resolve(namespace, name, path):
    if name not in namespace:
        raise ValueError("Variable no longer exists; return to the list and refresh")
    value, label = namespace[name], name
    for step in path:
        key, mode = step["key"], step["kind"]
        if mode == "int_key" and type(key) is str:
            key, mode = int(key), "key"
        if mode == "index" and type(value) in (list, tuple) and type(key) is int:
            value = value[key]
            label += f"[{key}]"
        elif (
            mode == "key"
            and type(value) is dict
            and type(key) in (str, int, float, bool, type(None))
        ):
            value = value[key]
            label += "[" + json.dumps(key, ensure_ascii=False) + "]"
        elif mode == "attr" and type(key) is str and fields(value) is not None:
            value = fields(value)[key]
            label += "." + key
        else:
            raise ValueError("This path is no longer inspectable; return to its parent")
    return value, label


def filtered_frame(value, request):
    frame = value.to_frame() if kind(value) == "series" else value
    filtering, sorting = request.get("filter"), request.get("sort_col")
    if not filtering and sorting is None:
        return frame
    if len(frame) > 100000:
        raise ValueError(
            "Sort/filter is limited to 100,000 rows; narrow the data in Python first"
        )
    if filtering:
        pos, op, target = filtering["column"], filtering["op"], filtering["value"]
        series = frame.iloc[:, pos]
        if series.dtype.kind == "O" and not all(
            type(v) in (str, int, float, bool, type(None)) for v in series
        ):
            raise ValueError("Object-column filtering requires plain strings/numbers")
        if op == "contains":
            mask = series.map(
                lambda v: type(v) is str and str(target).casefold() in v.casefold()
            )
        else:
            operations = {
                "==": operator.eq,
                "!=": operator.ne,
                ">": operator.gt,
                "<": operator.lt,
                ">=": operator.ge,
                "<=": operator.le,
            }
            if op not in operations:
                raise ValueError("Supported filters: contains, ==, !=, >, <, >=, <=")
            mask = operations[op](series, target).fillna(False)
        frame = frame.loc[mask]
    if sorting is not None:
        series = frame.iloc[:, sorting].reset_index(drop=True)
        if series.dtype.kind == "O" and not all(
            type(v) in (str, int, float, bool, type(None)) for v in series
        ):
            raise ValueError("Object-column sorting requires plain strings/numbers")
        order = series.sort_values(
            ascending=not request.get("descending"), kind="stable", na_position="last"
        ).index
        frame = frame.iloc[order]
    return frame


def number(value):
    try:
        if type(value) in (str, int, float, bool):
            result = float(value)
            return result if math.isfinite(result) else None
    except (ValueError, OverflowError):
        pass
    return None


def inspect_namespace(namespace, request):
    try:
        return inspect_value(namespace, request)
    except (ValueError, KeyError, IndexError, TypeError, AttributeError) as exc:
        return {"error": str(exc)}


def inspect_value(namespace, request):
    name, path = request.get("name"), request.get("path", [])
    row, col = max(0, int(request.get("row", 0))), max(0, int(request.get("col", 0)))
    if name is None:
        entries = []
        needle = request.get("query", "").casefold()
        for key, value in namespace.items():
            if (
                not isinstance(key, str)
                or (key.startswith("_") and not request.get("hidden"))
                or key in {"In", "Out", "exit", "quit", "get_ipython", "open"}
            ):
                continue
            if isinstance(
                value,
                (types.ModuleType, types.FunctionType, types.BuiltinFunctionType, type),
            ):
                continue
            item = describe(key, value)
            if needle and needle not in (key + " " + item["type"]).casefold():
                continue
            entries.append(item)
        sort = request.get("sort", "name")
        entries.sort(
            key=lambda item: (
                item["type"].casefold() if sort == "type" else "",
                item["name"].casefold(),
            ),
            reverse=bool(request.get("descending")),
        )
        row = min(row, max(0, len(entries) - 1))
        return {
            "entries": entries[row : row + VARIABLES],
            "total": len(entries),
            "row": row,
            "more": row + VARIABLES < len(entries),
            "page_size": VARIABLES,
        }
    value, label = resolve(namespace, name, path)
    if request.get("action") == "image":
        preview = runpy.run_path(str(Path(__file__).with_name("inspect-image.py")))[
            "preview"
        ]
        return {
            "name": label,
            "image": preview(value, request.get("image_options", {})),
        }
    result = describe(label, value)
    result["path"] = path
    category = result["kind"]
    renderer = request.get("renderer")
    cols = max(1, min(COLS, int(request.get("cols", COLS))))
    if (request.get("filter") or request.get("sort_col") is not None) and (
        renderer or category not in ("dataframe", "series")
    ):
        raise ValueError(
            "Filtering/sorting is available for standard DataFrame and Series views"
        )
    if request.get("slice") and (
        category not in ("tensor", "array") or len(result["shape"]) <= 2
    ):
        raise ValueError(
            "Leading slices apply to tensors/arrays with more than two dimensions"
        )
    if renderer:
        registry = namespace.get("__nvim_inspect_renderers__", {})
        if (
            type(registry) is not dict
            or renderer not in registry
            or not callable(registry[renderer])
        ):
            raise ValueError(
                "Unknown renderer. Register a callable in __nvim_inspect_renderers__."
            )
        rendered = registry[renderer](value)
        if type(rendered) is not dict:
            raise ValueError("Renderer must return a dict with rows/columns or note")
        rows = rendered.get("rows", [])
        if (
            type(rows) is not list
            or len(rows) > 10000
            or any(type(r) not in (list, tuple) for r in rows)
        ):
            raise ValueError(
                "Renderer rows must be a list of at most 10,000 lists/tuples"
            )
        height, width = len(rows), max([len(r) for r in rows] or [0])
        row, col = min(row, max(0, height - 1)), min(col, max(0, width - 1))
        table_rows(result, [r[col : col + cols] for r in rows[row : row + ROWS]])
        result["columns"] = [
            text(v)
            for v in rendered.get("columns", [str(i) for i in range(width)])[
                col : col + cols
            ]
        ]
        result.update(
            row=row,
            col=col,
            total_rows=height,
            total_cols=width,
            note=text(rendered.get("note", "Custom renderer: " + renderer), 4000),
        )
    elif category in ("tensor", "array", "dataframe", "series"):
        shape = result["shape"]
        if category == "tensor" and (
            str(value.layout) != "torch.strided"
            or value.device.type == "meta"
            or value.is_quantized
        ):
            result["note"] = "Metadata only for sparse, quantized, or meta tensors."
            return result
        if category in ("dataframe", "series"):
            frame = filtered_frame(value, request)
            height, width = frame.shape
            result["view_shape"] = [height, width]
        else:
            height = shape[-2] if len(shape) >= 2 else (shape[0] if shape else 1)
            width = shape[-1] if len(shape) >= 2 else 1
        row, col = min(row, max(0, height - 1)), min(col, max(0, width - 1))
        result.update(row=row, col=col, total_rows=height, total_cols=width)
        if category in ("dataframe", "series"):
            block = frame.iloc[row : row + ROWS, col : col + cols]
            result["columns"] = [text(v) for v in block.columns]
            table_rows(result, list(block.itertuples(index=False, name=None)))
            result["index"] = [text(v) for v in block.index]
        else:
            if len(shape) > 2 and any(s == 0 for s in shape[:-2]):
                result["note"] = "Empty tensor/array: no slice to preview."
                return result
            prefix = request.get("slice", [0] * max(0, len(shape) - 2))
            if len(prefix) != max(0, len(shape) - 2) or any(
                type(i) is not int or not 0 <= i < size
                for i, size in zip(prefix, shape)
            ):
                raise ValueError(
                    "Slice must contain one valid index per leading dimension: "
                    + str(shape[:-2])
                )
            result["slice"] = prefix
            if len(shape) >= 2:
                block = value[
                    tuple(prefix) + (slice(row, row + ROWS), slice(col, col + cols))
                ]
            elif shape:
                block = value[row : row + ROWS]
            else:
                block = value
            if category == "tensor":
                block = block.detach().to("cpu")
            raw = block.tolist()
            raw = raw if shape else [raw]
            raw = raw if len(shape) >= 2 else [[v] for v in raw]
            table_rows(result, raw)
            result["columns"] = [str(i) for i in range(col, min(col + cols, width))]
            if prefix:
                result["note"] = "Slice [" + ", ".join(map(str, prefix)) + ", :, :]"
    else:
        mapping = fields(value)
        children = []
        if type(value) in (list, tuple, dict, set, frozenset) or mapping is not None:
            container = mapping if mapping is not None else value
            total = len(container)
            row = min(row, max(0, total - 1))
            iterator = (
                container.items() if type(container) is dict else enumerate(container)
            )
            for key, child in itertools.islice(iterator, row, row + ROWS):
                step = None
                if mapping is not None and type(key) is str:
                    step = {"kind": "attr", "key": key}
                elif (
                    type(value) is dict
                    and type(key) in (str, int, float, bool, type(None))
                    and not (type(key) is float and not math.isfinite(key))
                ):
                    step = {"kind": "key", "key": key}
                    if type(key) is int and abs(key) > 2**53:
                        step = {"kind": "int_key", "key": str(key)}
                elif type(value) in (list, tuple):
                    step = {"kind": "index", "key": key}
                item = describe(text(key), child)
                item["path"] = path + [step] if step else None
                children.append(item)
            result.update(
                children=children, row=row, col=0, total_rows=total, total_cols=1
            )
        else:
            result["note"] = (
                text(value, 10000)
                if type(value) in (str, int, float, bool, complex, type(None))
                else "No stored fields. Properties and custom repr are not evaluated."
            )
    if "rows" in result:
        numeric = [[number(v) for v in r] for r in result["rows"]]
        selected = max(0, int(request.get("selected_col", 0)))
        values = [
            r[selected]
            for r in numeric
            if selected < len(r) and r[selected] is not None
        ]
        if values:
            result["stats"] = {
                "count": len(values),
                "min": min(values),
                "max": max(values),
                "mean": math.fsum(v / len(values) for v in values),
                "column": selected,
            }
        if request.get("action") == "plot":
            draw = runpy.run_path(str(Path(__file__).with_name("inspect-plot.py")))[
                "draw"
            ]
            result["plot"] = draw(
                numeric,
                request.get("plot", "line"),
                label
                + " · "
                + (
                    result.get("columns", [str(col + selected)])[selected]
                    if selected < len(result.get("columns", []))
                    else str(col + selected)
                ),
                int(request.get("selected_col", 0)),
                row,
                col,
            )
    return result
