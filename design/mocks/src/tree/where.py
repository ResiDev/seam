# Where a call lives, marked the same way in the tree and in the code beside it.
# Six marks, each on two screens: update() in core (calls in its own file and
# in other files) and useOwnedRun() in react (a call into core, and react's own hooks).
#   python3 where.py <treesitter.json> <raf core src> <a raf react src>  -> /tmp/seam-tree/v6/where-*.html
import sys, os, json, re
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose, width
lib.W = W = 178
lib.SHOT_CSS += (" .nv .dot{text-decoration:underline dotted;text-underline-offset:3px}"
                 " .nv .ulcor{text-decoration:underline;text-decoration-color:#7dcfff;text-underline-offset:2px;text-decoration-thickness:2px}"
                 " .nv .bf{font-weight:700}")
TSX = json.load(open(sys.argv[1]))
N = {n["id"]: n for n in TSX["nodes"]}
CORE_SRC, REACT_SRC = sys.argv[2], sys.argv[3]
LW = 46
RW = W - LW - 1

def kids(i):
    out = []
    for c, _, _ in sorted(N[i]["calls"], key=lambda t: t[1]):
        if c in N and c not in out: out.append(c)
    return out
UPD = next(i for i, n in N.items() if n["name"] == "update" and n["path"].endswith("run/update.ts"))
HOME = N[UPD]["path"]
WHERE = {}   # name -> ("file", path) or ("other", path) or ("pkg", package)
for k in kids(UPD):
    rel = N[k]["path"].replace("packages/core/src/", "")
    if rel.startswith("run/"): rel = rel[4:]
    WHERE[N[k]["name"]] = ("file", "") if N[k]["path"] == HOME else ("other", rel)
WHERE["createRun"] = ("pkg", "waymark-core")

# ── how each variant marks a name, as segments ──────────────────────────
def mark(v, name, base, ctx):
    """base: the class the name has already; ctx 'tree' or 'code'"""
    kind, where = WHERE.get(name, (None, ""))
    if kind is None: return s(base, name)
    if v == "underline":
        if kind == "other": return s(base + " ul", name)
        if kind == "pkg": return (lib.bar("core") if ctx == "tree" else []) + s(base + " ulcor", name)
    if v == "dotted":
        if kind == "other": return s(base + " dot", name)
        if kind == "pkg": return s(base + " ulcor", name)
    if v == "italic":
        if kind == "other": return s(base + " it", name)
        if kind == "pkg": return s("hcor it", name)
    if v == "bold-here":
        if kind == "file": return s(base + " bf", name)
        if kind == "pkg": return s("hcor", name)
    if v == "glyph":
        if kind == "other": return s(base, name) + s("c", "↗")
        if kind == "pkg": return s(base, name) + s("hcor", "↗")
    if v == "file":
        return s(base, name)
    return s(base, name)

def eol(v, names):
    """the file variant: where the names on a line come from, dim, after it"""
    if v != "file": return []
    wh = []
    for n in names:
        k, w = WHERE.get(n, (None, ""))
        if k in ("other", "pkg") and w not in wh: wh.append(w)
    return (s("", "   ") + s("d3", "← " + ", ".join(wh))) if wh else []

def code_rows(v, path, a, b):
    src = open(path).read().split("\n")
    rows = []
    for n in range(a, b + 1):
        line = src[n - 1]
        segs = ts(line)
        out, found = [], []
        for j, (c, t) in enumerate(segs):
            prv = segs[j - 1][1] if j else ""
            if t in WHERE and not prv.endswith(".") and not c.startswith("g"):
                out += mark(v, t, c, "code"); found.append(t)
            else:
                out.append((c, t))
        rows.append((s("c", str(n).rjust(5)) + s("", "  ") + out + eol(v, found), ""))
    return rows

def tree_rows(v, cursor):
    R = [(0, s("fg", "packages/")), (1, s("hcor", "core/src/")), (2, s("fg", "▸ checklists/")), (2, s("fg", "run/")),
         (3, s("fg", "▸ page.ts")), (3, s("fg", "▸ run.ts")), (3, s("fg", "update.ts")), (4, s("b", "update") + s("pun", "()"), "update")]
    for k in kids(UPD):
        R.append((5, mark(v, N[k]["name"], "b", "tree") + s("pun", "()"), N[k]["name"]))
    R += [(3, s("fg", "▸ walkthroughs.ts")), (2, s("fg", "▸ storage/")), (1, s("hre", "react/src/")), (2, s("fg", "useRun.ts")),
          (3, s("b", "useOwnedRun") + s("pun", "()"), "useOwnedRun"), (4, mark(v, "createRun", "b", "tree") + s("pun", "()"), "createRun"),
          (2, s("fg", "▸ Walkthrough.tsx"))]
    out = [blank()[0]]
    for r in R:
        d, segs = r[0], r[1]
        row = s("", "  " + "  " * d) + segs
        nm = r[2] if len(r) > 2 else None
        if v == "file" and nm in WHERE and WHERE[nm][0] in ("other", "pkg"):
            row += s("", " " * max(2, 34 - width(row))) + s("d3", WHERE[nm][1])
        out.append((row, "sel" if nm == cursor else ""))
    return out

def pane(title, rest, code):
    r = s("", " ")
    for t in ["Code", "Types", "Built from", "Used by", "Map", "Changed"]: r += s("tab bold" if t == "Code" else "c", f" {t} ") + s("", "  ")
    return [(s("", " ") + title + s("c", "   " + rest), ""), blank()[0], (r, ""), blank()[0]] + code

def screen(name, v, which):
    if which == "core":
        right = pane(s("b bold", "update") + s("pun", "()"), "function in run/update.ts:144", code_rows(v, os.path.join(CORE_SRC, "run/update.ts"), 144, 193))
        cursor = "update"
    else:
        right = pane(s("b bold", "useOwnedRun") + s("pun", "()"), "function in react/src/useRun.ts:39", code_rows(v, os.path.join(REACT_SRC, "useRun.ts"), 39, 67))
        cursor = "useOwnedRun"
    left = tree_rows(v, cursor)
    hd = [(s("c", " Seams › ") + s("fg bold", cursor + "()"), ""), (s("d3", "─" * W), "")]
    n = max(len(left), len(right)) + 1
    lib.write_shot(name, compose(hd, [(left + blank(n - len(left)), LW), (right + blank(n - len(right)), RW)], cursor + "()", "l open   <Tab> view   J go"))

for v in ["underline", "dotted", "italic", "bold-here", "glyph", "file"]:
    screen(f"where-{v}-core", v, "core")
    screen(f"where-{v}-react", v, "react")
print("ok")
