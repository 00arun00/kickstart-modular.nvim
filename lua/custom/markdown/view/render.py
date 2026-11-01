"""Render a Markdown snapshot into image tiles and source-position anchors.

Pandoc owns Markdown parsing and Typst owns layout. This worker only resolves
local images, isolates bad assets, and adapts the output to terminal cells.
"""

import json
import math
import os
import plistlib
import re
import signal
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import unquote, urlsplit

from PIL import Image

ROOT = Path(__file__).resolve().parent
MAX_PIXELS = 80_000_000
IMAGE_SUFFIXES = {'.svg', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.avif', '.bmp', '.tif', '.tiff'}
child = None


def write_palette(outdir, supplied):
    """Write immutable generation-local color inputs, including code syntax."""
    colors = dict(background='#ffffff', foreground='#35394a', muted='#687185',
                  heading='#346b70', link='#397b85', math='#35394a',
                  panel='#f3f5f7', header='#edf3f3', border='#d8dde2',
                  code='#35394a', figure_background='#ffffff')
    syntax = dict(comment='#687185', keyword='#9357a2', string='#467536',
                  function='#246b93', type='#8c6827', constant='#a45b31',
                  operator='#397b85', punctuation='#35394a', tag='#a5454a')
    supplied = supplied if isinstance(supplied, dict) else {}
    for role in colors:
        value = supplied.get(role)
        if isinstance(value, str) and re.fullmatch(r'#[0-9a-fA-F]{6}', value):
            colors[role] = value.lower()
    for role in syntax:
        value = supplied.get('syntax', {}).get(role) if isinstance(supplied.get('syntax'), dict) else None
        if isinstance(value, str) and re.fullmatch(r'#[0-9a-fA-F]{6}', value):
            syntax[role] = value.lower()
    colors['syntax'] = syntax
    (outdir / 'palette.json').write_text(json.dumps(colors), encoding='utf-8')
    scopes = dict(comment='comment', keyword='keyword, storage', string='string',
                  function='entity.name.function, support.function',
                  type='entity.name.type, support.type, support.class',
                  constant='constant', operator='keyword.operator',
                  punctuation='punctuation', tag='entity.name.tag')
    settings = [{'settings': {'foreground': colors['code'], 'background': colors['panel']}}]
    settings.extend({'scope': scopes[role], 'settings': {'foreground': value}} for role, value in syntax.items())
    (outdir / 'code.tmTheme').write_bytes(plistlib.dumps({'name': 'Neovim', 'settings': settings}))
    return colors


class CommandError(RuntimeError):
    def __init__(self, message, returncode):
        super().__init__(message)
        self.returncode = returncode


def terminate_child():
    """Stop the entire compiler process group, including orphaned descendants."""
    global child
    process = child
    if process is None:
        return
    try:
        if os.name == 'posix':
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        else:
            process.terminate()
        try:
            process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass
        if os.name == 'posix':
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        elif process.poll() is None:
            process.kill()
        process.communicate(timeout=1)
    finally:
        child = None


def stop(signum, _frame):
    terminate_child()
    raise SystemExit(128 + signum)


def run(args, *, cwd, env=None, timeout=18, warnings=None):
    global child
    child = subprocess.Popen(
        [str(arg) for arg in args], cwd=cwd, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        start_new_session=os.name == 'posix',
    )
    try:
        try:
            out, err = child.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            terminate_child()
            raise TimeoutError(f'Render command timed out after {timeout} seconds') from None
        code = child.returncode
        if code:
            raise CommandError(err.strip() or out.strip() or f'Command exited {code}', code)
        if warnings is not None and err.strip():
            warnings.append(err.strip())
        return out
    finally:
        # Successful compilers should not leave background descendants behind.
        terminate_child()


def attr(node):
    return dict(node.get('c', [[None, None, []]])[0][2])


def plain(node):
    if isinstance(node, list):
        return ''.join(plain(value) for value in node)
    if not isinstance(node, dict):
        return ''
    if node.get('t') == 'Str':
        return node['c']
    if node.get('t') in ('Space', 'SoftBreak', 'LineBreak'):
        return ' '
    if node.get('t') in ('Span', 'Link', 'Image'):
        return plain(node['c'][1])
    return plain(node.get('c', []))


def fallback(label, reason):
    return {'t': 'Span', 'c': [
        ['', ['rich-image-fallback'], []],
        [{'t': 'Str', 'c': f'[Image unavailable: {label[:160]} ({reason})]'}],
    ]}


def heading_ids(value):
    if isinstance(value, dict):
        if value.get('t') == 'Header':
            return {value['c'][1][0]}
        return heading_ids(value.get('c', []))
    if isinstance(value, list):
        return set().union(*(heading_ids(item) for item in value))
    return set()


class Assets:
    def __init__(self, origin, warnings, anchors=None):
        self.origin = origin
        self.warnings = warnings
        self.anchors = anchors or set()
        self.vault = next((p for p in origin.parents if (p / '.obsidian').is_dir()), None)
        self.index = None
        self.images = {}

    def warn(self, message):
        if message not in self.warnings:
            self.warnings.append(message)

    def resolve(self, source, wiki):
        parts = urlsplit(source)
        if parts.scheme and parts.scheme != 'file':
            return None, 'remote images are not loaded'
        if parts.netloc and parts.netloc != 'localhost':
            return None, 'remote images are not loaded'
        target = Path(unquote(parts.path))
        if target.suffix.lower() not in IMAGE_SUFFIXES:
            return None, 'unsupported image or note embed'
        candidates = [target] if target.is_absolute() else [self.origin.parent / target]
        if self.vault and not target.is_absolute():
            candidates.append(self.vault / target)
        for candidate in candidates:
            if candidate.is_file():
                return candidate.resolve(), None
        if wiki and self.vault:
            if self.index is None:
                self.index = {}
                for directory, dirs, files in os.walk(self.vault):
                    dirs[:] = [d for d in dirs if d not in {'.obsidian', '.git', 'node_modules', '.trash'}]
                    for name in files:
                        if Path(name).suffix.lower() in IMAGE_SUFFIXES:
                            self.index.setdefault(name, []).append(Path(directory) / name)
            matches = self.index.get(target.name, [])
            if len(target.parts) > 1:
                matches = [p for p in matches if p.as_posix().endswith('/' + target.as_posix())]
            if len(matches) == 1:
                return matches[0].resolve(), None
            if len(matches) > 1:
                return None, 'ambiguous attachment name'
        return None, 'file not found'

    def image(self, node, wiki=False):
        source = node['c'][2][0]
        label = plain(node['c'][1]) or source
        path, error = self.resolve(source, wiki)
        if error:
            self.warn(f'Image unavailable: {source} ({error})')
            return fallback(label, error)
        node['c'][2][0] = str(path)
        # Preserve explicit sizes and otherwise let Typst fit the intrinsic
        # image size to its containing column. Forcing 100% enlarged compact
        # raster figures and made their scale depend on the pane width.
        self.images.setdefault(path, []).append((node, label))
        return node

    def walk(self, value):
        if isinstance(value, dict):
            if value.get('t') == 'Image':
                return self.image(value)
            if value.get('t') == 'Link' and 'wikilink' in value['c'][0][1]:
                # The image canvas has no link interaction. Render vault link
                # labels without inventing Typst labels for external notes or
                # Obsidian heading anchors (which need not exist in this file).
                return {'t': 'Span', 'c': [value['c'][0], self.walk(value['c'][1])]}
            if value.get('t') == 'Link' and value['c'][2][0].startswith('#'):
                target = value['c'][2][0]
                if unquote(target[1:]) not in self.anchors:
                    self.warn(f'Unresolved local heading link displayed as text: {target}')
                    return {'t': 'Span', 'c': [value['c'][0], self.walk(value['c'][1])]}
            if value.get('t') == 'CodeBlock' and 'mermaid' in value['c'][0][1]:
                self.warn('Mermaid diagrams are displayed as code in the rich view.')
            if value.get('t') == 'BlockQuote' and plain(value['c']).lstrip().startswith('[!'):
                self.warn('Obsidian callouts are displayed as ordinary quotes in the rich view.')
            if value.get('t') in ('RawBlock', 'RawInline') and value['c'][0] == 'html':
                self.warn('Raw HTML is not rendered in the rich view.')
            if 'c' in value:
                value['c'] = self.walk(value['c'])
            return value
        if not isinstance(value, list):
            return value
        result = []
        index = 0
        while index < len(value):
            current = value[index]
            following = value[index + 1] if index + 1 < len(value) else None
            # Pandoc parses ![[target]] as an adjacent ! span and a wikilink.
            # A one-character source span excludes an escaped \! marker.
            pos = attr(current).get('data-pos', '') if isinstance(current, dict) and current.get('t') == 'Span' else ''
            match = re.fullmatch(r'(?:.*@)?(\d+):(\d+)-(\d+):(\d+)', pos)
            bang = match and match[1] == match[3] and int(match[4]) - int(match[2]) == 1 and plain(current) == '!'
            if bang and isinstance(following, dict) and following.get('t') == 'Link' and 'wikilink' in following['c'][0][1]:
                image = {'t': 'Image', 'c': following['c']}
                result.append(self.image(image, wiki=True))
                index += 2
                continue
            result.append(self.walk(current))
            index += 1
        return result

    def validate(self, typst, outdir):
        """Let the actual typesetter validate assets before rendering the note.

        A batch probe is cheap for healthy documents. Compiler locations identify
        failed images, which are replaced locally before retrying the probe.
        """
        probe = outdir / 'assets.typ'

        def reject(path):
            self.warn(f'Image unavailable: {path.name} (could not decode image)')
            for node, label in self.images[path]:
                node.clear()
                node.update(fallback(label, 'could not decode image'))

        def check(pending):
            if not pending:
                return
            probe.write_text('#set page(width: 10pt, height: auto, margin: 0pt)\n' + '\n'.join(
                '#image(' + json.dumps(str(path), ensure_ascii=False) + ', width: 1pt, height: 1pt)'
                for path in pending
            ), encoding='utf-8')
            try:
                run([typst, 'compile', '--root', '/', probe, outdir / 'assets.pdf'], cwd=outdir)
            except CommandError as exc:
                # A killed compiler or an output/global failure is not proof
                # that the assets are corrupt. Keep it as a document error.
                if exc.returncode != 1:
                    raise
                failed = {int(line) - 2 for line in re.findall(r'assets\.typ:(\d+):\d+', str(exc))}
                failed = {i for i in failed if 0 <= i < len(pending)}
                # SVG errors can point into the asset instead of the probe.
                locations = re.findall(r'┌─ ([^\n]+):\d+:\d+', str(exc))
                paths = {(outdir / location).resolve() for location in locations}
                failed.update(i for i, path in enumerate(pending) if path in paths)
                if not failed:
                    raise
                for index in sorted(failed):
                    reject(pending[index])
                check([path for i, path in enumerate(pending) if i not in failed])

        check(list(self.images))
        for path in (probe, outdir / 'assets.pdf'):
            path.unlink(missing_ok=True)


def render(request):
    warnings = []
    outdir = Path(request['output']).resolve()
    outdir.mkdir(parents=True, exist_ok=True)
    palette = write_palette(outdir, request.get('palette'))
    origin = Path(request['origin']).resolve()
    cwd = origin.parent if origin.parent.is_dir() else outdir
    pandoc, typst = request.get('pandoc', 'pandoc'), request.get('typst', 'typst')
    snapshot = outdir / 'source.md'
    snapshot.write_text(request['text'], encoding='utf-8')
    ast = json.loads(run([
        pandoc, snapshot, '--from', 'commonmark_x+sourcepos+wikilinks_title_after_pipe', '--to', 'json',
    ], cwd=cwd, warnings=warnings))
    assets = Assets(origin, warnings, heading_ids(ast['blocks']))
    ast['blocks'] = assets.walk(ast['blocks'])
    assets.validate(typst, outdir)
    (outdir / 'source.json').write_text(json.dumps(ast, ensure_ascii=False), encoding='utf-8')
    run([
        pandoc, outdir / 'source.json', '--from', 'json', '--to', 'typst',
        '--syntax-highlighting=idiomatic', '--lua-filter', ROOT / 'source-map.lua',
        '--output', outdir / 'content.typ',
    ], cwd=cwd, warnings=warnings)
    cols = int(request['columns'])
    cw, ch = float(request['cell_width']), float(request['cell_height'])
    if not 20 <= cols <= 180 or not 0 < cw <= 100 or not 0 < ch <= 200:
        raise ValueError('Invalid terminal cell geometry')
    pixel_width = max(80, round(cols * cw))
    paged = request['mode'] == 'paged'
    ppt = pixel_width / 595 if paged else ch / 14
    page_width = 595 if paged else pixel_width / ppt
    height, margin = ('842pt', 36) if paged else ('auto', 24)
    document = f'#set page(width: {page_width:.6f}pt, height: {height}, margin: {margin}pt'
    document += (', numbering: "1"' if paged else '') + ')\n'
    document += (ROOT / 'style.typ').read_text(encoding='utf-8') + '\n#include "content.typ"\n#include "map.typ"\n'
    (outdir / 'document.typ').write_text(document, encoding='utf-8')
    (outdir / 'map.typ').write_text((ROOT / 'map.typ').read_text(encoding='utf-8'), encoding='utf-8')
    run([typst, 'compile', '--root', '/', '--format', 'png', '--ppi', str(ppt * 72), outdir / 'document.typ', outdir / 'page-{p}.png'], cwd=outdir, warnings=warnings)
    mapping = json.loads(run([
        typst, 'eval', 'query(<md-map>).map(it => it.value)', '--root', '/', '--in', outdir / 'document.typ',
    ], cwd=outdir, warnings=warnings))[0]
    tiles, pages = [], {}
    canvas_rows, pixels = 0, 0
    paths = sorted(outdir.glob('page-*.png'), key=lambda p: int(re.search(r'page-(\d+)', p.name)[1]))
    for path in paths:
        page = int(re.search(r'page-(\d+)', path.name)[1])
        with Image.open(path) as source:
            pixels += source.width * source.height
            if pixels > MAX_PIXELS:
                raise ValueError('Rendered note exceeds the image-size limit; try a narrower view or a smaller note')
            image = source.convert('RGB')
            rows = math.ceil(image.height / ch)
            normalized = Image.new('RGB', (pixel_width, rows * round(ch)), palette['background'])
            normalized.paste(image, (0, 0))
            pages[page] = {'start': canvas_rows, 'rows': rows, 'width': image.width, 'height': image.height}
            for start in range(0, rows, 120):
                count = min(120, rows - start)
                file = outdir / f'tile-{page}-{start}.png'
                normalized.crop((0, start * round(ch), pixel_width, (start + count) * round(ch))).save(file)
                tiles.append({'file': str(file), 'start': canvas_rows + start, 'rows': count, 'columns': cols})
            canvas_rows += rows + (2 if paged else 0)
        path.unlink()
    points = []
    for point in mapping:
        match = re.search(r'@(\d+):(\d+)-(\d+):(\d+)$', point['source'])
        if match and point['page'] in pages:
            row = pages[point['page']]['start'] + int(point['y'] * ppt / ch) + 1
            points.append({'source': int(match[1]), 'col': int(match[2]) - 1, 'end_source': int(match[3]), 'row': min(canvas_rows, max(1, row))})
    if not points:
        points = [{'source': 1, 'col': 0, 'end_source': 1, 'row': 1}]
    result = dict(tiles=tiles, points=points, rows=canvas_rows, columns=cols, mode=request['mode'],
                  source_lines=request['text'].count('\n') + 1, pages=len(paths), pixel_width=pixel_width,
                  palette=palette, warnings=list(dict.fromkeys(warnings)))
    (outdir / 'manifest.json').write_text(json.dumps(result), encoding='utf-8')
    return result


def main():
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        started = time.monotonic()
        result = render(json.loads(Path(sys.argv[1]).read_text(encoding='utf-8')))
        result['render_ms'] = round((time.monotonic() - started) * 1000)
        print(json.dumps(result))
        return 0
    except Exception as exc:
        print(json.dumps({'error': str(exc)}))
        return 1
    finally:
        terminate_child()


if __name__ == '__main__':
    sys.exit(main())
