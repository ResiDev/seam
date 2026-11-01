# Many ways to draw the Map, all on raf core's real calls (seam's treesitter
# index) and signatures (sigs.json). Writes one shot per idea and a gallery.
#   python3 ideas.py <treesitter.json> <sigs.json> <raf core src>
#       -> /tmp/seam-tree/v6/mapx-*.html, /tmp/seam-tree/v6/map-ideas.html
import sys, os, json, re, posixpath, collections, html as H
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose, width
lib.W = W = 178
lib.SHOT_CSS += " .nv .chip{background:#24283b} .nv .chipb{background:#2f3549;font-weight:700} .nv .bar{background:#3d59a1;color:#c0caf5} .nv .bar2{background:#2e3c64;color:#a9b1d6} .nv .bar3{background:#283152;color:#737aa2}"
TSX = json.load(open(sys.argv[1]))
N = {n["id"]: n for n in TSX["nodes"]}
S = json.load(open(sys.argv[2]))
SRC = sys.argv[3]
CORE = "packages/core/src/"
SIG = {}
for f in S["files"]:
    for x in f["fns"]: SIG[(CORE + f["path"], x["name"])] = x

def unwrap(t):
    while True:
        i = t.find("Readonly<")
        if i < 0: return t
        depth = 0
        for j in range(i + 8, len(t)):
            if t[j] == "<": depth += 1
            elif t[j] == ">" and t[j - 1] != "=":
                depth -= 1
                if depth == 0: break
        t = t[:i] + t[i + 9:j] + t[j + 1:]
def simple(t): return re.sub(r"\s+", " ", unwrap(re.sub(r"/\*\*.*?\*/", "", t or ""))).strip()
def cut(t, w): return t if len(t) <= w else t[:w - 1] + "…"
def sig(i, w=34):
    x = SIG.get((N[i]["path"], N[i]["name"]))
    if not x: return None
    def part(p):
        t = simple(p.get("type") or p["name"])
        return "{ … }" if t.startswith("{") else t
    takes = ", ".join(part(p) for p in x["params"])
    ret = simple(x.get("ret")) if x.get("ret") else None
    if not ret:
        h = x.get("hover") or ""
        ret = simple(h.rsplit("=>", 1)[1]).rstrip(")") if "=>" in h else "void"
        if ret.count("{") != ret.count("}") or len(ret) > 30: ret = "{ … }"
    return cut(takes, w), cut(ret, 30)
def kids(i):
    out = []
    for c, _, _ in N[i]["calls"]:
        if c in N and c not in out: out.append(c)
    return out
def byname(nm, path=None):
    return next(i for i, n in N.items() if n["name"] == nm and (path is None or path in n["path"]))
def short(p): return p.replace(CORE, "")
def reach(i):
    seen, st = set(), [i]
    while st:
        for k in kids(st.pop()):
            if k not in seen: seen.add(k); st.append(k)
    seen.discard(i); return seen
CALLERS = collections.defaultdict(list)
for i, n in N.items():
    for c, _, _ in n["calls"]:
        if i not in CALLERS[c]: CALLERS[c].append(i)
def is_test(p): return ".test." in p or "/test/" in p or p.startswith("e2e/") or ".perf." in p

ROOT = byname("createRun")
HOME = N[ROOT]["path"]
LW = 44
RW = W - LW - 1
CAP = 3

# ── a canvas: lines join by their ends, text over them ──────────────────
GLYPH = {5: "│", 10: "─", 6: "┌", 12: "┐", 3: "└", 9: "┘", 7: "├", 13: "┤", 14: "┬", 11: "┴", 15: "┼",
         1: "╵", 4: "╷", 2: "╶", 8: "╴"}
class Canvas:
    def __init__(c, w, h):
        c.w, c.H = w, h
        c.bits = [[0] * w for _ in range(h)]
        c.txt = [[None] * w for _ in range(h)]
        c.cls = [[""] * w for _ in range(h)]
    def grow(c, y):
        while y >= c.H:
            c.bits.append([0] * c.w); c.txt.append([None] * c.w); c.cls.append([""] * c.w); c.H += 1
    def put(c, x, y, text, cls=""):
        c.grow(y)
        for k, ch in enumerate(text):
            if 0 <= x + k < c.w: c.txt[y][x + k] = ch; c.cls[y][x + k] = cls
    def seg(c, segs, x, y):
        for cl, t in segs: c.put(x, y, t, cl); x += len(t)
        return x
    def _b(c, x, y, b, cls):
        c.grow(y)
        if 0 <= x < c.w: c.bits[y][x] |= b; c.cls[y][x] = c.cls[y][x] or cls
    def h(c, x0, x1, y, cls="c"):
        if x0 > x1: x0, x1 = x1, x0
        for x in range(x0, x1 + 1):
            c._b(x, y, (8 if x > x0 else 0) | (2 if x < x1 else 0), cls)
    def v(c, x, y0, y1, cls="c"):
        if y0 > y1: y0, y1 = y1, y0
        for y in range(y0, y1 + 1):
            c._b(x, y, (1 if y > y0 else 0) | (4 if y < y1 else 0), cls)
    def box(c, x, y, w, h, cls="c"):
        c.h(x, x + w - 1, y, cls); c.h(x, x + w - 1, y + h - 1, cls)
        c.v(x, y, y + h - 1, cls); c.v(x + w - 1, y, y + h - 1, cls)
    def rows(c, indent=1):
        out = []
        for y in range(c.H):
            r = s("", " " * indent)
            for x in range(c.w):
                t = c.txt[y][x]
                if t is None:
                    b = c.bits[y][x]
                    r.append((c.cls[y][x] if b else "", GLYPH.get(b, " ") if b else " "))
                else:
                    r.append((c.cls[y][x], t))
            while r and r[-1][1] == " " and r[-1][0] == "": r.pop()
            out.append((r, ""))
        return out

# ── the screen ──────────────────────────────────────────────────────────
VIEWS = ["Code", "Types", "Built from", "Used by", "Map", "Changed"]
def tabs():
    r = s("", " ")
    for t in VIEWS: r += s("tab bold" if t == "Map" else "c", f" {t} ") + s("", "  ")
    return (r, "")
def pane_head(title, rest, display, extra=""):
    return [(s("", " ") + title + s("c", "   " + rest), ""), blank()[0], tabs(),
            (s("", " ") + s("c", "display  ") + s("fg", display) + s("c", extra), ""), blank()[0]]
def tree_left(cursor):
    rows = [blank()[0]]
    T = [("packages/", 0, "fg"), ("core/src/", 1, "hcor"), ("▸ checklists/", 2, "fg"), ("run/", 2, "fg"), ("▸ page.ts", 3, "fg"),
         ("run.ts", 3, "fg"), ("createRun()", 4, "b"), ("▸ update.ts", 3, "fg"), ("storage/", 2, "fg"), ("link.ts", 3, "fg"),
         ("createLink()", 4, "b"), ("▸ records.ts", 3, "fg"), ("state.ts", 2, "fg"), ("Model", 3, "ty"), ("Msg", 3, "ty")]
    for t, d, c in T:
        rows.append((s("", "  " + "  " * d) + s(c, t), "sel" if t == cursor else ""))
    return rows
SHOTS = []
def screen(name, title, cap, right, status, cursor="createRun()", trail="createRun()", wide=False):
    hd = [(s("c", " Seams › ") + s("fg bold", trail), ""), (s("d3", "─" * W), "")]
    keys = "<Tab> view   <C-Tab> display   > < levels   l open   J go"
    if wide:
        body = compose(hd, [(right + blank(1), W)], status, keys)
    else:
        left = tree_left(cursor)
        n = max(len(left), len(right)) + 1
        body = compose(hd, [(left + blank(n - len(left)), LW), (right + blank(n - len(right)), RW)], status, keys)
    lib.write_shot(name, body)
    SHOTS.append((name, title, cap, body))

crh = s("b bold", "createRun") + s("pun", "()")
crr = "function in run/run.ts:33   calls 17"
def head(display, extra="   > < levels   l opens"): return pane_head(crh, crr, display, extra)

# ── 1. tree guides, names only, the file on the right ───────────────────
def guides(root, levels, right=None, cap=CAP, col=40, chain=True):
    rows = [(s("", " ") + s("b bold", N[root]["name"]) + (right(root, len(N[root]["name"]) + 1, col) if right else []), "")]
    def walk(i, prefix, depth):
        ks = kids(i)
        shown = ks if depth == 0 else ks[:cap]
        more = len(ks) - len(shown)
        for j, k in enumerate(shown):
            last = j == len(shown) - 1 and not more
            r = s("c", " " + prefix + ("└─ " if last else "├─ ")) + s("b", N[k]["name"])
            gk = kids(k)
            inline = chain and len(gk) == 1 and depth + 1 < levels
            if inline: r += s("c", " ── ") + s("b", N[gk[0]]["name"])
            if right: r += right(k, width(r), col)
            rows.append((r, ""))
            if depth + 1 < levels and len(gk) > 1 or (depth + 1 < levels and len(gk) == 1 and not chain):
                walk(k, prefix + ("   " if last else "│  "), depth + 1)
        if more: rows.append((s("c", " " + prefix + "└─ ⋯ " + f"{more} more"), ""))
    walk(root, "", 0)
    return rows

