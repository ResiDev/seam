import sys, json
sys.path.insert(0, "/tmp/seam-tree/v2"); sys.path.insert(0, "/tmp/seam-tree/v2/data")
import lib
from lib import s, ts, code, bar, blank, line, width, html_row, W
from graphq import D, E, find, reach
from collections import defaultdict

RAF = "/home/alex/Work/libs/raf-run-redesign/"
def src(path, a, b):
    ls = open(RAF + path).read().split("\n")
    return [(n, ls[n - 1]) for n in range(a, b + 1)]

callers = defaultdict(set)
for a, es in E.items():
    for t, l in es: callers[t].add(a)
def kids(n):
    out = {}
    for t, l in E.get(n, []): out.setdefault(t, []).append(l)
    return out
below = lambda n: len(reach(n)) - 1
short = lambda p: p.split("src/")[-1]

LW = 86
RW = W - LW - 1
C_BELOW, C_USED, C_FILE, C_LINE = 40, 48, 56, 78

def head(name, kind, path, ln, right):
    r1 = s("c", " Seams › ") + s("b bold" if kind == "function" else "ty bold", name) + s("c", f"   {kind} in packages/") + s("hcor bold", "core") + s("c", f"/src/{path}:{ln}")
    r1 = line([(r1, 0), (s("c", right), W - len(right) - 1)], W)
    r2 = s("", "  ") + s("c", " Built from ") + s("", "   ") + s("c", " Used by ") + s("", "   ") + s("tab bold", " Calls ")
    return [(r1, ""), (r2, ""), (s("d3", "─" * W), "")]

def colhead(a="below", b="used by", c="file", d="line"):
    return (line([(s("c", a.rjust(5)), C_BELOW - 1), (s("c", b), C_USED - 1), (s("c", c), C_FILE), (s("c", d), C_LINE)], LW), "")

def trow(glyph, fold, name_segs, ln="", file="", bel=None, used=None, note=None, cls=""):
    r = bar("core") + s("", " ") + s("c", glyph) + s("c", (fold + " ") if fold else "  ") + name_segs
    cells = [(r, 0)]
    if bel is not None: cells.append((s("fd", str(bel).rjust(4)), C_BELOW))
    if used is not None: cells.append((s("fd", str(used).rjust(3)), C_USED))
    if file: cells.append((file if isinstance(file, list) else s("c", file), C_FILE))
    if note: cells.append((note, C_FILE))
    if ln: cells.append((s("c", ln), C_LINE))
    return (line(cells, LW), cls)

fn = lambda n: s("b", n) + s("pun", "()")

def node_row(t, ls, glyph, parent_path, opened=False, cls="", seen=None):
    d = D[t]; b = below(t)
    nm = fn(d["name"])
    if len(ls) > 1: nm += s("c", f" ×{len(ls)}")
    if d["exported"] is False: nm += s("d3", " local")
    fold = "▾" if opened else ("▸" if b else "")
    file = "" if d["path"] == parent_path else d["path"].rsplit("/", 1)[-1]
    if seen:
        return trow(glyph, "", nm, ":" + str(ls[0]), note=s("c", f"↑ also at :{seen}"), cls=cls)
    return trow(glyph, fold, nm, ":" + str(ls[0]), file, b if b else "", len(callers[t]), cls=cls)

def anchor_up(label, items):
    r = s("", " ") + s("c", "↑ " + label + "  ")
    for i, (n, at) in enumerate(items):
        r += (s("c", " · ") if i else []) + n + (s("c", " " + at) if at else [])
    return (r, "")

def focus(name_segs, rest):
    r = s("fg bold", "━━ ") + name_segs + s("c", "  " + rest + " ")
    return (r + s("d3", "━" * (LW - width(r))), "")

def compose(headrows, left, right, sl, sr):
    out = [html_row(r, W, c) for r, c in headrows]
    for i in range(max(len(left), len(right))):
        l, lc = left[i] if i < len(left) else ([], "")
        r, rc = right[i] if i < len(right) else ([], "")
        out.append(html_row(l, LW, lc) + '<span class="d3">│</span>' + html_row(r, RW, rc))
    n = len(sl) + len(sr) + 1
    out.append('<span class="mode"> NORMAL </span><span class="sl">' + lib.H.escape(sl + " " * (W - 8 - n) + sr + " ") + "</span>")
    return '<pre class="nv">' + "\n".join(out) + "</pre>"

