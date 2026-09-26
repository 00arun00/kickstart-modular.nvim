"""Kernel-side inspection. No arbitrary expressions, repr, imports of user packages,
or writes to the user namespace. Value materialization happens only on preview.
"""

import itertools
import sys
import types

ROWS, COLS, VARIABLES = 20, 8, 200


def text(value, limit=100):
    if type(value) is str:
        return value[:limit].replace("\n", " ↵ ").replace("\r", " ")
    if type(value) in (int, float, bool, complex, type(None)):
        try:
            return str(value)[:limit]
        except ValueError:
            return "<large integer>"
    return "<" + type(value).__name__ + ">"


def kind(value):
    # Only known exact types: subclasses can override ordinary inspection methods.
    torch = sys.modules.get("torch")
    if torch and type(value) in (torch.Tensor, torch.nn.Parameter):
        return "tensor"
    np = sys.modules.get("numpy")
    if np and type(value) is np.ndarray:
        return "array"
    pd = sys.modules.get("pandas")
    if pd and type(value) is pd.DataFrame:
        return "dataframe"
    return "object"


def describe(name, value):
    category = kind(value)
    item = {"name": name, "type": type(value).__name__, "kind": category, "summary": ""}
    if category in ("tensor", "array", "dataframe"):
        item["shape"] = list(value.shape)
        if category != "dataframe":
            item["dtype"] = str(value.dtype)
        if category == "tensor":
            item["device"] = str(value.device)
            item["requires_grad"] = bool(value.requires_grad)
            item["layout"] = str(value.layout)
    elif type(value) in (list, tuple, dict, set, frozenset, str, bytes):
        item["summary"] = (
            f"{len(value)} items" if type(value) is not str else text(value)
        )
    else:
        item["summary"] = text(value)
    return item


def scalar(value):
    np = sys.modules.get("numpy")
    if np and isinstance(value, np.generic) and value.dtype.kind in "biufcSU":
        return text(value.item())
    return text(value)


def inspect_namespace(namespace, request):
    name = request.get("name")
    if name is None:
        entries = []
        more = False
        for key, value in namespace.items():
            if (
                not isinstance(key, str)
                or key.startswith("_")
                or key in {"In", "Out", "exit", "quit", "get_ipython", "open"}
            ):
                continue
            if isinstance(
                value,
                (types.ModuleType, types.FunctionType, types.BuiltinFunctionType, type),
            ):
                continue
            if len(entries) == VARIABLES:
                more = True
                break
            entries.append(describe(key, value))
        return {
            "entries": sorted(entries, key=lambda item: item["name"].lower()),
            "more": more,
        }
    if not isinstance(name, str) or name not in namespace:
        return {"error": "Variable no longer exists; refresh the list"}
    value = namespace[name]
    result = describe(name, value)
    row = max(0, int(request.get("row", 0)))
    col = max(0, int(request.get("col", 0)))
    category = result["kind"]
    if category in ("tensor", "array", "dataframe"):
        shape = result["shape"]
        if category == "tensor" and (
            str(value.layout) != "torch.strided"
            or value.device.type == "meta"
            or value.is_quantized
        ):
            result["note"] = (
                "Value preview unavailable for sparse, quantized, or meta tensors."
            )
            return result
        height = shape[-2] if len(shape) >= 2 else (shape[0] if shape else 1)
        width = shape[-1] if len(shape) >= 2 else 1
        row = min(row, max(0, height - 1))
        col = min(col, max(0, width - 1))
        result.update(row=row, col=col, total_rows=height, total_cols=width)
        if category == "dataframe":
            block = value.iloc[row : row + ROWS, col : col + COLS]
            result["columns"] = [scalar(v) for v in block.columns]
            result["rows"] = [
                [scalar(v) for v in r] for r in block.itertuples(index=False, name=None)
            ]
            result["index"] = [scalar(v) for v in block.index]
        else:
            if len(shape) > 2 and any(s == 0 for s in shape[:-2]):
                result["note"] = "Empty tensor/array: no slice to preview."
                return result
            prefix = (0,) * max(0, len(shape) - 2)
            if len(shape) >= 2:
                block = value[prefix + (slice(row, row + ROWS), slice(col, col + COLS))]
            elif shape:
                block = value[row : row + ROWS]
            else:
                block = value
            if category == "tensor":
                # Transfer only the requested <=160 elements, on explicit preview.
                block = block.detach().to("cpu")
            raw = block.tolist()
            raw = raw if shape else [raw]
            raw = raw if len(shape) >= 2 else [[v] for v in raw]
            result["rows"] = [[text(v) for v in r] for r in raw]
            if prefix:
                result["note"] = (
                    "Showing slice ["
                    + ", ".join(["0"] * len(prefix) + [":", ":"])
                    + "]"
                )
        return result
    if type(value) in (list, tuple, dict, set, frozenset):
        total = len(value)
        row = min(row, max(0, total - 1))
        items = value.items() if type(value) is dict else enumerate(value)
        result.update(
            row=row,
            col=0,
            total_rows=total,
            total_cols=1,
            rows=[
                [text(k), text(v)] for k, v in itertools.islice(items, row, row + ROWS)
            ],
        )
        return result
    result["note"] = (
        text(value, 1000)
        if type(value) in (str, int, float, bool, complex, type(None))
        else "Metadata only; custom object repr is not evaluated."
    )
    return result