def file_right(i, at, col):
    p = short(N[i]["path"])
    if N[i]["path"] == HOME: return []
    return s("", " " * max(2, col - at)) + s("d3", p)
screen("mapx-guides", "Tree lines, names only",
       "The tree's own lines. A call with one call of its own is put on the same line. The file is dim on the right, and only when it isn't run.ts.",
       head("calls") + guides(ROOT, 2, file_right), "createRun()  map · calls")

# ── 2. grouped by file, one row each ────────────────────────────────────
def by_file(root):
    g = collections.OrderedDict()
    for k in kids(root): g.setdefault(N[k]["path"], []).append(k)
    order = sorted(g, key=lambda p: (posixpath.dirname(short(p)) or "~", short(p)))
    rows, last = [], None
    for p in order:
        d = posixpath.dirname(short(p))
        if d != last:
            if last is not None: rows.append(blank()[0])
            rows.append((s("", " ") + s("fg", (d + "/") if d else "core/src/"), "")); last = d
        r = s("", "   ") + s("fd", posixpath.basename(p).ljust(18))
        for j, k in enumerate(g[p]): r += s("b", N[k]["name"]) + s("", "   ")
        rows.append((r, ""))
    return rows
screen("mapx-by-file", "Grouped by file",
       "One row a file, the functions it gives createRun on the row, files under their folder. Shows where a function reaches, at the cost of the order.",
       pane_head(crh, "function in run/run.ts:33   calls 17 in 13 files", "calls by file", "   l opens a file's calls") + by_file(ROOT), "createRun()  map · calls by file")

# ── 3. file boxes in folder bands ───────────────────────────────────────
def file_boxes(root):
    g = collections.OrderedDict()
    for k in kids(root): g.setdefault(N[k]["path"], []).append(k)
    bands = collections.OrderedDict()
    for p in sorted(g, key=lambda p: short(p)):
        bands.setdefault(posixpath.dirname(short(p)), []).append(p)
    order = sorted(bands, key=lambda d: (-sum(len(g[p]) for p in bands[d]), d))
    out = []
    for d in order:
        out.append((s("", " ") + s("fg bold", (d + "/") if d else "core/src/"), ""))
        cv = Canvas(RW - 2, 1)
        x, y, rowh = 2, 0, 0
        for p in bands[d]:
            names = [N[k]["name"] for k in g[p]]
            title = posixpath.basename(p)
            w = max(len(title) + 6, max(len(n) for n in names) + 4)
            h = len(names) + 2
            if x + w > RW - 3: x, y, rowh = 2, y + rowh + 1, 0
            cv.box(x, y, w, h, "d3")
            cv.put(x + 2, y, " " + title + " ", "fd")
            for j, n in enumerate(names): cv.put(x + 2, y + 1 + j, n, "b")
            x += w + 2; rowh = max(rowh, h)
        out += cv.rows(); out.append(blank()[0])
    return out
screen("mapx-file-boxes", "Boxes for files, bands for folders",
       "The same grouping drawn as boxes. The folder with the most calls comes first. It reads at a glance which parts of the code createRun leans on.",
       pane_head(crh, "function in run/run.ts:33   calls 17 in 13 files", "calls by file", "   l opens a box") + file_boxes(ROOT), "createRun()  map · calls by file")

# ── 4. names first, types in columns ────────────────────────────────────
def typed_cols(i, at, col):
    sg = sig(i, 40)
    if not sg: return []
    return s("", " " * max(2, col - at)) + ts(sg[0]) + s("", " " * max(2, 44 - len(sg[0]))) + ts(sg[1])
rows4 = guides(ROOT, 2, typed_cols, col=34, chain=False)
hdr = (s("", " " * 35) + s("c", "takes") + s("", " " * 39) + s("c", "gives"), "")
screen("mapx-type-columns", "Names first, types in two columns",
       "B's facts, but the names come first and line up, and what a call takes and gives sit in their own columns. The eye runs down the names; the types are there to read across.",
       head("calls with types") + [hdr] + rows4, "createRun()  map · calls with types")

# ── 5. names and what each gives ────────────────────────────────────────
def gives_col(i, at, col):
    sg = sig(i)
    if not sg: return []
    return s("", " " * max(2, col - at)) + s("c", "→ ") + ts(sg[1])
screen("mapx-gives", "Names and what each gives",
       "Half the types: only what each call gives back. It reads as what createRun gets from each part.",
       head("calls with what they give") + guides(ROOT, 2, gives_col, col=36), "createRun()  map · calls · gives")

# ── 6. a type map: types as boxes, functions on the arrows ──────────────
def type_graph():
    cv = Canvas(RW - 2, 30)
    def tbox(x, y, name, h=3):
        w = len(name) + 4
        cv.box(x, y, w, h, "d3"); cv.put(x + 2, y + 1, name, "ty bold" if name == "Model" else "ty")
        return x, y, w, h
    def arrow(x0, x1, y, label):
        cv.h(x0, x1 - 1, y, "c"); cv.put(x1, y, "▶", "c")
        if label: cv.put(x0 + 2, y, " " + label + " ", "b")
    # left: what makes Model
    g = tbox(0, 1, "Given"); u = tbox(0, 5, "UserRecord")
    cv.h(g[2], 16, 2, "c"); cv.h(u[2], 16, 6, "c"); cv.v(16, 2, 6, "c")
    arrow(16, 39, 4, "initialModel")
    m = tbox(40, 3, "Model")
    cv.put(40, 1, "↺ withStartRequests", "b")
    cv.v(43, 2, 3, "c")
    # Model to Updated, four ways
    mx = m[0] + m[2] - 1
    cv.v(mx + 3, 4, 13, "c"); cv.h(mx, mx + 3, 4, "c")
    for j, nm in enumerate(["update", "change", "command", "unchanged"]):
        y = 10 + j
        cv.h(mx + 3, 74, y, "c"); cv.put(75, y, "▶", "c"); cv.put(mx + 5, y, " " + nm + " ", "b")
    cv.box(76, 9, 11, 6, "d3"); cv.put(78, 10, "Updated", "ty")
    # Model to RunState
    arrow(mx, 75, 4, "runStateOf")
    r = tbox(76, 3, "RunState")
    rx = r[0] + r[2] - 1
    cv.put(76, 1, "↺ 13 that give RunState back", "b")
    cv.v(79, 2, 3, "c")
    for j, (nm, out) in enumerate([("createPage", "Page"), ("runChange", "Ran"), ("isBeacon", "boolean")]):
        y = 4 + j * 4
        if j: cv.v(rx + 2, 4, y, "c")
        cv.h(rx if j == 0 else rx + 2, 112, y, "c"); cv.put(113, y, "▶", "c"); cv.put(rx + 3, y, " " + nm + " ", "b")
        tbox(114, y - 1, out)
    return cv.rows()
screen("mapx-type-graph", "Types as boxes, functions on the arrows",
       "A type's map turned inside out. Boxes are types, arrows are the functions that turn one into another. Model is made from Given and UserRecord, becomes Updated four ways, and RunState by runStateOf.",
       pane_head(s("ty bold", "Model"), "type in state.ts:152   made by 2, taken by 7", "types and what turns them", "   > < levels   l opens a box") + type_graph(),
       "Model  map", cursor="Model", trail="Model")

# ── 7. butterfly: who calls it on the left, what it calls on the right ──
def butterfly(root):
    callers = sorted(CALLERS[root], key=lambda c: (is_test(N[c]["path"]), N[c]["path"]))
    L = []
    for c in callers:
        n = N[c]; test = is_test(n["path"])
        p = n["path"].replace(CORE, "").replace("packages/", "")
        L.append(s("d3", p + "  ") + s("d3" if test else "b", n["name"] or "(top level)"))
    R = [N[k]["name"] for k in kids(root)]
    n = max(len(L), len(R)); mid = n // 2
    lx = 58
    cv = Canvas(RW - 2, n)
    l0 = mid - len(L) // 2; r0 = mid - len(R) // 2
    for j, seg in enumerate(L):
        y = l0 + j
        cv.seg(seg, lx - width(seg), y); cv.h(lx + 1, lx + 3, y, "c")
    cv.v(lx + 3, l0, l0 + len(L) - 1, "c"); cv.h(lx + 3, lx + 6, mid, "c")
    nm = N[root]["name"]
    cv.put(lx + 7, mid, nm, "b bold")
    bx = lx + 8 + len(nm)
    cv.h(bx, bx + 3, mid, "c"); cv.v(bx + 3, r0, r0 + len(R) - 1, "c")
    for j, r in enumerate(R):
        cv.h(bx + 3, bx + 5, r0 + j, "c"); cv.put(bx + 6, r0 + j, r, "b")
    return cv.rows()
