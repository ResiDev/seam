# Types as data, drawn from real excalidraw data (/tmp/seam-types/mock.json,
# written by seam.types over the lab's copy). Three screens:
#   calls-typed   the call tree with what each function takes and gives
#   types-top     every repo type, the most travelled first
#   types-flow    one type: the functions that make it, and the ones that take it
import sys, json, os, html as H
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, code, blank, line, width, html_row, compose, W

D = json.load(open("/tmp/seam-types/mock.json"))
OUT = os.path.join(os.path.dirname(__file__), "..", "..")
LW, RW = 86, W - 86 - 1
SIG_AT = 36
HUES = {"element": "hcor", "excalidraw": "hre", "common": "hdemo", "math": "he2e"}

def pkg(path):
    p = path.split("/")
    return p[1] if p[0] == "packages" else p[0]

def bar(path):
    return s(HUES.get(pkg(path), "c"), "▎")

def base(path):
    return path.split("/")[-1]

def fname(n):
    if n["kind"] == "module": return s("fg", base(n["path"]))
    if n["kind"] == "component": return s("pun", "<") + s("ty", n["name"]) + s("pun", ">")
    if n["kind"] == "class": return s("ty", n["name"])
    return s("t" if n.get("test") else "b", n["name"]) + s("pun", "()")

def sig(pieces, lit=None, room=50):
    out = []
    for p in pieces:
        t = p["text"]
        if p.get("flow"):
            out += s("ty bold ul" if p["flow"] == lit else "ty", t)
        else:
            for tok in __import__("re").findall(r"[A-Za-z_$][\w$]*|[^A-Za-z_$]+", t):
                out += s("fd" if tok[0].isalpha() or tok[0] in "_$" else "pun", tok)
    # keep the return whole: cut what it takes first
    total = sum(len(t) for _, t in out)
    sep = next((i for i, (c, t) in enumerate(out) if t.startswith(") → ") or t == ")" and i + 1 < len(out) and out[i + 1][1].startswith(" → ")), None)
    if total > room - 1 and sep is not None:
        after = out[sep:]
        left = room - 2 - sum(len(t) for _, t in after)
        if left >= 6:
            w, kept = 0, []
            for c, t in out[:sep]:
                if w + len(t) > left:
                    kept.append((c, t[:left - w])); break
                kept.append((c, t)); w += len(t)
            return kept + [("c", "…")] + after
    w = 0; clipped = []
    for c, t in out:
        if w + len(t) > room - 1:
            clipped.append((c, t[:room - 1 - w])); clipped.append(("c", "…")); return clipped
        clipped.append((c, t)); w += len(t)
    return clipped

def status(l, r):
    return l, r

def tabs(names, on):
    r = s("", "  ")
    for t in names:
        r += s("tab bold" if t.startswith(on) else "c", f" {t} ") + s("", "   ")
    return r

def headrows(r1, r2):
    return [(line([(r1, 0)], W), ""), (r2, ""), (s("d3", "─" * W), "")]

def takes_gives(sigd):
    rows = []
    ps = sigd.get("params") or []
    nw = max([len(p["name"]) for p in ps] + [4])
    for i, p in enumerate(ps):
        rows.append((s("c", " takes " if i == 0 else "       ") + s("fg", p["name"].ljust(nw)) + s("", "  ") + ts(p["type"]), ""))
    rows.append((s("c", " gives ") + s("", " " * (nw + 2) if ps else "") + ts(sigd.get("ret") or "void"), ""))
    return rows

# ── calls, typed ────────────────────────────────────────────────────────
def calls_typed():
    a = D["anchor"]
    r1 = s("c", " Calls › ") + s("b bold", a["name"] + "()") + s("c", "   function in packages/") + s("hcor bold", "element") + s("c", "/src/bounds.ts:305")
    r2 = tabs([f"Calls {len(D['kids'])}", "Called by 3"], "Calls")
    hd = headrows(r1, r2)
    T = [(line([(s("c", "takes → gives"), SIG_AT)], LW), "")]
    head = bar(a["path"]) + s("c", "─ ") + fname(a)
    T.append((line([(head, 0), (sig(a["pieces"], room=LW - SIG_AT), SIG_AT)], LW), ""))
    kids = D["kids"]
    for i, k in enumerate(kids):
        last = i == len(kids) - 1
        g = s("c", "└ " if last else "├ ") + s("c", "▸ " if k["below"] else "  ")
        nm = bar(k["path"]) + s("", " ") + g + fname(k) + (s("d3", " local") if not k["exported"] else [])
        cls = "sel" if k["name"] == "getElementShape" else ""
        T.append((line([(nm, 0), (sig(k["pieces"], room=LW - SIG_AT), SIG_AT)], LW), cls))
    # the right: the function under the cursor, itself, with what it takes and gives
    sel = next(k for k in kids if k["name"] == "getElementShape")
    Rr = [(s("b bold", " getElementShape()") + s("c", "   function in element/src/shape.ts"), ""), blank()[0]]
    Rr += takes_gives({"params": [{"name": "element", "type": "ExcalidrawElement"}, {"name": "elementsMap", "type": "ElementsMap"}],
                       "ret": "GeometricShape<Point>"})
    Rr += blank()
    src = open("/home/alex/.config/nvim/seam.nvim/lab/excalidraw/packages/element/src/shape.ts").read().split("\n")
    at = next(i for i, l in enumerate(src) if "export const getElementShape" in l)
    Rr += code(src[at:at + 26], at + 1, gutter=4)
    return compose(hd, [(T + blank(40 - len(T)), LW), (Rr, RW)], "getElementLineSegments()  ›  getElementShape()   calls  1 of 16",
                   "j/k row  t its types  T counts  <CR> anchor  K back")