ROOT = find("startRun")
RK = kids(ROOT)
KEYS = "j/k row  h parent  l open  [ ] sibling  L open all  +/- budget"

def root_rows(open_apply=None, cursor=None):
    rows = []
    items = list(RK.items())
    for i, (t, ls) in enumerate(items):
        last = i == len(items) - 1
        g = "└ " if last else "├ "
        opened = open_apply == t
        rows.append(node_row(t, ls, g, D[ROOT]["path"], opened, "sel" if cursor == t else ""))
        if opened:
            sub = list(kids(t).items())
            for j, (u, uls) in enumerate(sub):
                g2 = ("   " if last else "│  ") + ("└ " if j == len(sub) - 1 else "├ ")
                seen = RK[u][0] if u in RK else None
                rows.append(node_row(u, uls, g2, D[t]["path"], False, "sel" if cursor == u else "", seen))
    return rows

up = anchor_up("called by", [(fn("createRun"), "run.ts:79"), (fn("createActiveRun") + s("d3", " local"), "checklists.ts:399")])
top = [up, focus(fn("startRun"), f"run.ts:83–337   calls {len(RK)}  ·  {below(ROOT)} below"), colhead()]

def right_pane(name, kind_path, call_from, call_line, body, ul, lit_call):
    r = [([], ""), (s("", " ") + s("b bold", name + "()") + s("c", "   " + kind_path), ""),
         (s("", " ") + s("c", "startRun() calls it at ") + s("fd", f"run.ts:{call_line}"), "")]
    r += code([call_from], call_line, lit=(call_line,), ul=(name,))
    r += [([], ""), (s("d3", "─" * RW), ""), ([], "")]
    r += code([t for _, t in body], body[0][0], ul=ul, on=None)
    return r

SHOTS = []
def shot(name, title, cap, html_):
    lib.write_shot(name, html_); SHOTS.append({"name": name, "title": title, "caption": cap})

# ── 1: startRun as it opens: the budget is spent on its 29 calls ──────────
APPLY = find("apply", "rules")
run_src = dict(src("packages/core/src/run/run.ts", 100, 112))
left = top + root_rows(cursor=APPLY)
right = right_pane("apply", "function in core/src/run/rules.ts:48", run_src[109], 109,
                   src("packages/core/src/run/rules.ts", 48, 90),
                   ("act", "observe", "noChange", "start", "isClick", "satisfy", "eventsOf", "mount", "begin"), 109)
shot("tree-1", "startRun(): the tree as it opens",
     "The function you came for is pinned at the top, with one line for who calls it. Below are its 29 calls in the order they are written, and the budget (34 rows) stops here: going one level deeper would take 29 more. Each row says how much sits under it and how many places call it, so apply() with 30 below is clearly where the weight is. The right panel shows the call, then the function itself, its own calls underlined.",
     compose(head("startRun()", "function", "run/run.ts", 83, "budget 34 rows  ·  depth 1 shown  ·  69 below"), left[:40], right[:40],
             " startRun()  ›  apply()   calls  7 of 29", KEYS))

# ── 2: l on apply(), then j: apply's calls, the cursor on observe() ───────
OBS = find("observe", "rules")
rows = root_rows(open_apply=APPLY, cursor=OBS)
i = [k for k, (r, c) in enumerate(rows) if c == "sel"][0]
view = rows[3:3 + 36]
rules = src("packages/core/src/run/rules.ts", 60, 66)
right = [([], ""), (s("", " ") + s("b bold", "observe()") + s("d3", " local") + s("c", "   function in core/src/run/rules.ts:331"), ""),
         (s("", " ") + s("c", "apply() calls it at ") + s("fd", "rules.ts:64"), "")]
right += code([t for _, t in rules], 60, lit=(64,), ul=("observe",))
right += [([], ""), (s("d3", "─" * RW), ""), ([], "")]
right += code([t for _, t in src("packages/core/src/run/rules.ts", 331, 347)], 331, ul=("observeWaymark", "noChange", "observeAdvance"))
shot("tree-2", "l on apply(), then j: one branch opened, the rest held",
     "l opened apply() one level: its 9 calls, in order, under it. begin() was already a call of startRun(), so it points up to :102 instead of opening twice. Nothing else moved; the root and its caller line stay pinned while the tree scrolls. L would open everything under apply() until the budget runs out, folding the rest with their counts.",
     compose(head("startRun()", "function", "run/run.ts", 83, "budget 34 rows  ·  apply() opened  ·  69 below"), top + view, right[:39],
             " startRun()  ›  apply()  ›  observe()   calls  2 of 9", KEYS))

