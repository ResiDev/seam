"""Round fourteen: the foot's type at three levels, `=` going from one to the next.

As written is the declaration from its file (treesitter), as the foot is now.
Flat is the server's hover of `{ [K in keyof T]: T[K] } & {}`, type-fest's
Simplify, asked in a file never written to disk beside T's: one object, the
names it uses kept. In full is the same hover at verbosityLevel 1, every alias
spelled out; `| undefined` after a `?:` left out, the `?` says it. The text of
each is tsgo's own (7.0.0-dev.20260510), on excalidraw's ViewportOffsets and
ExcalidrawFrameElement. Writes levels.html beside this file.
Run: python3 design/mocks/src/foot/levels.py
"""
import html, os, re

W = 112
KW = {'export', 'type', 'interface', 'readonly', 'true', 'false', 'null', 'undefined'}
PRIM = {'number', 'string', 'boolean', 'void'}

def ts(s):
    """a line of TypeScript in the foot's colours"""
    out = []
    for m in re.finditer(r'"[^"]*"|[A-Za-z_$][\w$]*|\d+|\s+|.', s):
        t = m.group(0)
        e = html.escape(t)
        if t[0] == '"':
            out.append(f'<span class="s">{e}</span>')
        elif t in KW:
            out.append(f'<span class="k">{e}</span>')
        elif t in PRIM:
            out.append(f'<span class="p">{e}</span>')
        elif t[0].isupper():
            out.append(f'<span class="t">{e}</span>')
        elif t[0].isalpha() or t[0] in '_$':
            nxt = s[m.end():m.end() + 2]
            out.append(f'<span class="m">{e}</span>' if nxt[:1] in '?:' or nxt[:1] == '(' else e)
        elif t.isdigit():
            out.append(f'<span class="n">{e}</span>')
        elif t.strip():
            out.append(f'<span class="o">{e}</span>')
        else:
            out.append(e)
    return ''.join(out)

def span(c, t):
    return f'<span class="{c}">{html.escape(t)}</span>'

def levels(on):
    out = []
    for i, n in enumerate(['as written', 'flat', 'in full']):
        out.append(span('b' if n == on else 'd', n))
    return '  '.join(out)

def head(name, where, on):
    left = ' ' + span('tb', name) + span('d', '   ' + where)
    plain = len(' ' + name + '   ' + where)
    right = levels(on)
    rlen = len('as written  flat  in full')
    return left + ' ' * (W - plain - rlen - 1) + right

def foot(name, where, on, lines, more=None):
    rows = [span('l', ' ' + '─' * (W - 2)), '', head(name, where, on)]
    rows += [' ' + ts(l) for l in lines]
    if more:
        rows.append(span('d', f' ⋯ {more} more lines'))
    rows.append('')
    return rows

def status(nxt):
    right = span('k2', '=') + ' ' + span('d', nxt) + '  │  ' + span('k2', '+') + ' ' + span('d', 'open type') + '  │  ' + span('k2', '<Tab>') + ' ' + span('d', 'view') + '  │  ' + span('k2', '<Esc>') + ' ' + span('d', 'tree')
    plain = len(f'= {nxt}  │  + open type  │  <Tab> view  │  <Esc> tree')
    left = ' ' + span('mode', ' NORMAL ') + ' ViewportOffsets  types'
    return left + ' ' * (W - len(' NORMAL  ViewportOffsets  types') - plain - 2) + right

