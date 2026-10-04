"""Render a plot snapshot in the editor host, using browser-free Vega-Lite."""

import json
import math
import sys
import textwrap
from pathlib import Path

import vl_convert as vlc


def specification(data, settings):
    style = data["style"]
    tooltip = [
        {
            "field": f,
            "type": "quantitative"
            if f in ("x", "y", "x2", "value", "order") and style != "heatmap"
            else "nominal",
        }
        for f in (("x", "row", "value") if style == "heatmap" else ("series", "x", "y"))
    ]
    spec = {
        "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
        "width": 880,
        "height": 440,
        "background": "#181825",
        "padding": 24,
        "title": {
            "text": textwrap.wrap(settings.get("title") or "Variable plot", 75),
            "subtitle": textwrap.wrap(data["caption"], 110),
            "anchor": "start",
            "offset": 24,
        },
        "data": {"values": data["records"]},
        "config": {
            "font": "Arial",
            "view": {"stroke": None},
            "axis": {
                "labelColor": "#bac2de",
                "titleColor": "#cdd6f4",
                "gridColor": "#313244",
                "domainColor": "#585b70",
                "tickColor": "#585b70",
                "labelFontSize": 12,
                "titleFontSize": 13,
                "titlePadding": 14,
            },
            "title": {
                "color": "#cdd6f4",
                "fontSize": 22,
                "subtitleColor": "#a6adc8",
                "subtitleFontSize": 12,
            },
            "legend": {
                "labelColor": "#cdd6f4",
                "titleColor": "#bac2de",
                "orient": "top",
                "labelLimit": 250,
            },
            "range": {
                "category": [
                    "#89b4fa",
                    "#f5c2e7",
                    "#a6e3a1",
                    "#fab387",
                    "#cba6f7",
                    "#f9e2af",
                    "#94e2d5",
                    "#f38ba8",
                ]
            },
        },
    }
    color = {
        "field": "series",
        "type": "nominal",
        "title": None,
        "legend": {} if settings.get("legend", True) else None,
    }
    if style == "heatmap":
        spec["mark"] = {"type": "rect", "tooltip": True}

        def ticks(field, maximum):
            values = list(dict.fromkeys(r[field] for r in data["records"]))
            step = max(1, math.ceil(len(values) / maximum))
            return values[::step]

        spec["encoding"] = {
            "x": {
                "field": "x",
                "type": "ordinal",
                "sort": None,
                "title": settings.get("xlabel") or "Column",
                "axis": {
                    "values": ticks("x", 16),
                    "labelLimit": 120,
                    "labelOverlap": True,
                },
            },
            "y": {
                "field": "row",
                "type": "ordinal",
                "sort": None,
                "title": settings.get("ylabel") or "Source row",
                "axis": {"values": ticks("row", 16), "labelOverlap": True},
            },
            "color": {
                "field": "value",
                "type": "quantitative",
                "scale": {"scheme": "viridis"},
                "legend": {} if settings.get("legend", True) else None,
            },
            "tooltip": tooltip,
        }
    else:
        spec["encoding"] = {
            "x": {
                "field": "x",
                "type": "quantitative",
                "title": settings.get("xlabel")
                or (data["x_label"] if style != "histogram" else "Value"),
                "scale": {"zero": False},
            },
            "y": {
                "field": "y",
                "type": "quantitative",
                "title": settings.get("ylabel")
                or ("Count" if style == "histogram" else "Value"),
                "scale": {"zero": style == "histogram"},
            },
            "color": color,
            "tooltip": tooltip,
        }
        if style == "line":
            spec["mark"] = {
                "type": "line",
                "strokeWidth": 2.5,
                "point": len(data["records"]) < 200,
                "clip": True,
            }
            spec["encoding"]["order"] = {"field": "order", "type": "quantitative"}
            spec["encoding"]["detail"] = {"field": "segment"}
        elif style == "scatter":
            spec["mark"] = {
                "type": "point",
                "filled": True,
                "size": 35,
                "opacity": 0.7,
                "clip": True,
            }
        else:
            spec["mark"] = {"type": "bar", "opacity": 0.65, "clip": True}
            spec["encoding"]["x"]["bin"] = "binned"
            spec["encoding"]["x2"] = {"field": "x2"}
            spec["encoding"]["y"]["stack"] = None
        spec["params"] = [
            {
                "name": "navigation",
                "select": {"type": "interval"},
                "bind": "scales",
            }
        ]
    return spec


def render(payload, folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    data, settings = payload["data"], payload["settings"]
    spec = specification(data, settings)
    base = folder / "plot"
    base.with_suffix(".json").write_text(json.dumps(spec, ensure_ascii=False))
    base.with_suffix(".svg").write_text(vlc.vegalite_to_svg(spec))
    base.with_suffix(".png").write_bytes(vlc.vegalite_to_png(spec, scale=1.5))
    # Bundle assets, escape inline JSON and disable outbound editor links.
    encoded = (
        json.dumps(spec, ensure_ascii=False)
        .replace("<", "\\u003c")
        .replace("\u2028", "\\u2028")
        .replace("\u2029", "\\u2029")
    )
    bundle = vlc.javascript_bundle()
    html = (
        '<!doctype html><meta charset="utf-8"><title>Notebook plot</title><style>body{background:#181825;color:#cdd6f4;font:14px sans-serif;margin:24px}#chart{max-width:100%}p{color:#a6adc8}</style><p>Scroll to zoom · drag to pan · double-click to reset. Chart and data are embedded locally.</p><div id="chart"></div><script>'
        + bundle
        + "</script><script>const spec="
        + encoded
        + ';vegaEmbed("#chart",spec,{actions:{export:true,source:false,compiled:false,editor:false}}).catch(e=>{document.getElementById("chart").textContent=e.message});</script>'
    )
    if data["style"] == "heatmap":
        html = html.replace(
            "Scroll to zoom · drag to pan · double-click to reset.",
            "Hover to inspect cells.",
        )
    base.with_suffix(".html").write_text(html)
    return {
        ext: str(base.with_suffix("." + ext)) for ext in ("png", "svg", "html", "json")
    }


if __name__ == "__main__":
    try:
        result = render(json.loads(Path(sys.argv[1]).read_text()), sys.argv[2])
        print(json.dumps({"ok": True, "files": result}))
    except Exception as exc:  # noqa: BLE001 -- keep renderer failures distinct from kernel errors
        print(json.dumps({"ok": False, "error": str(exc)}))
        sys.exit(1)