# ── 3: a type: the same tree, its edges are who it is handed to ──────────
T = lambda n, f: (s("b", n) + s("pun", "()"), f)
tleft = [
    anchor_up("made by", [(fn("defineWalkthrough"), "core and react"), (fn("checkedWalkthrough"), "core")]),
    anchor_up("held in", [(s("ty", "WalkthroughProps") + s("pun", ".") + s("pr", "walkthrough"), "react"), (s("fg", "resumable"), "core"), (s("ty", "StepsOf"), "core")]),
    focus(s("ty bold", "Walkthrough"), "types.ts:110   taken by 18 functions, in the order it is handed on"),
    colhead("below", "used by", "file", "takes at"),
]
def trow2(g, fold, nm, at, bel, used, note=None, cls=""):
    f, l = at.rsplit(":", 1)
    if note is not None and "keeps" in note[0][1]: note = None
    return trow(g, fold, nm, ":" + l, "" if note else f, bel, used, note, cls)

tleft += [
    trow2("├ ", "▾", fn("useOwnedRun") + s("hre", "  react"), "useRun.ts:45", 14, 1),
    trow2("│  └ ", "▾", fn("createRun"), "run.ts:76", 13, 6),
    trow2("│     └ ", "▾", fn("startRun"), "run.ts:84", 12, 2, cls="sel"),
    trow2("│        ├ ", "", fn("storageOf"), "walkthrough.ts:54", "", 2, s("d3", "keeps it")),
    trow2("│        ├ ", "", fn("loading"), "state.ts:117", "", 1, s("d3", "keeps it")),
    trow2("│        ├ ", "▾", fn("begin"), "state.ts:126", 2, 2),
    trow2("│        │  └ ", "▾", fn("enter"), "state.ts:88", 1, 3),
    trow2("│        │     └ ", "", fn("stepAt"), "state.ts:60", "", 2, s("d3", "keeps it")),
    trow2("│        ├ ", "▸", fn("apply"), "rules.ts:51", 6, 1, s("c", "act observe satisfy +3")),
    trow2("│        ├ ", "", fn("stepAt"), "state.ts:60", "", 2, s("c", "↑ also under enter()")),
    trow2("│        └ ", "", fn("onReset"), "walkthrough.ts:41", "", 1, s("d3", "keeps it")),
    trow2("├ ", "▾", fn("createActiveRun") + s("d3", " local"), "checklists.ts:396", 12, 1),
    trow2("│  └ ", "", fn("startRun"), "run.ts:84", "", 2, s("c", "↑ opened above")),
    trow2("└ ", "", fn("isSteps") + s("d3", " local"), "checklists.ts:51", "", 1, s("d3", "keeps it")),
]
runl = dict(src("packages/core/src/run/run.ts", 83, 320))
pick = [83, 84, 85, 86, 87, None, 91, None, 102, None, 109, None, 135, None, 318]
right = [([], ""), (s("", " ") + s("b bold", "startRun()") + s("c", "   takes it at :84, hands it on at 5 lines"), ""), ([], "")]
right += code([(n, runl[n]) if n else None for n in pick], 83, lit=(91, 102, 109, 135, 318), ul=("walkthrough",))
shot("tree-3", "The type Walkthrough: the same tree, its edges are who it is handed to",
     "A type calls nothing, so its tree is the value's journey: the functions that take one as a parameter, nested by who hands it to whom. Who makes it and where it is held sit pinned on top, as a function's callers do. A row with nothing below keeps the value and passes it no further; apply()'s six is folded by the budget. The right shows where startRun() hands it on.",
     compose(head("Walkthrough", "type", "walkthrough/types.ts", 110, "budget 34 rows  ·  18 functions take it"), tleft, right,
             " Walkthrough  ›  startRun()   taken by  3 of 18", KEYS))

json.dump(SHOTS, open("/tmp/seam-tree/v3/tree.json", "w"), indent=1)
print("ok", [len(x) for x in [left, right]])
