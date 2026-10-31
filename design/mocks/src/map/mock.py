# The Map view, mocked on raf core: calls from seam's treesitter index
# (.proto/treesitter.json), signatures as written (sigs.json, extract.lua),
# imports from sigs.json.
#   python3 mock.py <treesitter.json> <sigs.json>   -> /tmp/seam-tree/v6/map-*.html
import sys, os, json, re, posixpath
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose
lib.W = W = 178
TSX = json.load(open(sys.argv[1]))
N = {n["id"]: n for n in TSX["nodes"]}
S = json.load(open(sys.argv[2]))
SIG = {}
for f in S["files"]:
    for x in f["fns"]: SIG[("packages/core/src/" + f["path"], x["name"])] = x
CORE = "packages/core/src/"

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

def simple(t):
    t = re.sub(r"/\*\*.*?\*/", "", t or "")
    return re.sub(r"\s+", " ", unwrap(t)).strip()

def cut(t, w): return t if len(t) <= w else t[:w - 1] + "…"

def sig(node, w=34):
    x = SIG.get((node["path"], node["name"]))
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

ROOT = next(i for i, n in N.items() if n["name"] == "createRun")
HOME = N[ROOT]["path"]

def name_seg(i, seen=False):
    n = N[i]
    c = "b"
    if n["path"] != HOME: c += " ul"
    if seen: c = "d3"
    return s(c, n["name"])

CAP = 3
def tabs(have, on):
    r = s("", " ")
    for t in have:
        r += s("tab bold" if t == on else "c", f" {t} ") + s("", "  ")
    return (r, "")
VIEWS = ["Code", "Types", "Built from", "Used by", "Map", "Changed"]

def pane_head(title, rest, display, levels):
    return [(s("", " ") + title + s("c", "   " + rest), ""), blank()[0], tabs(VIEWS, "Map"),
            (s("", " ") + s("c", "display  ") + s("fg", display) + s("c", f"   {levels} levels   > more   < fewer   l opens a branch"), ""), blank()[0]]

# ── A. left to right ────────────────────────────────────────────────────
def draw_a():
    rows = []
    rootw = len(N[ROOT]["name"])
    first = True
    for k in kids(ROOT):
        ks = kids(k)
        lead = s("b bold", N[ROOT]["name"]) if first else s("", " " * rootw)
        first = False
        left = lead + s("c", " → ") + name_seg(k)
        if not ks:
            rows.append((s("", " ") + left, "")); continue
        pad = 22 - len(N[k]["name"])
        for j, g in enumerate(ks[:CAP]):
            l = left if j == 0 else s("", " " * (rootw + 3 + len(N[k]["name"])))
            rows.append((s("", " ") + l + s("", " " * pad) + s("c", " → ") + name_seg(g), ""))
        if len(ks) > CAP:
            rows.append((s("", " " * (rootw + 4 + len(N[k]["name"]) + pad)) + s("c", f" ⋯ {len(ks) - CAP} more"), ""))
    return rows

# ── B. an indented tree of signature lines ──────────────────────────────
def sig_row(i, depth, seen=False, on=False):
    n = N[i]
    sg = sig(n)
    r = s("", " " + "   " * depth)
    if sg:
        r += s("pun", "(") + ts(sg[0]) + s("pun", ")") + s("c", " → ")
    r += name_seg(i, seen) if depth else s("b bold", n["name"])
    if sg: r += s("c", " → ") + ts(sg[1])
    return (r, "vis" if on else "")

def draw_b(levels, cursor=None):
    rows = []
    def walk(i, depth, path):
        rows.append(sig_row(i, depth, on=i == cursor and depth > 0))
        if depth >= levels: return
        ks = kids(i)
        cap = len(ks) if depth == 0 else CAP
        for k in ks[:cap]:
            if k in path:
                rows.append(sig_row(k, depth + 1, seen=True)); continue
            walk(k, depth + 1, path | {k})
        if len(ks) > cap:
            rows.append((s("", " " + "   " * (depth + 1)) + s("c", f"⋯ {len(ks) - cap} more"), ""))
    walk(ROOT, 0, {ROOT})
    return rows

# ── C. columns, the cursor in one filling the next ──────────────────────
def draw_c(w):
    cw = 30
    c1 = kids(ROOT)
    on1 = next(k for k in c1 if N[k]["name"] == "createLink")
    c2 = kids(on1)
    on2 = next(k for k in c2 if N[k]["name"] == "loadFrom")
    c3 = kids(on2)
    cols = [[(N[ROOT]["name"], ROOT)], [(N[k]["name"], k) for k in c1], [(N[k]["name"], k) for k in c2], [(N[k]["name"], k) for k in c3]]
    ons = [ROOT, on1, on2, None]
    rows = []
    for r in range(max(len(c) for c in cols)):
        line = s("", " ")
        for ci, col in enumerate(cols):
            if r < len(col):
                nm, i = col[r]
                seg = name_seg(i) if ci else s("b bold", nm)
                more = len(kids(i))
                cell = seg + (s("c", f"  {more} ›") if more else [])
                cls = "vis" if i == ons[ci] else ""
                cell = [(c + (" " + cls if cls else ""), t) for c, t in cell]
                line += cell + s("", " " * (cw - lib.width(cell)))
            else:
                line += s("", " " * cw)
        rows.append((line, ""))
    rows += [blank()[0], (s("d3", " " + "─" * (w - 3)), ""), sig_row(on2, 0)]
    return rows

