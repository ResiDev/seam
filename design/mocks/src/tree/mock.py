# The tree's own surface, mocked on raf: what a row shows beside its name,
# how a call says where it lives, what an opened function shows, a file's rows.
#   python3 mock.py <treesitter.json> <sigs.json> <raf core src>  -> /tmp/seam-tree/v6/tree-*.html
import sys, os, json, re, collections, posixpath
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose, width
lib.W = W = 178
TSX = json.load(open(sys.argv[1]))
N = {n["id"]: n for n in TSX["nodes"]}
S = json.load(open(sys.argv[2]))
SRC = sys.argv[3]
CORE = "packages/core/src/"
SIG = {}
for f in S["files"]:
    for x in f["fns"]: SIG[(CORE + f["path"], x["name"])] = x
CALLERS = collections.defaultdict(set)
for i, n in N.items():
    for c, _, _ in n["calls"]: CALLERS[c].add(i)
def kids(i):
    out = []
    for c, _, _ in sorted(N[i]["calls"], key=lambda t: t[1]):
        if c in N and c not in out: out.append(c)
    return out
def byname(nm, path=None): return next(i for i, n in N.items() if n["name"] == nm and (path is None or path in n["path"]))
def pkg(p): return p.split("/")[1] if p.startswith("packages/") else None

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
def sig(i):
    x = SIG.get((N[i]["path"], N[i]["name"]))
    if not x: return None
    def part(p):
        t = simple(p.get("type") or p["name"])
        return "{ … }" if t.startswith("{") else t
    takes = cut(", ".join(part(p) for p in x["params"]), 30)
    ret = simple(x.get("ret"))
    if not ret:
        h = x.get("hover") or ""
        ret = simple(h.rsplit("=>", 1)[1]).rstrip(")") if "=>" in h else "void"
        if ret.count("{") != ret.count("}") or len(ret) > 24: ret = "{ … }"
    return takes, cut(ret, 22)

ROOT = byname("createRun")
WR = byname("WaymarkRoot")

# ── a row: (depth, segments, kind, id) ──────────────────────────────────
def fn_name(i, home, where):
    n = N[i]
    nm = s("b", n["name"]) + s("pun", "()")
    other_file = n["path"] != home
    other_pkg = pkg(n["path"]) != pkg(home)
    if where == "a":
        if other_pkg: return lib.bar(pkg(n["path"])) + nm
        if other_file: return [(c + " ul", t) for c, t in nm]
        return nm
    if where == "b":
        return nm if other_file else [("d3", t) for _, t in nm]
    return nm

def build(where="a", flow=False, kept="dim", open_update=True):
    R = []
    def add(d, segs, kind="", i=None, note=None): R.append((d, segs, kind, i, note))
    add(0, s("fg", "packages/"))
    add(1, s("hcor", "core/src/"))
    add(2, s("fg", "▸ checklists/"))
    add(2, s("fg", "run/"))
    add(3, s("fg", "▸ page.ts"))
    add(3, s("fg", "run.ts"))
    add(4, s("b", "createRun") + s("pun", "()"), "fn", ROOT)
    home = N[ROOT]["path"]
    if flow:
        for d, segs, i in flow_rows(ROOT): add(5 + d, segs, "fn" if i else "", i, home if i else None)
    else:
        for k in kids(ROOT):
            add(5, fn_name(k, home, where), "fn", k, home)
    if open_update:
        add(3, s("fg", "update.ts"))
        fs = sorted([i for i, n in N.items() if n["path"] == CORE + "run/update.ts"], key=lambda i: N[i]["line"])
        ex = [i for i in fs if N[i]["exported"]]
        kp = [i for i in fs if not N[i]["exported"]]
        for i in ex: add(4, s("b", N[i]["name"]) + s("pun", "()"), "fn", i)
        if kept == "dim":
            for i in kp: add(4, s("c", N[i]["name"] + "()"), "fn", i)
        else:
            add(4, s("c", f"▸ {len(kp)} kept to itself"))
    else:
        add(3, s("fg", "▸ update.ts"))
    add(2, s("fg", "▸ storage/"))
    add(1, s("hre", "react/src/"))
    add(2, s("fg", "WaymarkRoot.tsx"))
    add(3, s("b", "WaymarkRoot") + s("pun", "()"), "fn", WR)
    for k in kids(WR): add(4, fn_name(k, N[WR]["path"], where), "fn", k, N[WR]["path"])
    add(2, s("fg", "▸ RunView.tsx"))
    return R