WHERE = 'type in excalidraw/types.ts:1658   made by 0, taken by 0'
WRITTEN = [
    'export type ViewportOffsets = Offsets & {',
    '  ui?: true | ViewportOffsetsOptions;',
    '};',
]
FLAT = [
    'type ViewportOffsets = {',
    '  top?: number;',
    '  right?: number;',
    '  bottom?: number;',
    '  left?: number;',
    '  ui?: true | ViewportOffsetsOptions;',
    '}',
]
FULL = [
    'type ViewportOffsets = {',
    '  top?: number;',
    '  right?: number;',
    '  bottom?: number;',
    '  left?: number;',
    '  ui?: true | {',
    '    padding?: number;',
    '    paddingTop?: number;',
    '    paddingRight?: number;',
    '    paddingBottom?: number;',
    '    paddingLeft?: number;',
    '    top?: number;',
    '    bottom?: number;',
    '    left?: number;',
    '    right?: number;',
    '    reserve?: {',
    '      stylesPanel?: boolean;',
    '      sidebar?: boolean;',
    '    };',
    '  };',
    '}',
]
FRAME_WHERE = 'type in element/src/types.ts:178   made by 12, taken by 2'
FRAME_FLAT = [
    'type ExcalidrawFrameElement = {',
    *['  readonly ' + f for f in [
        'id: string;', 'x: number;', 'y: number;', 'strokeColor: string;', 'backgroundColor: string;',
        'fillStyle: FillStyle;', 'strokeWidth: number;', 'strokeStyle: StrokeStyle;']],
    '  readonly roundness: null | {',
    '    type: RoundnessType;',
    '    value?: number;',
    '  };',
    *['  readonly ' + f for f in [
        'roughness: number;', 'opacity: number;', 'width: number;', 'height: number;', 'angle: Radians;',
        'seed: number;', 'version: number;', 'versionNonce: number;', 'index: FractionalIndex | null;',
        'isDeleted: boolean;', 'groupIds: readonly GroupId[];', 'frameId: string | null;',
        'boundElements: readonly BoundElement[] | null;', 'updated: number;', 'created: number | null;',
        'link: string | null;', 'locked: boolean;', 'customData?: Record<string, any>;']],
    '  type: "frame";',
    '  name: string | null;',
    '}',
]
SHOWN = 17

def screen(rows):
    return '<pre>' + '\n'.join(rows) + '</pre>'

cards = [
    ('As written, the foot today, = once to flat',
     'The pane\'s cursor on ViewportOffsets. The declaration from its file: an intersection, so what a ViewportOffsets holds is half in Offsets.',
     foot('ViewportOffsets', WHERE, 'as written', WRITTEN) + [status('flat')]),
    ('Flat, = again to in full',
     'One object, every field it has, the names it uses kept: ViewportOffsetsOptions stays a name (the server, Simplify on it).',
     foot('ViewportOffsets', WHERE, 'flat', FLAT) + [status('in full')]),
    ('In full, = again back to as written',
     'Every alias spelled out, ViewportOffsetsOptions\'s fields in place; the server at verbosity 1.',
     foot('ViewportOffsets', WHERE, 'in full', FULL) + [status('as written')]),
    ('Flat on a big one: cut where the foot ends',
     'ExcalidrawFrameElement is _ExcalidrawElementBase & { type: "frame"; name: string | null }; flat, its 32 fields, as long as the foot holds, then how many lines are left.',
     foot('ExcalidrawFrameElement', FRAME_WHERE, 'flat', FRAME_FLAT[:SHOWN], more=len(FRAME_FLAT) - SHOWN)),
]

CSS = '''
:root { color-scheme: dark; }
body { background: #11121a; margin: 0; padding: 20px; }
.page { display: flex; flex-direction: column; gap: 22px; font-family: sans-serif; color: #c0caf5; }
.card h3 { margin: 0 0 4px; font-size: 14px; } .card p { margin: 0 0 8px; font-size: 12.5px; color: #9aa; max-width: 760px; }
pre { margin: 0; padding: 16px; border-radius: 8px; background: #1a1b26; color: #c0caf5; font: 12px/1.55 monospace; width: max-content; }
.d { color: #565f89; } .l { color: #3b4261; } .b { color: #c0caf5; font-weight: 700; }
.t { color: #2ac3de; } .tb { color: #2ac3de; font-weight: 700; } .f { color: #7dcfff; }
.k { color: #bb9af7; } .p { color: #2ac3de; } .s { color: #9ece6a; } .n { color: #ff9e64; } .o { color: #89ddff; } .m { color: #73daca; }
.k2 { color: #7aa2f7; font-weight: 700; } .mode { background: #7aa2f7; color: #1a1b26; font-weight: 700; }
'''
body = ''.join(f'<div class="card"><h3>{html.escape(h)}</h3><p>{html.escape(p)}</p>{screen(r)}</div>' for h, p, r in cards)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'levels.html')
open(out, 'w').write(f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body><div class="page">{body}</div></body></html>')
print(out)
