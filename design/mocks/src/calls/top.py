import sys, json
sys.path.insert(0, "/tmp/seam-tree/v3")
import tree as T
from tree import s, fn, trow, colhead, compose, src, code, focus, anchor_up, LW, RW, W, line, width
import lib

def comp(name): return lib.s("pun", "<") + lib.s("ty", name) + lib.s("pun", ">")
def pkgrow(hue, label, rest, fold="▾", cls=""):
    r = lib.s(hue, "▎") + lib.s("", " ") + lib.s("c", fold + " ") + lib.s("fg bold", label) + lib.s("c", "   " + rest)
    return (r, cls)
def row(hue, g, fold, nm, bel="", used="", file="", ln="", note=None, cls=""):
    r = trow(g, fold, nm, ln, file, bel, used, note, cls)
    segs = r[0]
    segs[0] = (hue, "▎")
    return (segs, cls)
SH = lambda t: lib.s("d3", t)
DOT = "·"

def head(title, rest, right):
    r1 = s("c", " Seams › ") + s("fg bold", title) + s("c", "   " + rest)
    r1 = line([(r1, 0), (s("c", right), W - len(right) - 1)], W)
    r2 = s("", "  ") + s("c", " Contracts ") + s("", "   ") + s("tab bold", " Calls ")
    return [(r1, ""), (r2, ""), (s("d3", "─" * W), "")]

# ── 4: from the top ────────────────────────────────────────────────────
left = [
    (s("", " ") + s("c", "where the code starts: nothing calls these"), ""),
    (s("", " ") + s("c", "shared, never opened:  ") + s("b", "useStore") + s("c", " 5   ") + s("b", "noChange") + s("c", " 9   ") + s("b", "storageFailed") + s("c", " 5   ") + s("b", "isRecord") + s("c", " 5"), ""),
    colhead(),
    pkgrow("hdemo", "apps/demo", "the app"),
    row("hdemo", "├ ", "▾", s("fg", "main.tsx") + s("c", "  top of the module"), DOT, "", "", ""),
    row("hdemo", "│  └ ", "▾", comp("App"), DOT, 1, "App.tsx", ":6"),
    row("hdemo", "│     ├ ", "▸", comp("Sidebar"), 1, 1, "", ":41"),
    row("hdemo", "│     ├ ", "▸", comp("TopBar"), 3, 1, "", ":43"),
    row("hdemo", "│     ├ ", "", comp("PageHeader"), "", 1, "", ":45"),
    row("hdemo", "│     ├ ", "", comp("Stats"), "", 1, "", ":46", SH("calls useStore() only")),
    row("hdemo", "│     ├ ", "▸", comp("Projects"), 4, 1, "", ":48"),
    row("hdemo", "│     ├ ", "▸", comp("GettingStarted"), DOT, 1, "", ":49"),
    row("hdemo", "│     └ ", "▾", comp("Guidance"), DOT, 1, "guidance.tsx", ":53"),
    row("hdemo", "│        ├ ", "", fn("useAfter"), "", 1, "", ":145"),
    row("hre", "│        └ ", "▸", comp("Walkthrough") + lib.s("c", " ×3"), DOT, 7, "Walkthrough.tsx", ":148", cls="sel"),
    row("hdemo", "└ ", "▾", s("fg", "guidance.tsx") + s("c", "  top of the module"), DOT, "", "", ""),
    row("hdemo", "   ├ ", "▸", fn("defineWalkthrough") + s("c", "  inviteTour"), DOT, 8, "definition.ts", ":12"),
    row("hdemo", "   ├ ", "▸", fn("createChecklists") + s("c", "  views"), DOT, 8, "definition.ts", ":48"),
    row("hdemo", "   └ ", "▸", fn("createChecklists") + s("c", "  onboarding"), "", "", "", ":101", SH("↑ same as :48")),
    pkgrow("he2e", "e2e/fixtures", "main.ts · react/main.tsx · checklist.ts   3 starts", "▸"),
    pkgrow("hre", "packages/react", "public: index.ts exports 12 functions and components"),
    row("hre", "├ ", "▸", comp("Walkthrough"), DOT, 7, "Walkthrough.tsx", ":47"),
    row("hre", "├ ", "▸", comp("Checklist"), DOT, 4, "Checklist.tsx", ":194"),
    row("hre", "├ ", "▸", fn("useChecklist"), DOT, 5, "Checklist.tsx", ":12"),
    row("hre", "├ ", "▸", fn("defineWalkthrough") + s("c", " +2"), DOT, "", "definition.ts", ""),
    row("hre", "└ ", "▸", comp("ChecklistRoot") + s("c", "  and 5 more parts"), DOT, 5, "parts.tsx", ""),
    pkgrow("hcor", "packages/core", "public: index.ts exports 5 functions"),
    row("hcor", "├ ", "▸", fn("createRun"), 71, 6, "run.ts", ":75"),
    row("hcor", "├ ", "▸", fn("everyProblem"), 4, 7, "problems.ts", ":50"),
    row("hcor", "├ ", "▸", fn("localStorageAdapter"), 1, 5, "adapter.ts", ":67"),
    row("hcor", "└ ", "▸", fn("defineWalkthrough") + s("c", " +1"), DOT, "", "walkthrough.ts", ""),
    pkgrow("c", "tests", "16 files, each its own start", "▸"),
]
g = src("apps/demo/app/guidance.tsx", 144, 153)
right = [([], ""), (s("", " ") + s("pun", "<") + s("ty bold", "Walkthrough") + s("pun", ">") + s("c", "   rendered 3 times by ") + s("pun", "<") + s("ty", "Guidance") + s("pun", ">"), ""),
         (s("", " ") + s("c", "demo/app/guidance.tsx, each with different props"), ""), ([], "")]
