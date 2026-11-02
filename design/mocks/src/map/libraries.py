"""Round twelve: the Map's library display.

Each name taken from a library is a head, its library after it; under it
every function using it, its file once and the line it is used on. Drawn
from excalidraw's treesitter index (format 4, `libs`), on its element/src
folder and on one component. Writes libraries.html beside this file.
Run: python3 design/mocks/src/map/libraries.py <treesitter.json>
"""
import collections, html, json, os, sys

d = json.load(open(sys.argv[1]))
NODES = collections.defaultdict(list)
for n in d['nodes']:
    NODES[n['path']].append(n)

def owner(p, l):
    best = None
    for n in NODES[p]:
        if n['line'] <= l <= n['end_line'] and (best is None or n['line'] >= best['line']):
            best = n
    return best

def groups(inside, every=False):
    out = []
    for L in d['libs']:
        users = collections.OrderedDict()
        for u in L['uses']:
            if not inside(u):
                continue
            n = owner(u['path'], u['line'])
            k = (u['path'], u['line']) if every else n['id'] if n else u['path']
            users.setdefault(k, (u, n))
        if users:
            out.append((L, list(users.values())))
    total = collections.Counter()
    for L, us in out:
        total[L['library']] += len(us)
    out.sort(key=lambda g: (-total[g[0]['library']], g[0]['library'], -len(g[1]), g[0]['name']))
    return out

def span(cls, t):
    return f'<span class="{cls}">{html.escape(t)}</span>'

def flow(gs, centre, short, names=True):
    rows = []
    for gi, (L, us) in enumerate(gs):
        first, last = gi == 0, gi == len(gs) - 1
        if not first:
            rows.append(span('l', '  │'))
        rows.append(span('l', '  ┌─ ' if first else '  ├─ ') + span('t' if L['name'][:1].isupper() else 'f', L['name']) + '  ' + span('d', L['library']))
        if not names:
            lines = ' '.join(span('d', ':' + str(u['line'])) for u, _ in sorted(us, key=lambda x: x[0]['line']))
            rows.append(span('l', '  │') + '    ' + span('x', short(us[0][0]['path'])) + '  ' + lines)
            continue
        prev = None
        wide = max(len(short(u['path'])) for u, _ in us) + 6
        for u, n in sorted(us, key=lambda x: (x[0]['path'], x[0]['line'])):
            f = short(u['path'])
            where = (span('x', f) if f != prev else ' ' * len(f)) + span('d', ':' + str(u['line']))
            pad = ' ' * (wide - len(f) - len(':' + str(u['line'])))
            who = span('f', (n and n['name']) or '(top level)') if names else ''
            rows.append(span('l', '  │') + '    ' + where + pad + who)
            prev = f
    rows.append(span('l', '  │'))
    rows.append(span('l', '  └──▶ ') + centre)
    return '\n'.join(rows)

folder = 'packages/element/src/'
F = flow(groups(lambda u: u['path'].startswith(folder)), span('b', 'element/src/'), lambda p: p[len(folder):])
comp = 'packages/excalidraw/components/LibraryMenuItems.tsx'
cn = [n for n in NODES[comp] if n['name'] == 'LibraryMenuItems'][0]
C = flow(groups(lambda u: u['path'] == comp and cn['line'] <= u['line'] <= cn['end_line'], True),
         span('b', 'LibraryMenuItems'), lambda p: p.split('/')[-1], False)

CSS = '''
:root { color-scheme: dark; }
.page { display: flex; flex-direction: column; gap: 22px; font-family: var(--font-sans, sans-serif); }
.card h3 { margin: 0 0 4px; font-size: 14px; } .card p { margin: 0 0 8px; font-size: 12.5px; color: #9aa; max-width: 680px; }
pre { margin: 0; padding: 16px; border-radius: 8px; background: #1a1b26; color: #c0caf5; font: 10.4px/1.55 monospace; }
.d { color: #565f89; } .t { color: #2ac3de; } .f { color: #7dcfff; } .l { color: #545c7e; } .x { color: #c0caf5; }
.b { color: #7aa2f7; font-weight: 700; }
'''
cards = [
    ('A folder: element/src/', 'Each name it takes from a library, the library after it, the libraries most used first; under each the functions using it, the file once, the line it is used on.', F),
    ('A function: LibraryMenuItems', 'The same on one function: each name it takes, the lines it is used on after its file, the function not named again.', C),
]
page = f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body><div class="page">' + ''.join(
    f'<div class="card"><h3>{html.escape(t)}</h3><p>{html.escape(p)}</p><pre>{b}</pre></div>' for t, p, b in cards) + '</div></body></html>'
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'libraries.html')
open(out, 'w').write(page)
print(out)
