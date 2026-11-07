"""Round fifteen, b: `e`, a file's exports only, with whichever kinds are on.

transformHandles.ts with `t` `v` on, then `e`: what it keeps to itself goes
(transformHandleSizes, ROTATION_RESIZE_HANDLE_GAP, the two OMIT_SIDES_FOR_LINE_*
and generateTransformHandle()), the rest stays in the file's order.
Run: python3 design/mocks/src/treekinds/exports.py  (writes exports.html beside it)
"""
import os
import kinds
from kinds import row, fn, ty, val, screen, HEAD, TH

ALL = HEAD + [row(2, [('fg', TH)])] + [
    row(3, x) for x in [
        ty('TransformHandleDirection'), ty('TransformHandleType'), ty('TransformHandle'), ty('TransformHandles'),
        ty('MaybeTransformHandleType'), val('transformHandleSizes'), val('ROTATION_RESIZE_HANDLE_GAP'),
        val('DEFAULT_OMIT_SIDES'), val('OMIT_SIDES_FOR_MULTIPLE_ELEMENTS'), val('OMIT_SIDES_FOR_FRAME'),
        val('OMIT_SIDES_FOR_LINE_SLASH'), val('OMIT_SIDES_FOR_LINE_BACKSLASH'), fn('generateTransformHandle'),
        fn('canResizeFromSides'), fn('getOmitSidesForEditorInterface'), fn('getTransformHandlesFromCoords'),
        fn('getTransformHandles'), fn('hasBoundingBox'),
    ]
] + [row(2, [('fg', 'typeChecks.ts')])]

E = HEAD + [row(2, [('fg', TH)])] + [
    row(3, x, sel=(i == 3)) for i, x in enumerate([
        ty('TransformHandleDirection'), ty('TransformHandleType'), ty('TransformHandle'), ty('TransformHandles'),
        ty('MaybeTransformHandleType'), val('DEFAULT_OMIT_SIDES'), val('OMIT_SIDES_FOR_MULTIPLE_ELEMENTS'),
        val('OMIT_SIDES_FOR_FRAME'), fn('canResizeFromSides'), fn('getOmitSidesForEditorInterface'),
        fn('getTransformHandlesFromCoords'), fn('getTransformHandles'), fn('hasBoundingBox'),
    ])
] + [row(2, [('fg', 'typeChecks.ts')]), row(2, [('fg', 'types.ts')])]

F = HEAD + [row(2, [('fg', TH)])] + [
    row(3, fn(n), sel=(n == 'getOmitSidesForEditorInterface')) for n in [
        'canResizeFromSides', 'getOmitSidesForEditorInterface', 'getTransformHandlesFromCoords',
        'getTransformHandles', 'hasBoundingBox']
] + [row(2, [('fg', 'typeChecks.ts')]), row(2, [('fg', 'types.ts')])]

shots = [
    screen(ALL, 'functions · types · values   TransformHandles', [('h', 'close')],
           '<b>A.</b> <kbd>t</kbd> <kbd>v</kbd>, as round fifteen: everything the file declares at its top.'),
    screen(E, 'functions · types · values · exports only   TransformHandles', [('h', 'close')],
           "<b>B.</b> <kbd>e</kbd>: its exports alone. What it keeps to itself goes: five of eighteen. "
           'Another <kbd>e</kbd> brings them back.'),
    screen(F, 'functions · exports only   getOmitSidesForEditorInterface()', [('l', 'open'), ('J', 'code')],
           "<b>C.</b> <kbd>e</kbd> with functions alone: the file's exported functions. A function's calls, opened "
           'with <kbd>l</kbd>, are all of them, exported or not.'),
]
here = os.path.dirname(os.path.abspath(__file__))
page = open(os.path.join(here, 'kinds.html')).read()
head = page[:page.index('<body')]
open(os.path.join(here, 'exports.html'), 'w').write(
    head + '<body class="mock"><h2>The tree by kind, b: <kbd>e</kbd> exports only</h2>'
    '<p class="lede">Round fifteen, b. excalidraw, packages/element/src/transformHandles.ts.</p>'
    f'<div class="row">{"".join(shots)}</div></body></html>')
print('ok')
