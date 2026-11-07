"""Round fifteen: the tree's rows by kind, functions, types and values, each on or off.

A file's rows are what it declares at its top, in the file's order: its
functions as now, `name()`; its types, `TransformHandles`, in the code's
type colour; its values, `DEFAULT_OMIT_SIDES`, plain. `f` `t` `v` turn
functions, types and values on or off; functions alone by default, the tree
as it is now. The status line's left says which are on when it is not
functions alone. A value opens with `l` to what it calls, as a function
does: excalidraw's actions are values, `register({ perform, PanelComponent })`.
Names from excalidraw's packages/element/src/transformHandles.ts and
packages/excalidraw/actions/actionProperties.tsx as written.
Run: python3 design/mocks/src/treekinds/kinds.py  (writes kinds.html beside it)
"""
import html, os

W = 58


def sp(c, t):
    return f'<span class="{c}">{html.escape(t)}</span>'


def row(depth, segs, sel=False, sign=' '):
    body = sp('c', sign) + ' ' + '  ' * depth + ''.join(sp(c, t) for c, t in segs)
    vis = len(sign) + 1 + 2 * depth + sum(len(t) for _, t in segs)
    pad = ' ' * max(0, W - vis)
    return f'<span class="sel">{body}{pad}</span>' if sel else body + pad


def fn(n):
    return [('fg', n), ('c', '()')]


def ty(n):
    return [('cy', n)]


def val(n):
    return [('fg', n)]


def folder(n):
    return [('b', n)]


def status(left, keys):
    k = '  '.join(sp('b bold', a) + ' ' + sp('c', b) for a, b in keys)
    vis = len(left) + 2 + sum(len(a) + 1 + len(b) + 2 for a, b in keys) - 2
    return sp('sl', ' ' + left + ' ' * max(1, W - vis - 1)) + f'<span class="sl">{k}</span>'


HEAD = [row(0, folder('packages/')), row(1, folder('element/src/'))]


def screen(rows, left, keys, note):
    lines = [sp('c', ' Seams   ') + sp('fg bold', 'by folder'), sp('d3', '─' * W)] + rows
    lines += [' ' * W] * (24 - len(lines))
    lines.append(status(left, keys))
    return f'<div class="shot"><pre class="nv">{chr(10).join(lines)}</pre><p class="cap">{note}</p></div>'


TH = 'transformHandles.ts'
A = HEAD + [
    row(2, [('fg', TH)]),
    row(3, fn('generateTransformHandle')),
    row(3, fn('canResizeFromSides')),
    row(3, fn('getOmitSidesForEditorInterface'), sel=True),
    row(3, fn('getTransformHandlesFromCoords')),
    row(3, fn('getTransformHandles')),
    row(3, fn('hasBoundingBox')),
    row(2, [('fg', 'typeChecks.ts')]),
    row(2, [('fg', 'types.ts')]),
]

B = HEAD + [
    row(2, [('fg', TH)]),
    row(3, ty('TransformHandleDirection')),
    row(3, ty('TransformHandleType')),
    row(3, ty('TransformHandle')),
    row(3, ty('TransformHandles'), sel=True),
    row(3, ty('MaybeTransformHandleType')),
    row(3, val('transformHandleSizes')),
    row(3, val('ROTATION_RESIZE_HANDLE_GAP')),
    row(3, val('DEFAULT_OMIT_SIDES')),
    row(3, val('OMIT_SIDES_FOR_MULTIPLE_ELEMENTS')),
    row(3, val('OMIT_SIDES_FOR_FRAME')),
    row(3, val('OMIT_SIDES_FOR_LINE_SLASH')),
    row(3, val('OMIT_SIDES_FOR_LINE_BACKSLASH')),
    row(3, fn('generateTransformHandle')),
    row(3, fn('canResizeFromSides')),
    row(3, fn('getOmitSidesForEditorInterface')),
    row(3, fn('getTransformHandlesFromCoords')),
    row(3, fn('getTransformHandles')),
    row(3, fn('hasBoundingBox')),
    row(2, [('fg', 'typeChecks.ts')]),
]

C = [
    row(0, folder('packages/')),
    row(1, folder('excalidraw/actions/')),
    row(2, [('fg', 'actionProperties.tsx')]),
    row(3, val('FONT_SIZE_RELATIVE_INCREASE_STEP')),
    row(3, fn('getStylesPanelInfo')),
    row(3, fn('changeProperty')),
    row(3, fn('getFormValue')),
    row(3, fn('offsetElementAfterFontResize')),
    row(3, fn('changeFontSize')),
    row(3, val('actionChangeStrokeColor'), sel=True),
    row(4, [('fg ul', 'register'), ('c', '()')]),
    row(4, [('fg', 'changeProperty'), ('c', '()')]),
    row(4, [('fg ul', 'newElementWith'), ('c', '()')]),
    row(4, [('fg ul', 'isTextElement'), ('c', '()')]),
    row(4, [('fg ul', 'getShortcutKey'), ('c', '()')]),
    row(4, [('fg ul', 'ColorPicker')]),
    row(3, val('actionChangeBackgroundColor')),
    row(3, val('actionChangeBucketFillBackgroundColor')),
    row(3, val('actionChangeFillStyle')),
    row(3, fn('getStrokeWidthKeyForElement')),
]

KEYS = [('l', 'open'), ('h', 'close'), ('J', 'code')]
shots = [
    screen(A, 'getOmitSidesForEditorInterface()', KEYS,
           '<b>A.</b> As now: functions alone, the default. Nothing says so.'),
    screen(B, 'types · values   TransformHandles  types', [('h', 'close')],
           "<b>B.</b> <kbd>t</kbd> <kbd>v</kbd>: every declaration at the file's top, in the file's order. "
           'Types in the type colour, values plain, functions with their <code>()</code>. A type does not open.'),
    screen(C, 'values   actionChangeStrokeColor  map', KEYS,
           '<b>C.</b> <kbd>v</kbd> on actionProperties.tsx: each action is a value, <code>register({ … })</code>, '
           'and opens with <kbd>l</kbd> to what it calls, as a function does. Its Code, Types and Map in the pane as a function\'s.'),
]
here = os.path.dirname(os.path.abspath(__file__))
css = open(os.path.join(here, '..', 'base.css')).read()
page = f'''<!doctype html><html><head><meta charset="utf-8"><style>
:root {{ --foreground:#c0caf5; --muted-foreground:#787c99; --border:#3b4261; --secondary:#24283b; --radius:8px; --font-sans: system-ui, sans-serif; --font-mono: monospace; }}
body {{ background:#16161e; margin:0; padding:20px; }}
{css}
.row {{ display:flex; gap:18px; align-items:flex-start; }}
.shot {{ width: 470px; }}
.nv {{ font-size: 12.5px; }}
code {{ color:#c0caf5; }}
</style></head><body class="mock"><h2>The tree by kind: <kbd>f</kbd> functions, <kbd>t</kbd> types, <kbd>v</kbd> values</h2>
<p class="lede">Round fifteen. excalidraw, packages/element/src/transformHandles.ts and packages/excalidraw/actions/actionProperties.tsx.</p>
<div class="row">{"".join(shots)}</div></body></html>'''
open(os.path.join(here, 'kinds.html'), 'w').write(page)
print('ok')
