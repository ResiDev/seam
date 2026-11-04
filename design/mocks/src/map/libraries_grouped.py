"""Round thirteen: the Map's library display grouped by library.

Each library is a head; under it each name the row takes from it, the
name once, then the functions using it, the file once and the line each
first uses it on. Closed, a library is one line: its name and how many
names in how many files. Drawn from excalidraw's treesitter index on the
TTDDialog folder, open and with the pane too short, and on one function.
Writes libraries_grouped.html beside this file.
Run: python3 design/mocks/src/map/libraries_grouped.py <treesitter.json>
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

def test(p):
    return '.test.' in p or '/tests/' in p

def libraries(inside, every=False):
    """[(library, [(name, [(use, fn)])])], most used first."""
    libs = collections.defaultdict(list)
    for L in d['libs']:
        users = collections.OrderedDict()
        for u in L['uses']:
            if not inside(u):
                continue
            n = owner(u['path'], u['line'])
            k = (u['path'], u['line']) if every else n['id'] if n else u['path']
            users.setdefault(k, (u, n))
        if users:
            us = sorted(users.values(), key=lambda x: (test(x[0]['path']), x[0]['path'], x[0]['line']))
            libs[L['library']].append((L['name'], us))
    out = [(l, sorted(ns, key=lambda x: (-len(x[1]), x[0]))) for l, ns in libs.items()]
    out.sort(key=lambda g: (-sum(len(us) for _, us in g[1]), g[0]))
    return out

def span(cls, t):
    return f'<span class="{cls}">{html.escape(t)}</span>'

def name(n):
    return span('t' if n[:1].isupper() else 'f', n)

def flow(gs, centre, short, fn=False, shut=()):
    rows = []
    nw = max(len(n) for _, ns in gs for n, _ in ns) + 3
    fw = max((len(short(u['path'])) + len(str(u['line'])) + 1 for _, ns in gs for _, us in ns for u, _ in us), default=0) + 3
    for gi, (lib, ns) in enumerate(gs):
        first = gi == 0
        if not first:
            rows.append(span('l', '  │'))
        join = span('l', '  ┌─ ' if first else '  ├─ ')
        if lib in shut:
            files = {u['path'] for _, us in ns for u, _ in us}
            rows.append(join + span('d', '▸ ') + span('x', lib) + span('d', f'  {len(ns)} name{"s" if len(ns) > 1 else ""} in {len(files)} file{"s" if len(files) > 1 else ""}'))
            continue
        rows.append(join + span('x', lib))
        for n, us in ns:
            if fn:
                lines = ' '.join(span('d', ':' + str(u['line'])) for u, _ in us)
                rows.append(span('l', '  │') + '    ' + name(n) + ' ' * (nw - len(n)) + lines)
                continue
            prev = None
            for i, (u, f) in enumerate(us):
                p = short(u['path'])
                where = (span('d' if test(u['path']) else 'x', p) if p != prev else ' ' * len(p)) + span('d', ':' + str(u['line']))
                pad = ' ' * (fw - len(p) - len(str(u['line'])) - 1)
                who = span('d' if test(u['path']) else 'f', f['name'] if f else '(top level)')
                rows.append(span('l', '  │') + '    ' + (name(n) + ' ' * (nw - len(n)) if i == 0 else ' ' * nw) + where + pad + who)
                prev = p
    rows.append(span('l', '  │'))
    rows.append(span('l', '  └──▶ ') + centre)
    return '\n'.join(rows)

folder = 'packages/excalidraw/components/TTDDialog/'
G = libraries(lambda u: u['path'].startswith(folder))
short = lambda p: p[len(folder):]
F = flow(G, span('b', 'TTDDialog/'), short)
S = flow(G, span('b', 'TTDDialog/'), short, shut={l for l, ns in G[1:]})
comp = folder + 'TTDDialogInput.tsx'
cn = sorted([n for n in NODES[comp]], key=lambda n: n['line'] - n['end_line'])[0]
C = flow(libraries(lambda u: u['path'] == comp and cn['line'] <= u['line'] <= cn['end_line'], True),
         span('bf', cn['name']), lambda p: p.split('/')[-1], fn=True)

CSS = '''
:root { color-scheme: dark; }
body { background: #11121a; margin: 0; padding: 20px; }
.page { display: flex; flex-direction: column; gap: 22px; font-family: sans-serif; color: #c0caf5; }
.card h3 { margin: 0 0 4px; font-size: 14px; } .card p { margin: 0 0 8px; font-size: 12.5px; color: #9aa; max-width: 680px; }
pre { margin: 0; padding: 16px; border-radius: 8px; background: #1a1b26; color: #c0caf5; font: 12px/1.55 monospace; }
.d { color: #565f89; } .t { color: #2ac3de; } .f { color: #7dcfff; } .l { color: #545c7e; } .x { color: #c0caf5; }
.b { color: #c0caf5; font-weight: 700; } .bf { color: #7dcfff; font-weight: 700; }
'''
cards = [
    ('A folder: TTDDialog/', 'Each library a head, the most used first; under it each name taken from it, the name once, then the functions using it: the file once, the line each first uses it on, tests dim and last.', F),
    ('The same, the pane too short', 'Whole libraries close, the fewest names first: the library and how many names in how many files; l opens it.', S),
    (f'A function: {cn["name"]}', 'Each name it takes, every line it is used on; its file is the row\'s own and is not named.', C),
]
page = f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body><div class="page">' + ''.join(
    f'<div class="card"><h3>{html.escape(t)}</h3><p>{html.escape(p)}</p><pre>{b}</pre></div>' for t, p, b in cards) + '</div></body></html>'
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'libraries_grouped.html')
open(out, 'w').write(page)
print(out)