screen("mapx-butterfly", "Both ways at once",
       "Who calls createRun on the left, what it calls on the right. Callers in tests are dim and last: one caller outside tests, WaymarkRoot in react. One picture answers where it sits.",
       pane_head(crh, "function in run/run.ts:33   called by 16, calls 17", "both ways", "   l opens a side's name") + butterfly(ROOT), "createRun()  map · both ways")

# ── 8. boxes and lines, each function drawn once ────────────────────────
def dag(root, levels):
    depth = {root: 0}
    order = [root]
    for d in range(levels):
        for i in list(order):
            if depth[i] != d: continue
            for k in kids(i):
                if k not in depth: depth[k] = d + 1; order.append(k)
    nodes = set(depth)
    nd = max(depth.values())
    cols = [[] for _ in range(nd + 1)]
    for i in order: cols[depth[i]].append(("n", i))
    # dummies for edges that skip a column
    edges = []
    for i in order:
        for k in kids(i):
            if k not in nodes: continue
            a, b = depth[i], depth[k]
            if b != a + 1: continue
            prev = ("n", i)
            for d in range(a + 1, b):
                dm = ("d", i, k, d); cols[d].append(dm); edges.append((prev, dm)); prev = dm
            edges.append((prev, ("n", k)))
    # barycentre order, once left to right
    pos = {}
    for d, col in enumerate(cols):
        if d:
            def bc(it):
                ps = [pos[a] for a, b in edges if b == it and a in pos]
                return sum(ps) / len(ps) if ps else 0
            col.sort(key=bc)
        for y, it in enumerate(col): pos[it] = y * 2
    colw = [max((len(N[it[1]]["name"]) + 2 if it[0] == "n" else 2) for it in col) for col in cols]
    gut = []
    for d in range(nd):
        parents = [it for it in cols[d] if any(a == it for a, b in edges)]
        gut.append(len(parents) * 2 + 3)
    xs, x = [], 0
    for d in range(nd + 1):
        xs.append(x); x += colw[d] + (gut[d] if d < nd else 0)
    H_ = max(len(c) for c in cols) * 2
    cv = Canvas(x + 2, H_)
    for d, col in enumerate(cols):
        for it in col:
            y = pos[it]
            if it[0] == "n":
                cv.put(xs[d], y, " " + N[it[1]]["name"] + " ", "chipb" if it[1] == root else "chip b")
            else:
                cv.h(xs[d] - 1, xs[d] + colw[d], y, "d3")
    for d in range(nd):
        parents = [it for it in cols[d] if any(a == it for a, b in edges)]
        x0 = xs[d] + colw[d]
        for t, p in enumerate(parents):
            tx = x0 + 1 + t * 2
            kidsy = [pos[b] for a, b in edges if a == p]
            py = pos[p]
            pw = (len(N[p[1]]["name"]) + 2) if p[0] == "n" else colw[d]
            cv.h(xs[d] + pw, tx, py, "c")
            cv.v(tx, min(kidsy + [py]), max(kidsy + [py]), "c")
            for ky in kidsy: cv.h(tx, xs[d + 1] - 1, ky, "c")
    return cv.rows()
LINK = byname("createLink")
screen("mapx-graph", "Boxes and lines, each function once",
       "A real graph of createLink two calls deep. A function called from two places is drawn once with two lines in, so dictionary and copy show they are shared. Calls between names in the same column are left out, and lines that cross read as joined: the cost of a graph in text.",
       pane_head(s("b bold", "createLink") + s("pun", "()"), "function in storage/link.ts:63   calls 9", "calls as a graph", "   > < levels") + dag(LINK, 2),
       "createLink()  map · graph", cursor="createLink()", trail="createLink()")

# ── 9. a matrix: which file calls which ─────────────────────────────────
def matrix(folder):
    E = collections.Counter()
    def ok(p): return p.startswith(CORE) and not is_test(p)
    for i, n in N.items():
        if not ok(n["path"]) or not n["path"].startswith(CORE + folder): continue
        for c, _, _ in n["calls"]:
            if c in N and ok(N[c]["path"]) and N[c]["path"] != n["path"]:
                E[(short(n["path"]), short(N[c]["path"]))] += 1
    rws = sorted({a for a, b in E})
    cls = sorted({b for a, b in E}, key=lambda p: (not p.startswith(folder), p))
    lw, cw = 22, 4
    x0 = lw + 2
    out = []
    for j, c in enumerate(cls):
        r = s("", " " * (x0 + 1))
        for k in range(j): r += s("d3", "│".ljust(cw))
        r += s("d3", "┌─ ") + s("fd" if c.startswith(folder) else "c", c)
        out.append((r, ""))
    for a in rws:
        r = s("", " ") + s("fg", posixpath.basename(a).rjust(lw)) + s("", "  ")
        for c in cls:
            n = E.get((a, c))
            r += (s("o", str(n).ljust(cw)) if n else s("d3", "·".ljust(cw)))
        out.append((r, ""))
    return out
screen("mapx-matrix", "A matrix of files",
       "A folder's map as a grid: each run/ file down the side, every file they call across the top, the number of calls where they meet. It shows the shape of a folder at once, and shows nothing about any one function.",
       pane_head(s("fg bold", "run/"), "folder in core/src   10 files call into 21", "files as a grid", "") + matrix("run/"),
       "run/  map · grid", cursor="run/", trail="run/")

# ── 10. in order, a lane for each file ──────────────────────────────────
def sequence(root):
    calls = [(c, l) for c, l, _ in N[root]["calls"] if c in N]
    calls.sort(key=lambda t: t[1])
    lanes = [HOME]
    for c, _ in calls:
        if N[c]["path"] not in lanes: lanes.append(N[c]["path"])
    lw, cw = 26, 5
    x0 = lw + 3
    out = []
    for j, p in enumerate(lanes):
        r = s("", " " * x0)
        for k in range(j): r += s("d3", "│".ljust(cw))
        nm = posixpath.basename(p).replace(".ts", "")
        r += s("d3", "┌─ ") + s("fg bold" if p == HOME else "fd", nm)
        out.append((r, ""))
    for c, l in calls:
        t = lanes.index(N[c]["path"])
        r = s("", " ") + s("c", str(l).rjust(4)) + s("", "  ") + s("b", N[c]["name"].ljust(lw - 6)) + s("", "  ")
        for k in range(len(lanes)):
            if k == 0: r += s("c", "●") + s("c", "─" * (cw - 1) if t > 0 else " " * (cw - 1))
            elif k < t: r += s("c", "─" * cw)
            elif k == t: r += s("b", "●") + s("", " " * (cw - 1))
            else: r += s("d3", "│".ljust(cw))
        out.append((r, ""))
    return out
screen("mapx-sequence", "In order, a lane for each file",
       "Every call createRun makes, in the order of the code, each file a lane. Shows when it touches what: setup first, the storage calls in the middle, the checklist calls at the end.",
       pane_head(crh, crr, "calls in order", "") + sequence(ROOT), "createRun()  map · in order")

# ── 11. how much each call reaches ──────────────────────────────────────
def weights(root):
    ks = sorted(kids(root), key=lambda k: -len(reach(k)))
    tot = len(reach(root))
    mx = max(len(reach(k)) for k in ks)
    bw = 60
    out = [(s("", " ") + s("c", f"of the {tot} functions createRun reaches, each call reaches"), ""), blank()[0]]
    for k in ks:
        n = len(reach(k))
        w = round(bw * n / mx)
        r = s("", "   ") + s("b", N[k]["name"].ljust(18)) + (s("bar", " " * w) if w else s("d3", "▏")) + s("c", f" {n}")
        if N[k]["path"] != HOME: r += s("", " " * (bw + 26 - width(r))) + s("d3", short(N[k]["path"]))
        out.append((r, ""))
    return out
screen("mapx-weight", "How much each call reaches",
       "A bar for how many functions each call goes on to reach. update is where the weight is. A first look at a big function: which branch to open.",
       pane_head(crh, crr, "calls by reach", "   l opens") + weights(ROOT), "createRun()  map · by reach")