# ── types, the most travelled first ─────────────────────────────────────
def types_top():
    r1 = s("c", " Types") + s("c", f"   {D['nflows']} types of the repo in what its functions take and give, the most travelled first")
    hd = headrows(r1, [])
    T = [(line([(s("c", "functions"), 38), (s("c", "make"), 49), (s("c", "take"), 56), (s("c", "declared in"), 62)], LW), "")]
    for i, t in enumerate(D["list"][:36]):
        nm = bar(t["path"]) + s("", " ") + s("ty", t["name"]) + (s("c", f" ×{t['ndecl']}") if t["ndecl"] > 1 else [])
        cls = "sel" if t["name"] == "Bounds" else ""
        T.append((line([(nm, 0), (s("fd", str(t["n"]).rjust(4)), 43), (s("fd", str(t["gives"]).rjust(3)), 50),
                        (s("fd", str(t["takes"]).rjust(3)), 57), (s("c", base(t["path"]) + ":" + str(t["line"])), 62)], LW), cls))
    dl = D["declsrc"]
    f = D["flow"]
    Rr = [(s("ty bold", " Bounds") + s("c", "   type in common/src/bounds.ts:4"), ""), blank()[0]]
    Rr += code(dl[f["decl"]["line"] - 1:f["decl"]["end_line"]], f["decl"]["line"], gutter=4)
    Rr += blank()
    Rr += [(s("c", f" made by {len(f['gives'])}  ·  taken by {len(f['takes'])}  ·  ") + s("fd", "l") + s("c", " its flow"), "")]
    return compose(hd, [(T + blank(40 - len(T)), LW), (Rr, RW)], "types  Bounds  9 of 347", "j/k row  l its flow  / a type  <Tab> order  K back")

# ── one type's flow ─────────────────────────────────────────────────────
def types_flow():
    f = D["flow"]
    r1 = s("c", " Types › ") + s("ty bold", f["name"]) + s("c", "   type in packages/") + s("hdemo bold", "common") + s("c", "/src/bounds.ts:4")
    r2 = s("c", f"   through {f['n']} functions:  made by ") + s("fg", str(len(f['gives']))) + s("c", "  ·  taken by ") + s("fg", str(len(f['takes'])))
    hd = headrows(r1, r2)
    T = []
    def section(title, rows, mark, total):
        T.append((s("fg bold", " " + title) + s("c", f"  {total}"), ""))
        for r in rows:
            nm = bar(r["path"]) + s("", " ") + fname(r) + (s("c", " new") if r.get("new") else [])
            T.append((line([(nm, 0), (sig(r["pieces"], lit=f["name"], room=LW - SIG_AT), SIG_AT)], LW), "sel" if r["name"] == mark else ""))
    section("made by", f["gives"], "getElementBounds", len(f["gives"]))
    T.append(blank()[0])
    section("taken by", f["takes"][:40 - len(T) - 1], None, len(f["takes"]))
    # the right: the function under the cursor, the type lit where it is named
    sel = next(r for r in f["gives"] if r["name"] == "getElementBounds")
    src = open("/home/alex/.config/nvim/seam.nvim/lab/excalidraw/" + sel["path"]).read().split("\n")
    at = sel["line"] - 1
    Rr = [(s("b bold", " getElementBounds()") + s("c", "   function in element/src/" + base(sel["path"]) + ":" + str(sel["line"])), ""), blank()[0]]
    Rr += takes_gives({"params": [{"name": "element", "type": "ExcalidrawElement"}, {"name": "elementsMap", "type": "ElementsMap"},
                                  {"name": "nonRotated", "type": "boolean"}], "ret": "Bounds"})
    Rr += blank()
    Rr += code(src[at:at + 24], at + 1, ul=("Bounds",), gutter=4)
    return compose(hd, [(T + blank(40 - len(T)), LW), (Rr, RW)], "Bounds  made by  1 of 22",
                   "j/k row  t its types  <CR> its calls  <Tab> next section  K back")

SHOT = lib.SHOT_CSS
for name, fn in (("calls-typed", calls_typed), ("types-top", types_top), ("types-flow", types_flow)):
    open(f"/tmp/seam-types/{name}.html", "w").write(
        f"<!doctype html><html><head><meta charset='utf-8'><style>{SHOT}</style></head><body>{fn()}</body></html>")