LW = 44
def tree_left(cursor="createRun()"):
    rows = [blank()[0]]
    T = [("packages/", 0, "fg"), ("core/src/", 1, "hcor"), ("▸ checklists/", 2, "fg"), ("run/", 2, "fg"), ("▸ page.ts", 3, "fg"),
         ("run.ts", 3, "fg"), ("createRun()", 4, "b"), ("▸ update.ts", 3, "fg"), ("▸ storage/", 2, "fg"), ("state.ts", 2, "fg"),
         ("Model", 3, "ty"), ("Msg", 3, "ty")]
    for t, d, c in T:
        rows.append((s("", "  " + "  " * d) + s(c, t), "sel" if t == cursor else ""))
    return rows

def screen(name, right, status, cursor="createRun()", trail="createRun()"):
    hd = [(s("c", " Seams › ") + s("fg bold", trail), ""), (s("d3", "─" * W), "")]
    left = tree_left(cursor)
    n = max(len(left), len(right)) + 1
    lib.write_shot(name, compose(hd, [(left + blank(n - len(left)), LW), (right + blank(n - len(right)), W - LW - 1)],
                                 status, "<Tab> view   <C-Tab> display   > < levels   l open   J go"))

RW = W - LW - 1
crh = s("b bold", "createRun") + s("pun", "()")
crr = "function in packages/core/src/run/run.ts:33   calls 17"
screen("map-a", pane_head(crh, crr, "calls", 2) + draw_a(), "createRun()  map · calls")
screen("map-b", pane_head(crh, crr, "calls", 2) + draw_b(1 + 1), "createRun()  map · calls")
screen("map-c", pane_head(crh, crr, "calls", 4) + draw_c(RW), "createRun()  map · calls")
screen("map-three", pane_head(crh, crr, "calls", 3) + draw_b(3), "createRun()  map · calls")

# ── a file: what it imports, then theirs ────────────────────────────────
IMP = {}
for f in S["files"]:
    out = []
    for im in f.get("imports", []):
        fr = im["from"]
        if not fr.startswith("."): continue
        p = posixpath.normpath(posixpath.join(posixpath.dirname(f["path"]), fr)) + ".ts"
        out.append((p, im.get("names") or []))
    IMP[f["path"]] = out

def draw_file(path, levels):
    rows = []
    def walk(p, depth, path_seen):
        names = None
        for q, ns in IMP.get(path_seen[-2] if len(path_seen) > 1 else "", []):
            if q == p: names = ns
        r = s("", " " + "   " * depth) + s("fg bold" if depth == 0 else "fg", p)
        if names: r += s("c", "   " + cut(", ".join(names), 60))
        rows.append((r, ""))
        if depth >= levels: return
        merged = {}
        for q, ns in IMP.get(p, []): merged.setdefault(q, []).extend(ns)
        ks = list(merged)
        cap = len(ks) if depth == 0 else CAP
        for q in ks[:cap]:
            if q in path_seen:
                rows.append((s("", " " + "   " * (depth + 1)) + s("d3", q), "")); continue
            walk(q, depth + 1, path_seen + [q])
        if len(ks) > cap: rows.append((s("", " " + "   " * (depth + 1)) + s("c", f"⋯ {len(ks) - cap} more"), ""))
    walk(path, 0, [path])
    return rows

screen("map-file", pane_head(s("fg bold", "run/run.ts"), "file in packages/core/src/run/   imports from 17 files", "imports", 2) + draw_file("run/run.ts", 2),
       "run/run.ts  map · imports", cursor="run.ts", trail="run/run.ts")

# ── a type: who makes it, who takes it, and on from what they give ──────
def fns_with(pred):
    out = []
    for f in S["files"]:
        if f["path"].startswith("test/"): continue
        for x in f["fns"]:
            if pred(x): out.append((f["path"], x))
    return out
def takes_t(T): return fns_with(lambda x: any(re.search(r"\b" + T + r"\b", p.get("type") or "") for p in x["params"]))
def gives_t(T): return fns_with(lambda x: re.search(r"\b" + T + r"\b", x.get("ret") or ""))
def srow(path, x, depth, seen=False):
    takes = cut(", ".join(("{ … }" if simple(p.get("type") or p["name"]).startswith("{") else simple(p.get("type") or p["name"])) for p in x["params"]), 40)
    ret = simple(x.get("ret")) if x.get("ret") else "{ … }"
    nm = s("d3" if seen else "b ul" if path != "state.ts" else "b", x["name"])
    return (s("", " " + "   " * depth) + s("pun", "(") + ts(takes) + s("pun", ")") + s("c", " → ") + nm + s("c", " → ") + ts(cut(ret, 30)), "")

def draw_type(T):
    rows = [(s("", " ") + s("ty bold", T), ""), blank()[0], (s("", "   ") + s("c", "made by"), "")]
    for p, x in gives_t(T): rows.append(srow(p, x, 2))
    rows += [blank()[0], (s("", "   ") + s("c", "taken by"), "")]
    seen = set()
    for p, x in takes_t(T):
        rows.append(srow(p, x, 2))
        ret = simple(x.get("ret") or "")
        m = re.match(r"[A-Z]\w*", ret)
        if m and m.group(0) != T:
            R = m.group(0)
            if R in seen:
                rows.append((s("", "         ") + s("d3", R + " taken by, above"), "")); continue
            seen.add(R)
            nxt = [(q, y) for q, y in takes_t(R) if y["name"] != x["name"]]
            for q, y in nxt[:CAP]: rows.append(srow(q, y, 3))
            if len(nxt) > CAP: rows.append((s("", "         ") + s("c", f"⋯ {len(nxt) - CAP} more take {R}"), ""))
    return rows

screen("map-type", pane_head(s("ty bold", "Model"), "type in packages/core/src/state.ts:152   made by 2, taken by 7", "made and taken", 2) + draw_type("Model"),
       "Model  map", cursor="Model", trail="Model")
print("ok")