# ── 12. an icicle: width is how much is under it ────────────────────────
def icicle(root, levels):
    bw = RW - 4
    out = []
    rowcls = ["chipb", "bar", "bar2", "bar3"]
    spans = [(root, 0, bw)]
    out.append((s("", " ") + s("bar", (" " + N[root]["name"]).ljust(bw)), ""))
    for d in range(1, levels + 1):
        nxt = []
        line = [(" ", "")] * bw
        cells = []
        for i, x, w in spans:
            ks = kids(i)
            if not ks or w < 2: continue
            tot = sum(len(reach(k)) + 1 for k in ks)
            at = x
            small = []
            for k in sorted(ks, key=lambda k: -len(reach(k))):
                kw = int(w * (len(reach(k)) + 1) / tot)
                if kw < len(N[k]["name"]) + 2: small.append(k); continue
                cells.append((at, kw, N[k]["name"])); nxt.append((k, at, kw)); at += kw
            if small and x + w - at >= 2:
                cells.append((at, x + w - at, f"⋯{len(small)}"))
        r = s("", " ")
        at = 0
        for j, (x, w, nm) in enumerate(sorted(cells)):
            if x > at: r += s("", " " * (x - at))
            cl = "bar2" if (j % 2 == 0) else "bar3"
            r += s(cl, (" " + nm).ljust(w - 1)[:w - 1]) + s("", " ")
            at = x + w
        out.append((r, ""))
        spans = nxt
    return out
screen("mapx-icicle", "An icicle",
       "The call tree as nested bars, each as wide as how much is under it, three calls deep. Small calls fold into ⋯ and a count. The shape of a big function in one glance; names get cut where it's thin.",
       pane_head(crh, crr, "calls as bars", "   > < levels   l zooms in") + icicle(ROOT, 3), "createRun()  map · bars")

# ── 13. every way from one to another ───────────────────────────────────
def paths(a, b, maxd=5):
    found = []
    def dfs(x, path):
        if len(path) > maxd: return
        for k in kids(x):
            if k == b: found.append(path[1:]); continue
            if k not in path: dfs(k, path + [k])
    dfs(a, [a])
    found.sort(key=lambda p: (len(p), [N[i]["name"] for i in p]))
    col = max(sum(len(N[i]["name"]) + 4 for i in p) for p in found) + len(N[a]["name"]) + 6
    out = []
    prev = []
    for j, p in enumerate(found):
        r = s("", " ")
        if j == 0: r += s("b bold", N[a]["name"]) + s("c", " ─┬─")
        else: r += s("", " " * (len(N[a]["name"]) + 2)) + s("c", "└─" if j == len(found) - 1 else "├─")
        at = len(N[a]["name"]) + 5
        for k, i in enumerate(p):
            same = k < len(prev) and prev[:k + 1] == p[:k + 1]
            r += s("c", " ") + s("d3" if same else "b", N[i]["name"]) + s("c", " ─")
            at += len(N[i]["name"]) + 3
        r += s("c", "─" * (col - at))
        r += s("c", ("─┬─▶ " if j == 0 else "─┘" if j == len(found) - 1 else "─┤"))
        if j == 0: r += s("b bold", N[b]["name"])
        out.append((r, ""))
        prev = p
    return out, len(found)
OPEN = byname("begin", "walkthroughs")
prow, pn = paths(ROOT, OPEN)
screen("mapx-paths", "Every way from one to another",
       f"Pick two functions and see each way the first reaches the second: here the {pn} ways createRun gets to begin. A name already on the line above is dim, so where the ways part is plain.",
       pane_head(crh + s("c", "  to  ") + s("b bold", "begin") + s("pun", "()"), f"{pn} ways, at most 5 calls deep", "ways between two", "   m marks the second") + prow,
       "createRun() → begin()  map · ways")

# ── 14. the body cut to its calls ───────────────────────────────────────
def skeleton(root):
    lines = open(os.path.join(SRC, "run/run.ts")).read().split("\n")
    n0, n1 = N[root]["line"], N[root]["end_line"]
    names = {N[k]["name"] for k in kids(root)}
    opener = re.compile(r"^(\s*)(?:(?:const|let) (\w+)(?::[^=]+)? = (?:\([^)]*\)|\w+) =>|function (\w+)\(([^)]*)\)|(\w+): (?:\([^)]*\)|\w+) =>|(if) \((.*?)\)(?= )|(\w+): on\()")
    stack, out = [], []
    shown = []
    for ln in range(n0, n1):
        src = lines[ln]
        ind = len(src) - len(src.lstrip())
        while stack and ind <= stack[-1][0] and src.strip().startswith(("}", ")")) is False and ind <= stack[-1][0]:
            stack.pop()
        while stack and ind <= stack[-1][0] and src.strip().startswith(("}", "})", "},", "};")):
            stack.pop(); break
        m = opener.match(src)
        found = [(m2.start(), m2.group(1)) for m2 in re.finditer(r"\b(\w+)\(", src) if m2.group(1) in names]
        if m and ln > n0:
            label = m.group(2) or m.group(3) or m.group(5) or m.group(8)
            kind = "if " + cut(m.group(7), 44) if m.group(6) else label
            stack.append((ind, kind, ln + 1))
        if found:
            ctx = tuple(k for _, k, _ in stack)
            shown.append((ctx, [f for _, f in found], ln + 1))
    rows = [(s("", " ") + s("b bold", "createRun") + s("pun", "(") + s("fg", "options") + s("pun", ")"), "")]
    last = ()
    for ctx, fs, ln in shown:
        for d in range(len(ctx)):
            if d >= len(last) or last[d] != ctx[d]:
                k = ctx[d]
                lab = s("m it", "if ") + ts(k[3:]) if k.startswith("if ") else s("fg", k) + s("c", " ⇒")
                rows.append((s("", " " + "   " * (d + 1)) + lab, ""))
        r = s("", " " + "   " * (len(ctx) + 1))
        for f in fs: r += s("b", f) + s("", "  ")
        r += s("", " " * max(1, 64 - width(r))) + s("d3", str(ln))
        rows.append((r, ""))
        last = ctx
    return rows
screen("mapx-skeleton", "The body cut down to its calls",
       "createRun with everything but its calls taken out, keeping the closures and ifs they sit in. Shows when a call happens: at once, inside step, or only when a checklist is first asked for. The line on the right.",
       pane_head(crh, crr, "calls where they happen", "   l opens a call") + skeleton(ROOT), "createRun()  map · where")

# ── 15. a folder map: folders as boxes, calls on the arrows ─────────────
def folders():
    def ok(p): return p.startswith(CORE) and not is_test(p)
    E = collections.Counter(); files = collections.defaultdict(set)
    for i, n in N.items():
        if not ok(n["path"]): continue
        a = posixpath.dirname(short(n["path"])) or "."
        files[a].add(n["path"])
        for c, _, _ in n["calls"]:
            if c in N and ok(N[c]["path"]):
                b = posixpath.dirname(short(N[c]["path"])) or "."
                if a != b: E[(a, b)] += 1
    cv = Canvas(RW - 2, 24)
    def fbox(x, y, d, w=24):
        nm = (d + "/") if d != "." else "core/src/ files"
        cv.box(x, y, w, 4, "d3"); cv.put(x + 2, y + 1, nm, "fg bold"); cv.put(x + 2, y + 2, f"{len(files[d])} file" + ("s" if len(files[d]) != 1 else ""), "c")
        return (x, y, w)
    run = fbox(0, 8, "run")
    mids = {"walkthrough": fbox(50, 1, "walkthrough"), "storage": fbox(50, 8, "storage"), "checklists": fbox(50, 15, "checklists")}
    dot = fbox(100, 8, ".")
    def lab(n): return f" {n} call" + ("s " if n != 1 else " ")
    # run → the three
    cv.h(24, 34, 10, "c"); cv.v(34, 3, 17, "c")
    for d, y in [("walkthrough", 3), ("storage", 10), ("checklists", 17)]:
        cv.h(34, 48, y, "c"); cv.put(49, y, "▶", "c"); cv.put(37, y, lab(E[("run", d)]), "o")
    # run → . over the top
    cv.v(12, 0, 7, "c"); cv.h(12, 112, 0, "c"); cv.v(112, 0, 7, "c"); cv.put(112, 7, "▼", "c"); cv.put(60, 0, lab(E[("run", ".")]), "o")
    # storage → checklists, storage → ., checklists → ., checklists → walkthrough
    cv.v(62, 12, 14, "c"); cv.put(62, 14, "▼", "c"); cv.put(64, 13, lab(E[("storage", "checklists")]), "o")
    cv.h(74, 98, 10, "c"); cv.put(99, 10, "▶", "c"); cv.put(80, 10, lab(E[("storage", ".")]), "o")
    cv.h(74, 108, 17, "c"); cv.v(108, 12, 17, "c"); cv.put(108, 12, "▲", "c"); cv.put(80, 17, lab(E[("checklists", ".")]), "o")
    cv.h(74, 78, 16, "c"); cv.v(78, 3, 16, "c"); cv.h(75, 78, 3, "c"); cv.put(74, 3, "◀", "c"); cv.put(79, 6, lab(E[("checklists", "walkthrough")]), "o")
    return cv.rows()
