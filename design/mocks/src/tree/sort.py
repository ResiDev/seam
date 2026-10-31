# The tree's order: by folder (the tree), or a flat list most used first or
# most calling first, as today's explorer sorts. Mocked on raf.
#   python3 sort.py <treesitter.json> <raf core src>  -> /tmp/seam-tree/v6/tree-sort-*.html
import sys, os, json, collections
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose, width
lib.W = W = 178
TSX = json.load(open(sys.argv[1]))
N = {n["id"]: n for n in TSX["nodes"]}
SRC = sys.argv[2]
LW = 50
RW = W - LW - 1
HUE = {"core": "core", "react": "react", "demo": "demo"}
def test(p): return ".test." in p or "/test/" in p or p.startswith("e2e/") or ".perf." in p
def pkg(p):
    parts = p.split("/")
    return parts[1] if len(parts) > 1 else parts[0]
USED = collections.defaultdict(set)
for i, n in N.items():
    for c, _, _ in n["calls"]:
        if c in N and not test(n["path"]): USED[c].add(i)
def calls(i): return len({c for c, _, _ in N[i]["calls"] if c in N})
FNS = [i for i, n in N.items() if n["name"] and n["kind"] != "module" and not test(n["path"])]

def listing(by):
    key = (lambda i: (-len(USED[i]), N[i]["name"])) if by == "used" else (lambda i: (-calls(i), N[i]["name"]))
    order = sorted(FNS, key=key)[:34]
    lit_u = "fg bold" if by == "used" else "c"
    lit_c = "fg bold" if by == "calls" else "c"
    rows = [blank()[0], (s("", " " * 32) + s(lit_u, "used by") + s("", "   ") + s(lit_c, "calls"), "")]
    for j, i in enumerate(order):
        n = N[i]
        p = pkg(n["path"])
        bar = lib.bar(HUE[p]) if p in HUE else s("", " ")
        r = s("", " ") + bar + s("", " ") + s("b", n["name"]) + s("pun", "()")
        r += s("", " " * max(1, 36 - width(r))) + s(lit_u if by == "used" else "c", str(len(USED[i])).rjust(3))
        r += s("", " " * 6) + s(lit_c if by == "calls" else "c", str(calls(i)).rjust(3))
        rows.append((r, "sel" if j == 0 else ""))
    return rows, order[0]

def pane(i):
    n = N[i]
    rel = n["path"].replace("packages/core/src/", "")
    r = s("", " ")
    for t in ["Code", "Types", "Built from", "Used by", "Map", "Changed"]: r += s("tab bold" if t == "Code" else "c", f" {t} ") + s("", "  ")
    rows = [(s("", " ") + s("b bold", n["name"]) + s("pun", "()") + s("c", f"   function in {rel}:{n['line']}   used by {len(USED[i])}"), ""), blank()[0], (r, ""), blank()[0]]
    src = open(os.path.join(SRC, rel)).read().split("\n")
    rows += lib.code(src[n["line"] - 1:n["end_line"]], n["line"])
    return rows

for by, title in (("used", "most used first"), ("calls", "most calling first")):
    left, top = listing(by)
    right = pane(top)
    hd = [(s("c", " Seams   ") + s("fg bold", title), ""), (s("d3", "─" * W), "")]
    n = max(len(left), len(right)) + 1
    nxt = "most calling first" if by == "used" else "by folder"
    lib.write_shot(f"tree-sort-{by}", compose(hd, [(left + blank(n - len(left)), LW), (right + blank(n - len(right)), RW)],
                                              title, f"s {nxt}   / search   <Tab> view   J go"))
print("ok")