right += code([t for _, t in g], 144, lit=(148, 149, 150), ul=("Walkthrough",))
right += [([], ""), (s("d3", "─" * RW), ""), ([], ""),
          (s("", " ") + s("pun", "<") + s("ty bold", "Walkthrough") + s("pun", ">") + s("c", "   component in packages/") + s("hre bold", "react") + s("c", "/src/Walkthrough.tsx:47"), ""),
          (s("", " ") + s("c", "used by 7 files  ·  its own tree opens with ") + s("fd", "l") + s("c", ", or ") + s("fd", "<CR>") + s("c", " to anchor on it"), "")]
T.lib.write_shot("tree-4", compose(head("from the top", "every place the code starts, and what each one calls", "budget 34 rows  ·  4 starts open"),
    left, right, " from the top  ›  main.tsx  ›  <App>  ›  <Guidance>  ›  <Walkthrough>", "j/k row  h parent  l open  [ ] sibling  <CR> anchor here"))

# ── 5: anchored on createRun, turned upward: who calls it, to where it starts ──
left = [
    (s("", " ") + s("c", "↓ calls  ") + fn("startRun") + s("c", " run.ts:79 · ") + fn("problemReporter") + s("c", " problems.ts:103"), ""),
    focus(fn("createRun"), "run.ts:75   called from 6 files, 102 uses   ·   upward"),
    colhead("above", "used by", "file", "line"),
    row("hre", "├ ", "▾", fn("useOwnedRun"), 11, 1, "useRun.ts", ":59"),
    row("hre", "│  └ ", "▾", comp("ActiveWalkthrough"), 10, 1, "Walkthrough.tsx", ":82"),
    row("hre", "│     └ ", "▾", comp("Walkthrough"), 9, 7, "", ":69"),
    row("hdemo", "│        ├ ", "▾", comp("Guidance") + s("c", " ×3"), 2, 1, "demo/…/guidance.tsx", ":148"),
    row("hdemo", "│        │  └ ", "▾", comp("App"), 1, 1, "demo/app/App.tsx", ":53"),
    row("hdemo", "│        │     └ ", "", s("fg", "main.tsx") + s("c", "  top of the module"), "", "", "", ":6", cls="sel"),
    row("he2e", "│        ├ ", "▸", comp("Guidance"), 4, 2, "e2e/…/guidance.tsx", ":297"),
    row("he2e", "│        ├ ", "▸", comp("WhatsNew"), 3, 1, "e2e/…/guidance.tsx", ":327"),
    row("hre", "│        └ ", "▸", s("fg", "tests"), "", 5, "react/src/", "", SH("64 uses, folded")),
    row("he2e", "├ ", "▾", fn("start"), 2, 1, "e2e/fixtures/main.ts", ":82"),
    row("he2e", "│  └ ", "▾", fn("apply"), 1, 1, "", ":121"),
    row("he2e", "│     └ ", "", s("fg", "main.ts") + s("c", "  top of the module"), "", "", "", ""),
    row("hcor", "├ ", "", fn("frameOf"), "", 1, "run.perf.ts", ":37"),
    row("hcor", "└ ", "▸", s("fg", "tests"), "", 3, "core/src/run/", "", SH("96 uses, folded")),
]
m = src("apps/demo/app/main.tsx", 1, 6)
right = [([], ""), (s("", " ") + s("fg bold", "main.tsx") + s("c", "   where this stack starts: the module itself"), ""),
         (s("", " ") + s("fd", "main.tsx › <App> › <Guidance> › <Walkthrough> › <ActiveWalkthrough>"), ""),
         (s("", " ") + s("fd", "› useOwnedRun() › createRun()"), ""), ([], "")]
right += code([t for _, t in m], 1, lit=(6,), ul=("App",))
T.lib.write_shot("tree-5", compose(head("createRun()", "function in packages/core/src/run/run.ts:75", "budget 34 rows  ·  called by, 4 levels open"),
    left, right, " createRun()  ›  called by  ›  main.tsx", "j/k row  h parent  l open  [ ] sibling  ~ calls  <CR> anchor here"))
print("ok")