screen("mapx-folders", "Folders as boxes, calls on the arrows",
       "A package's map: one box a folder, an arrow where one calls into another, the count on it. run/ calls everything; nothing calls run/. The boundaries, drawn.",
       pane_head(s("fg bold", "core/src/"), "package core   5 folders", "folders", "   l opens a box") + folders(),
       "core/src/  map · folders", cursor="core/src/", trail="core/src/")

# ── 16. values as lanes: what each call makes, who takes it ─────────────
def lanes():
    # read off createRun's body: each value, the call that makes it, the calls it's handed to
    V = [("report", "ReportProblem<TStep>"), ("queue", "Queue"), ("adapter", "StorageAdapter"),
         ("(record)", "UserRecord"), ("model", "Model"), ("runState", "RunState"), ("group", "ChecklistGroup")]
    R_ = [("problemReporter", 36, [], "report"), ("createQueue", 37, ["report"], "queue"), ("adapterOf", 38, [], "adapter"),
          ("userRecordAt", 47, ["adapter"], "(record)"), ("initialModel", 47, ["(record)"], "model"),
          ("runStateOf", 51, ["model"], "runState"), ("createPage", 67, ["queue", "runState"], None),
          ("createLink", 69, ["adapter", "queue", "report"], None), ("update", 93, ["model"], "model"),
          ("groupOf", 180, [], "group"), ("viewChecklist", 181, ["group", "runState"], None),
          ("listen", 197, ["queue"], None), ("openOf", 228, ["runState"], None)]
    names = [v for v, _ in V]
    T = dict(V)
    first = {}; lastu = {}
    for r, (nm, ln, takes, makes) in enumerate(R_):
        if makes and makes not in first: first[makes] = r
        for t in takes: lastu[t] = r
        if makes: lastu[makes] = max(lastu.get(makes, r), r)
    lw, cw = 22, 4
    out = []
    for r, (nm, ln, takes, makes) in enumerate(R_):
        row = s("", " ") + s("c", str(ln).rjust(4)) + s("", "  ") + s("b", nm.ljust(lw - 6))
        lastdot = max([names.index(t) for t in takes] + ([names.index(makes)] if makes else []) + [-1])
        for k, v in enumerate(names):
            live = v in first and first[v] <= r <= lastu.get(v, -1)
            hop = k < lastdot
            if v in takes: row += s("o", "●") + s("c", "─" * (cw - 1) if hop else " " * (cw - 1))
            elif v == makes and first[v] == r: row += s("g", "●") + s("c", "─" * (cw - 1) if hop else " " * (cw - 1))
            elif v == makes: row += s("g", "●") + s("c", "─" * (cw - 1) if hop else " " * (cw - 1))
            elif hop: row += s("c", "─" * cw)
            elif live: row += s("d3", "│".ljust(cw))
            else: row += s("", " " * cw)
        if makes: row += s("c", " → ") + s("fg", makes) + s("", "  ") + ts(T[makes])
        out.append((row, ""))
    return out
screen("mapx-lanes", "Values as lanes",
       "Each value createRun makes is a lane that starts at the call that makes it and runs down to the last call it is handed to. Read across a row for what a call takes; down a lane for where a value goes. Types ride on the values, not on every call.",
       pane_head(crh, crr, "values between calls", "") + lanes(), "createRun()  map · values")


# ── round two: the picks, on every kind of row ──────────────────────────
DISP = ["tree", "both ways", "folders", "size"]
TDISP = ["tree", "both ways", "folders", "by field", "by file"]
def phead(title, rest, cur, opts=DISP, hint=""):
    r = s("", " ") + s("c", "display  ")
    for j, o in enumerate(opts):
        if j: r += s("d3", " · ")
        r += s("fg bold" if o == cur else "c", o)
    r += s("c", hint)
    return [(s("", " ") + title + s("c", "   " + rest), ""), blank()[0], tabs(), (r, ""), blank()[0]]

# the tree, types hidden and shown with T
def plain_right(i, at, col): return []
screen("mapy-fn-tree", "A function, tree, T off",
       "Names only. T shows what each call takes and gives, and stays.",
       phead(crh, crr, "tree", hint="     T inputs and outputs   > < levels   l opens") + guides(ROOT, 2, None, chain=False),
       "createRun()  map · tree")
screen("mapy-fn-tree-types", "A function, tree, T on",
       "The same rows with T on: what each takes and gives, in columns.",
       phead(crh, crr, "tree", hint="     T inputs and outputs   > < levels   l opens") + [hdr] + rows4,
       "createRun()  map · tree · types")

# folders, on a function: the folders its calls go into, each a box
def fn_folders(root):
    g = collections.OrderedDict()
    for k in kids(root):
        d = posixpath.dirname(short(N[k]["path"]))
        g.setdefault(d, collections.OrderedDict()).setdefault(posixpath.basename(N[k]["path"]), []).append(N[k]["name"])
    order = sorted(g, key=lambda d: -sum(len(v) for v in g[d].values()))
    heights = [sum(1 for _ in g[d]) + 3 for d in order]
    H_ = sum(heights) + len(order) - 1
    cv = Canvas(RW - 2, H_)
    nm = N[root]["name"]
    mid = H_ // 2
    cv.box(0, mid - 1, len(nm) + 4, 3, "d3"); cv.put(2, mid, nm, "b bold")
    cv.put(2, mid + 2, "run/", "c")
    bus = len(nm) + 10
    cv.h(len(nm) + 4, bus, mid, "c")
    y = 0; tops = []
    bx = bus + 18
    for d, h in zip(order, heights):
        files = g[d]
        w = max(len(x) for x in files) + 4 + max(len("  ".join(v)) for v in files.values()) + 4
        w = max(w, len(d) + 8)
        cv.box(bx, y, w, h, "d3")
        cv.put(bx + 2, y, " " + ((d + "/") if d else "core/src/ files") + " ", "fg bold")
        for j, (f, v) in enumerate(files.items()):
            cv.put(bx + 2, y + 2 + j, f.ljust(max(len(x) for x in files) + 2), "fd")
            cv.put(bx + 4 + max(len(x) for x in files), y + 2 + j, "  ".join(v), "b")
        ay = y + 2
        n = sum(len(v) for v in files.values())
        tops.append(ay)
        cv.h(bus, bx - 2, ay, "c"); cv.put(bx - 1, ay, "▶", "c")
        cv.put(bus + 2, ay, f" {n} call" + ("s " if n != 1 else " "), "o")
        y += h + 1
    cv.v(bus, min(tops + [mid]), max(tops + [mid]), "c")
    return cv.rows()
screen("mapy-fn-folders", "A function, folders",
       "createRun's calls as the folders they go into, each folder a box holding the files and names. The arrow says how many. > follows those on into the folders they call.",
       phead(crh, crr, "folders", hint="     > < levels   l opens a box") + fn_folders(ROOT),
       "createRun()  map · folders")