# createRun's calls under the closures and ifs they sit in (as mapx-skeleton)
def flow_rows(root):
    lines = open(os.path.join(SRC, "run/run.ts")).read().split("\n")
    n0, n1 = N[root]["line"], N[root]["end_line"]
    by = {N[k]["name"]: k for k in kids(root)}
    opener = re.compile(r"^(\s*)(?:(?:const|let) (\w+)(?::[^=]+)? = (?:\([^)]*\)|\w+) =>|function (\w+)\(([^)]*)\)|(\w+): (?:\([^)]*\)|\w+) =>|(if) \((.*?)\)(?= )|(\w+): on\()")
    stack, out, last, seen = [], [], (), set()
    for ln in range(n0, n1):
        src = lines[ln]
        ind = len(src) - len(src.lstrip())
        while stack and ind <= stack[-1][0] and not src.strip().startswith(("}", ")")):
            stack.pop()
        while stack and ind <= stack[-1][0] and src.strip().startswith(("}", "})", "},", "};")):
            stack.pop(); break
        m = opener.match(src)
        found = [m2.group(1) for m2 in re.finditer(r"\b(\w+)\(", src) if m2.group(1) in by]
        if m and ln > n0:
            label = m.group(2) or m.group(3) or m.group(5) or m.group(8)
            stack.append((ind, "if " + cut(m.group(7), 30) if m.group(6) else label))
        for f in found:
            ctx = tuple(k for _, k in stack)
            for d in range(len(ctx)):
                if d >= len(last) or last[d] != ctx[d]:
                    k = ctx[d]
                    lab = s("m it", "if ") + ts(k[3:]) if k.startswith("if ") else s("c", k + " ⇒")
                    out.append((d, lab, None))
            i = by[f]
            out.append((len(ctx), fn_name(i, N[root]["path"], "a"), i))
            last = ctx
    return out

def tree_rows(R, cols, cursor, lw):
    out = [blank()[0]]
    lit = False
    for d, segs, kind, i, note in R:
        r = s("", "  " + "  " * d) + segs
        if kind == "fn" and i is not None and cols in ("counts", "types"):
            col = lw - 2 - (34 if cols == "types" else 22)
            if cols == "counts":
                ub = len(CALLERS[i]); cl = len(kids(i))
                extra = s("c", f"used by {ub}".ljust(12)) + s("c", f"calls {cl}")
            else:
                sg = sig(i)
                extra = (s("pun", "(") + ts(sg[0]) + s("pun", ")") + s("c", " → ") + ts(sg[1])) if sg else []
                col = max(width(r) + 2, 34)
            if cols == "types": r += s("", " " * max(2, col - width(r))) + extra
            else: r += s("", " " * max(2, col - width(r))) + extra
        if cols == "file" and kind == "fn" and note and N[i]["path"] != note:
            p = N[i]["path"].replace(CORE, "").replace("packages/", "")
            r += s("", " " * max(2, 26 + 2 * d - width(r) + 8)) + s("d3", p)
        on = i == cursor and d == 4 and not lit
        lit = lit or on
        out.append((r, "sel" if on else ""))
    return out

def pane(rw):
    rows = [(s("", " ") + s("b bold", "createRun") + s("pun", "()") + s("c", "   function in run/run.ts:33"), ""), blank()[0]]
    r = s("", " ")
    for t in ["Code", "Types", "Built from", "Used by", "Map", "Changed"]: r += s("tab bold" if t == "Code" else "c", f" {t} ") + s("", "  ")
    rows += [(r, ""), blank()[0]]
    src = open(os.path.join(SRC, "run/run.ts")).read().split("\n")
    rows += lib.code(src[32:60], 33)
    return rows

def screen(name, R, cols, lw, status):
    hd = [(s("c", " Seams › ") + s("fg bold", "createRun()"), ""), (s("d3", "─" * W), "")]
    left = tree_rows(R, cols, ROOT, lw)
    right = pane(W - lw - 1)
    n = max(len(left), len(right)) + 1
    lib.write_shot(name, compose(hd, [(left + blank(n - len(left)), lw), (right + blank(n - len(right)), W - lw - 1)],
                                 status, "T beside the name   l open   h close   <Tab> view   J go"))

screen("tree-where-a", build("a"), "names", 46, "createRun()")
screen("tree-where-b", build("b"), "names", 46, "createRun()")
screen("tree-where-c", build("c"), "file", 62, "createRun()")
screen("tree-cols-counts", build("a"), "counts", 66, "createRun()   T: used by and calls")
screen("tree-cols-types", build("a"), "types", 92, "createRun()   T: takes and gives")
screen("tree-flow", build("a", flow=True, open_update=False), "names", 56, "createRun()")
screen("tree-file-kept", build("a", kept="row"), "names", 46, "createRun()")
print("ok")