# folders, on a function, both sides: who calls it left, what it calls right
HEADS = "right"
def fn_folders_both(root):
    def group(ids):
        g = collections.OrderedDict()
        for k in ids:
            path = N[k]["path"]
            d = posixpath.dirname(short(path)) if path.startswith(CORE) else posixpath.dirname(path.replace("packages/", ""))
            g.setdefault(d, collections.OrderedDict()).setdefault(posixpath.basename(path), []).append(N[k]["name"] or "(top level)")
        return g
    R = group(kids(root))
    callers = CALLERS[root]
    real = [c for c in callers if not is_test(N[c]["path"])]
    tests = [c for c in callers if is_test(N[c]["path"])]
    L = group(real)
    def bsize(files): return len(files) + 3
    def bwidth(files, title):
        mf = max(len(x) for x in files)
        return max(mf + 4 + max(len("  ".join(v)) for v in files.values()) + 4, len(title) + 8)
    rorder = sorted(R, key=lambda d: -sum(len(v) for v in R[d].values()))
    rh = sum(bsize(R[d]) for d in rorder) + len(rorder) - 1
    lh = sum(bsize(L[d]) for d in L) + len(L) + 3
    H_ = max(rh, lh)
    cv = Canvas(RW - 2, H_)
    mid = H_ // 2
    nm = N[root]["name"]
    cx = 44
    cv.box(cx, mid - 1, len(nm) + 4, 3, "d3"); cv.put(cx + 2, mid, nm, "b bold"); cv.put(cx + 2, mid + 2, "run/", "c")
    def draw(files, title, x, y, w, dim=False):
        cv.box(x, y, w, bsize(files), "d3")
        cv.put(x + 2, y, " " + title + " ", "c" if dim else "fg bold")
        mf = max(len(f) for f in files)
        for j, (f, v) in enumerate(files.items()):
            cv.put(x + 2, y + 2 + j, f.ljust(mf + 2), "d3" if dim else "fd")
            cv.put(x + 4 + mf, y + 2 + j, "  ".join(v), "d3" if dim else "b")
    # left: the callers, by folder, then the tests as a count
    y = mid - (lh // 2); lys = []
    for d in L:
        title = (d + "/")
        w = bwidth(L[d], title)
        draw(L[d], title, 0, y, w)
        lys.append((y + 2, w)); y += bsize(L[d]) + 1
    tfiles = len({N[c]["path"] for c in tests})
    cv.put(2, y, f"⋯ {len(tests)} in tests, {tfiles} files", "c"); lys.append((y, len(f"⋯ {len(tests)} in tests, {tfiles} files") + 2))
    lbus = cx - 6
    for ay, w in lys:
        cv.h(w + (0 if w > 30 else 0), lbus, ay, "c")
    cv.v(lbus, min(a for a, _ in lys + [(mid, 0)]), max(a for a, _ in lys + [(mid, 0)]), "c")
    cv.h(lbus, cx - 2, mid, "c")
    if HEADS != "none": cv.put(cx - 1, mid, "▶", "c")
    n = len(callers)
    # right: what it calls
    rbus = cx + len(nm) + 8
    bx = rbus + 14
    y = mid - rh // 2; tops = []
    cv.h(cx + len(nm) + 4, rbus, mid, "c")
    for d in rorder:
        title = (d + "/") if d else "core/src/ files"
        draw(R[d], title, bx, y, bwidth(R[d], title))
        ay = y + 2; tops.append(ay)
        k = sum(len(v) for v in R[d].values())
        cv.h(rbus, bx - 2, ay, "c")
        if HEADS == "right": cv.put(bx - 1, ay, "▶", "c")
        if HEADS == "in": cv.put(rbus + 1, ay, "◀", "c")
        cv.put(rbus + 2, ay, f" {k} call" + ("s " if k != 1 else " "), "o")
        y += bsize(R[d]) + 1
    cv.v(rbus, min(tops + [mid]), max(tops + [mid]), "c")
    return cv.rows()
screen("mapy-fn-folders-both", "A function, folders, both sides",
       "Who calls createRun on the left, by folder, tests folded to a count; what it calls on the right. Every arrow runs from the caller to what it calls, left to right, as both ways does.",
       phead(crh, "function in run/run.ts:33   called by 16, calls 17", "folders", hint="     > < levels   l opens a box") + fn_folders_both(ROOT),
       "createRun()  map · folders")

# both ways, on a folder and on a type
def both(left, right, centre, lw=56):
    n = max(len(left), len(right)); mid = n // 2
    cv = Canvas(RW - 2, n)
    l0 = mid - len(left) // 2; r0 = mid - len(right) // 2
    for j, seg in enumerate(left):
        cv.seg(seg, lw - width(seg), l0 + j); cv.h(lw + 1, lw + 3, l0 + j, "c")
    if left: cv.v(lw + 3, l0, l0 + len(left) - 1, "c"); cv.h(lw + 3, lw + 6, mid, "c")
    cv.seg(centre, lw + 7, mid)
    bx = lw + 8 + width(centre)
    cv.h(bx, bx + 3, mid, "c")
    if right: cv.v(bx + 3, r0, r0 + len(right) - 1, "c")
    for j, seg in enumerate(right):
        cv.h(bx + 3, bx + 5, r0 + j, "c"); cv.seg(seg, bx + 6, r0 + j)
    return cv.rows()

def folder_both(folder):
    inn = collections.defaultdict(set); out = collections.defaultdict(set)
    for i, n in N.items():
        if is_test(n["path"]) or not n["path"].startswith("packages/"): continue
        a_in = n["path"].startswith(CORE + folder)
        for c, _, _ in n["calls"]:
            if c not in N: continue
            b_in = N[c]["path"].startswith(CORE + folder)
            if b_in and not a_in: inn[n["path"]].add(N[c]["name"])
            if a_in and not b_in and N[c]["path"].startswith("packages/"): out[N[c]["path"]].add(N[c]["name"])
    def seg(p, names, left):
        f = p.replace(CORE, "").replace("packages/", "")
        nm = ", ".join(sorted(names))
        return (s("c", cut(nm, 26) + "  ") + s("fg", f)) if left else (s("fg", f) + s("c", "  " + cut(nm, 40)))
    L = [seg(p, v, True) for p, v in sorted(inn.items(), key=lambda kv: -len(kv[1]))]
    R = [seg(p, v, False) for p, v in sorted(out.items(), key=lambda kv: -len(kv[1]))]
    return both(L, R, s("fg bold", folder)), len(inn), len(out)
fb, ni, no = folder_both("storage/")
screen("mapy-folder-both", "A folder, both ways",
       f"storage/: the {ni} files outside it that call in on the left, the {no} files it calls out to on the right, each with the names that cross. The boundary of a folder in one picture.",
       phead(s("fg bold", "storage/"), f"folder in core/src   called from {ni} files, calls {no}", "both ways", hint="     l opens a file") + fb,
       "storage/  map · both ways", cursor="storage/", trail="storage/")

def fns_with(pred):
    out = []
    for f in S["files"]:
        if is_test(f["path"]): continue
        for x in f["fns"]:
            if pred(x): out.append((f["path"], x))
    return out
def takes_t(T): return fns_with(lambda x: any(re.search(r"\b" + T + r"\b", p.get("type") or "") for p in x["params"]))
def gives_t(T): return fns_with(lambda x: re.search(r"\b" + T + r"\b", x.get("ret") or ""))
def type_both(T, types):
    makers = gives_t(T); takers = takes_t(T)
    def seg(path, x, side):
        sg = None
        if types:
            ps = ", ".join(("{ … }" if simple(p.get("type") or p["name"]).startswith("{") else simple(p.get("type") or p["name"])) for p in x["params"])
            ret = simple(x.get("ret"))
            if not ret:
                h = x.get("hover") or ""
                ret = simple(h.rsplit("=>", 1)[1]).rstrip(")") if "=>" in h else "void"
        if side == "L":
            return (s("pun", "(") + ts(cut(ps, 30)) + s("pun", ")") + s("c", " → ") if types else []) + s("b", x["name"])
        return s("b", x["name"]) + (s("c", " → ") + ts(cut(ret, 24)) if types else [])
    L = [seg(p, x, "L") for p, x in makers]
    R = [seg(p, x, "R") for p, x in takers]
    return both(L, R, s("ty bold", T), lw=50)
screen("mapy-type-both", "A type, both ways, T on",
       "Model: who makes it on the left, who takes it on the right. With T on, the makers show what they take and the takers what they give, so the type sits in the middle of its own flow.",
       phead(s("ty bold", "Model"), "type in state.ts:152   made by 2, taken by 7", "both ways", hint="     T inputs and outputs   l opens") + type_both("Model", True),
       "Model  map · both ways · types", cursor="Model", trail="Model")

# size, on a folder: each file, how much it reaches outside itself
def folder_size(folder):
    files = collections.defaultdict(list)
    for i, n in N.items():
        if n["path"].startswith(CORE + folder) and not is_test(n["path"]): files[n["path"]].append(i)
    rows_ = []
    for p, fs in files.items():
        r = set()
        for i in fs: r |= reach(i)
        r = {i for i in r if N[i]["path"] != p}
        used = {c for i in fs for c in CALLERS[i] if N[c]["path"] != p and not is_test(N[c]["path"])}
        rows_.append((p, len(r), len(used)))
    rows_.sort(key=lambda t: -t[1])
    mx = max(t[1] for t in rows_)
    bw = 56
    out = [(s("", "   ") + s("", " " * 18) + s("c", "reaches outside itself") + s("", " " * (bw - 16)) + s("c", "used from outside"), ""), blank()[0]]
    for p, nr, nu in rows_:
        w = round(bw * nr / mx)
        r = s("", "   ") + s("fg", posixpath.basename(p).ljust(18)) + (s("bar", " " * w) if w else s("d3", "▏")) + s("c", f" {nr}")
        r += s("", " " * (bw + 28 - width(r))) + s("fd", str(nu))
        out.append((r, ""))
    return out
screen("mapy-folder-size", "A folder, size",
       "run/'s files by how much each reaches outside itself, with how many functions outside call into it. run.ts and update.ts reach the most; rules.ts, walkthroughs.ts and record.ts are the most leaned on.",
       phead(s("fg bold", "run/"), "folder in core/src   10 files", "size", hint="     l opens a file") + folder_size("run/"),
       "run/  map · size", cursor="run/", trail="run/")

# ── round three: the cells still blank, a file's and a type's ───────────
def ok(p): return p.startswith(CORE) and not is_test(p)
def where(p):
    """a folder's name as the tree writes it"""
    d = posixpath.dirname(short(p)) if p.startswith(CORE) else posixpath.dirname(p.replace("packages/", ""))
    return (d + "/") if d else "core/src/ files"

# tree on a file or folder: one rank down each level, as the tree on the left
# goes: a folder's folders, then their files, then the functions in them
def rank_tree(title_segs, inside, unit, opened=None, cap=4):
    """inside(p): the path is in the row; unit(p): the next rank's name for a path"""
    out = collections.OrderedDict()
    for i, n in N.items():
        if not ok(n["path"]) or not inside(n["path"]): continue
        for c, _, _ in n["calls"]:
            if c in N and ok(N[c]["path"]) and not inside(N[c]["path"]):
                out.setdefault(unit(N[c]["path"]), collections.OrderedDict()).setdefault(N[c]["path"], set()).add(N[c]["name"])
    order = sorted(out, key=lambda u: -sum(len(v) for v in out[u].values()))
    rows = [(s("", " ") + title_segs, "")]
    for j, u in enumerate(order):
        last = j == len(order) - 1
        files = out[u]
        n = sum(len(v) for v in files.values())
        r = s("c", " " + ("└─ " if last else "├─ ")) + s("fg", u)
        r += s("", " " * max(2, 34 - width(r))) + s("d3", f"{n} name" + ("s" if n != 1 else ""))
        rows.append((r, ""))
        pre = "   " if last else "│  "
        kids_ = list(files.items())
        if unit(kids_[0][0]) == kids_[0][0].rsplit("/", 1)[-1]:   # the unit is a file: its names
            names = sorted(next(iter(files.values())))
            shown = names[:cap]
            for k, nm in enumerate(shown):
                lk = k == len(shown) - 1 and len(names) <= cap
                rows.append((s("c", " " + pre + ("└─ " if lk else "├─ ")) + s("b", nm) + s("pun", "()"), ""))
            if len(names) > cap: rows.append((s("c", " " + pre + f"└─ ⋯ {len(names) - cap} more"), ""))
        else:                                                   # the unit is a folder: its files
            fl = sorted(files.items(), key=lambda kv: -len(kv[1]))
            shown = fl[:cap]
            for k, (f, nms) in enumerate(shown):
                lk = k == len(shown) - 1 and len(fl) <= cap
                r = s("c", " " + pre + ("└─ " if lk else "├─ ")) + s("fg", posixpath.basename(f))
                rows.append((r, ""))
                if f == opened:
                    pre2 = pre + ("   " if lk else "│  ")
                    nl = sorted(nms)
                    for m, nm in enumerate(nl):
                        rows.append((s("c", " " + pre2 + ("└─ " if m == len(nl) - 1 else "├─ ")) + s("b", nm) + s("pun", "()"), ""))
            if len(fl) > cap: rows.append((s("c", " " + pre + f"└─ ⋯ {len(fl) - cap} more"), ""))
    return rows

def dirname_of(p): return where(p)
RUNTS = CORE + "run/run.ts"
screen("mapz-file-tree", "A file, tree",
       "run.ts: the files its functions call into, then the functions it uses in each. One rank down a level, as the tree on the left goes: files, then functions, then their calls with l.",
       phead(s("fg bold", "run.ts"), "file in run/   1 function", "tree", hint="     T inputs and outputs   > < levels   l opens") +
       rank_tree(s("fg bold", "run.ts"), lambda p: p == RUNTS, lambda p: posixpath.basename(p)),
       "run.ts  map · tree", cursor="run.ts", trail="run.ts")
screen("mapz-folder-tree", "A folder, tree",
       "run/: the folders it calls into, then the files in each, then the functions (records.ts opened with l). One rank down a level, as the tree on the left goes.",
       phead(s("fg bold", "run/"), "folder in core/src   10 files", "tree", hint="     T inputs and outputs   > < levels   l opens") +
       rank_tree(s("fg bold", "run/"), lambda p: p.startswith(CORE + "run/"), where, opened=CORE + "storage/records.ts"),
       "run/  map · tree", cursor="run/", trail="run/")

fb2, ni2, no2 = folder_both("run/run.ts")
screen("mapz-file-both", "A file, both ways",
       f"run.ts: the {ni2} files that call into it on the left, the {no2} files it calls out to on the right, each with the names that cross. The same as a folder's.",
       phead(s("fg bold", "run.ts"), f"file in run/   called from {ni2} file" + ("s" if ni2 != 1 else "") + f", calls {no2}", "both ways", hint="     l opens a file") + fb2,
       "run.ts  map · both ways", cursor="run.ts", trail="run.ts")

# folders, both sides, for any row: who uses it by folder left, what it uses right
def folders_both(centre, sub, left, right, tests=0, tfiles=0, ccls="fg bold", word=("call", "calls")):
    def group(items):
        g = collections.OrderedDict()
        for path, nm in items:
            g.setdefault(where(path), collections.OrderedDict()).setdefault(posixpath.basename(path), [])
            if nm not in g[where(path)][posixpath.basename(path)]: g[where(path)][posixpath.basename(path)].append(nm)
        return collections.OrderedDict(sorted(g.items(), key=lambda kv: -sum(len(v) for v in kv[1].values())))
    def wrap(names, w=26):
        lines, cur = [], ""
        for nm in names:
            if cur and len(cur) + 2 + len(nm) > w: lines.append(cur); cur = nm
            else: cur = (cur + "  " + nm) if cur else nm
        return lines + [cur]
    L, R = group(left), group(right)
    def bsize(files): return sum(len(wrap(v)) for v in files.values()) + 3
    def bwidth(files, title):
        mf = max(len(x) for x in files)
        return max(mf + 4 + max(len(l) for v in files.values() for l in wrap(v)) + 4, len(title) + 8)
    rh = sum(bsize(R[d]) for d in R) + len(R) - 1
    lh = sum(bsize(L[d]) for d in L) + len(L) + (2 if tests else 0)
    H_ = max(rh, lh, 3)
    cv = Canvas(RW - 2, H_)
    mid = H_ // 2
    lw = max([bwidth(L[d], d) for d in L] + [len(f"⋯ {tests} in tests, {tfiles} files") + 2])
    cx = lw + 15
    cv.box(cx, mid - 1, len(centre) + 4, 3, "d3"); cv.put(cx + 2, mid, centre, ccls); cv.put(cx + 2, mid + 2, sub, "c")
    def draw(files, title, x, y, w):
        cv.box(x, y, w, bsize(files), "d3"); cv.put(x + 2, y, " " + title + " ", "fg bold")
        mf = max(len(f) for f in files)
        j = 0
        for f, v in files.items():
            cv.put(x + 2, y + 2 + j, f.ljust(mf + 2), "fd")
            for l in wrap(v):
                cv.put(x + 4 + mf, y + 2 + j, l, "b"); j += 1
    def lab(k): return f" {k} {word[0] if k == 1 else word[1]} "
    lys = []
    y = mid - lh // 2
    for d in L:
        w = bwidth(L[d], d); draw(L[d], d, 0, y, w)
        k = sum(len(v) for v in L[d].values())
        lys.append((y + 2, w, k)); y += bsize(L[d]) + 1
    if tests:
        tx = f"⋯ {tests} in tests, {tfiles} files"; cv.put(2, y, tx, "c"); lys.append((y, len(tx) + 2, 0))
    lbus = cx - 4
    for ay, w, k in lys:
        cv.h(w, lbus, ay, "c")
        if k: cv.put(w + 2, ay, lab(k), "o")
    if lys:
        cv.v(lbus, min([a for a, _, _ in lys] + [mid]), max([a for a, _, _ in lys] + [mid]), "c")
        cv.h(lbus, cx - 2, mid, "c"); cv.put(cx - 1, mid, "▶", "c")
    rbus = cx + len(centre) + 6
    bx = rbus + max([len(lab(sum(len(v) for v in R[d].values()))) for d in R] + [0]) + 5
    y = mid - rh // 2; tops = []
    if R: cv.h(cx + len(centre) + 4, rbus, mid, "c")
    for d in R:
        draw(R[d], d, bx, y, bwidth(R[d], d))
        ay = y + 2; tops.append(ay)
        k = sum(len(v) for v in R[d].values())
        cv.h(rbus, bx - 2, ay, "c"); cv.put(bx - 1, ay, "▶", "c")
        cv.put(rbus + 2, ay, lab(k), "o")
        y += bsize(R[d]) + 1
    if R: cv.v(rbus, min(tops + [mid]), max(tops + [mid]), "c")
    return cv.rows()

ins = [i for i, n in N.items() if n["path"] == RUNTS]
lt, rt, tc = [], [], set()
for i in ins:
    for c in CALLERS[i]:
        if N[c]["path"] == RUNTS: continue
        if is_test(N[c]["path"]): tc.add(c); continue
        lt.append((N[c]["path"], N[c]["name"] or "(top level)"))
    for k in kids(i):
        if N[k]["path"] != RUNTS and N[k]["path"].startswith("packages/"): rt.append((N[k]["path"], N[k]["name"]))
screen("mapz-file-folders", "A file, folders",
       "run.ts as a box: who calls into it on the left, by folder, tests folded to a count; the folders it calls into on the right. As a function's, with the file's functions together.",
       phead(s("fg bold", "run.ts"), "file in run/", "folders", hint="     > < levels   l opens a box") +
       folders_both("run.ts", "run/", lt, rt, len(tc), len({N[c]["path"] for c in tc})),
       "run.ts  map · folders", cursor="run.ts", trail="run.ts")

mk = [(CORE + p, x["name"]) for p, x in gives_t("Model")]
tk = [(CORE + p, x["name"]) for p, x in takes_t("Model")]
screen("mapz-type-folders", "A type, folders",
       "Model as a box: the functions that make it on the left, by folder; the functions that take it on the right. Both ways, gathered into folders.",
       phead(s("ty bold", "Model"), f"type in state.ts:152   made by {len(mk)}, taken by {len(tk)}", "folders", opts=TDISP, hint="     l opens a box") +
       folders_both("Model", "state.ts", mk, tk, ccls="ty bold", word=("function", "functions")),
       "Model  map · folders", cursor="Model", trail="Model")

# ── round four: what the user asked after round three ───────────────
for HEADS, nm, cap in (("in", "mapz-fn-folders-in", "Every arrow points at createRun: its callers on the left use it, the folders on the right are what it is built from."),
                       ("none", "mapz-fn-folders-none", "No arrowheads, as both ways draws it: callers left, what it calls right, the counts on the lines.")):
    screen(nm, "A function, folders, arrows " + HEADS, cap,
           phead(crh, "function in run/run.ts:33   called by 16, calls 17", "folders", hint="     > < levels   l opens a box") + fn_folders_both(ROOT),
           "createRun()  map · folders")
HEADS = "right"

# size, on a file: each of its functions, how much it reaches and how much it is used
def file_size(path):
    fs = [i for i, n in N.items() if n["path"] == path and n["name"]]
    rows_ = []
    for i in fs:
        used = {c for c in CALLERS[i] if not is_test(N[c]["path"])}
        rows_.append((N[i]["name"], len(reach(i)), len(used)))
    rows_.sort(key=lambda t: -t[1])
    mx = max(t[1] for t in rows_) or 1
    bw = 56
    out = [(s("", "   ") + s("", " " * 22) + s("c", "reaches") + s("", " " * (bw - 1)) + s("c", "used by"), ""), blank()[0]]
    for nm, nr, nu in rows_:
        w = round(bw * nr / mx)
        r = s("", "   ") + s("b", (nm + "()").ljust(22)) + (s("bar", " " * w) if w else s("d3", "▏")) + s("c", f" {nr}")
        r += s("", " " * (bw + 32 - width(r))) + s("fd", str(nu))
        out.append((r, ""))
    return out
screen("mapz-file-size", "A file, size",
       "update.ts's functions by how many functions each goes on to reach, with how many call it. As a function's size, for every function in the file.",
       phead(s("fg bold", "update.ts"), "file in run/   13 functions", "size", hint="     l opens") + file_size(CORE + "run/update.ts"),
       "update.ts  map · size", cursor="▸ update.ts", trail="update.ts")

# tree, on a type, with + on the Model box: its declaration opens under it
def type_graph_open():
    rows = type_graph()
    while rows and not rows[-1][0]: rows.pop()
    decl = open(os.path.join(SRC, "state.ts")).read().split("\n")[150:159]
    ind = 41
    # a line down from the box to what it opened
    out = []
    for j, (r, c) in enumerate(rows):
        if j >= 6:
            w = width(r)
            if w <= ind + 3: r = r + s("", " " * (ind + 3 - w)) + s("d3", "│")
            else:
                flat = "".join(tx for _, tx in r)
                if flat[ind + 3] == " ":
                    # put the bar into the gap
                    acc, nr = 0, []
                    for cl, tx in r:
                        if acc <= ind + 3 < acc + len(tx):
                            k = ind + 3 - acc
                            nr += [(cl, tx[:k]), ("d3", "│"), (cl, tx[k + 1:])]
                        else: nr.append((cl, tx))
                        acc += len(tx)
                    r = nr
        out.append((r, c))
    out.append((s("", " " * (ind + 3)) + s("d3", "│"), ""))
    out.append((s("", " " * (ind + 3)) + s("d3", "└ ") + s("ty bold", "Model") + s("c", "   type in state.ts:152"), ""))
    for k, line in enumerate(decl):
        n = 151 + k
        st = line.strip()
        body = (s("", line[:len(line) - len(line.lstrip())]) + s("c it", st)) if st.startswith(("/**", "//")) else ts(line, on="UserRecord" if "userRecord" in line else None)
        out.append((s("", " " * (ind + 5)) + s("d3", "│") + s("c", str(n).rjust(4)) + s("", "  ") + body, ""))
    return out
screen("mapz-type-tree-open", "A type, tree, + on Model",
       "+ on a box opens its declaration under it, as a type opens anywhere else. + on a name inside opens that one, - closes it.",
       phead(s("ty bold", "Model"), "type in state.ts:152   made by 2, taken by 7", "tree", opts=TDISP, hint="     + opens a type   > < levels   l opens") + type_graph_open(),
       "Model  map · tree", cursor="Model", trail="Model")

# size, on a type: A each field by how often it is read; B the files that use it most
def src_files():
    out = {}
    for dp, _, fns in os.walk(SRC):
        for f in fns:
            if f.endswith((".ts", ".tsx")) and not is_test(f):
                out[os.path.relpath(os.path.join(dp, f), SRC)] = open(os.path.join(dp, f)).read()
    return out
SF = src_files()
FIELDS = ["userRecord", "startRequests", "live", "held", "views"]
def bars(items, label_w, bw=56, cls="b"):
    mx = max(n for _, n, _ in items) or 1
    out = []
    for nm, n, rest in items:
        w = round(bw * n / mx)
        r = s("", "   ") + s(cls, nm.ljust(label_w)) + (s("bar", " " * w) if w else s("d3", "▏")) + s("c", f" {n}")
        if rest: r += s("", " " * (bw + label_w + 10 - width(r))) + s("d3", rest)
        out.append((r, ""))
    return out
def fields_size():
    items = []
    for f in FIELDS:
        per = collections.Counter({p: len(re.findall(r"\.\s*" + f + r"\b", txt)) for p, txt in SF.items()})
        per = {p: n for p, n in per.items() if n}
        top = sorted(per, key=lambda p: -per[p])[:3]
        items.append((f, sum(per.values()), ", ".join(top)))
    items.sort(key=lambda t: -t[1])
    return [(s("", "   ") + s("c", "each field, by how often it is read, and the files that read it most"), ""), blank()[0]] + bars(items, 16)
def files_size():
    items = []
    for p, txt in SF.items():
        n = len(re.findall(r"\bModel\b", txt)) + sum(len(re.findall(r"\bmodel\.\w+", txt)) for _ in [0])
        if p == "state.ts": n -= 1
        if n > 0: items.append((p, n, ""))
    items.sort(key=lambda t: -t[1])
    return [(s("", "   ") + s("c", "the files that use it, by how many times"), ""), blank()[0]] + bars(items[:16], 30, cls="fg")
for nm, cap, body, d in (("mapz-type-size-fields", "A type, size, by field", fields_size(), "by field"),
                      ("mapz-type-size-files", "A type, size, by file", files_size(), "by file")):
    screen(nm, cap, "Model, size: " + cap,
           phead(s("ty bold", "Model"), "type in state.ts:152   made by 2, taken by 7", d, opts=TDISP, hint="     l opens") + body,
           "Model  map · size", cursor="Model", trail="Model")

# ── the gallery ─────────────────────────────────────────────────────────
G = []
for k, (name, title, cap, body) in enumerate(SHOTS, 1):
    G.append(f"<h2><small>{k}</small>{H.escape(title)}</h2><p class='cap'>{H.escape(cap)}</p>{body}")
open("/tmp/seam-tree/v6/map-ideas.html", "w").write(
    "<!doctype html><html><head><meta charset='utf-8'><style>" + lib.SHOT_CSS.replace("width:1380px", "max-width:1380px") +
    " h2{color:#c0caf5;font-family:system-ui} .cap{color:#a9b1d6;font-family:system-ui}</style></head><body><main>" + "".join(G) + "</main></body></html>")
print("\n".join(n for n, *_ in SHOTS))
