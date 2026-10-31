# The Changed view and the marks on the tree, mocked on two real versions of
# raf core: the base is raf-run-redesign (Oct 17), now is seam's copy (Oct 23).
# Declarations from decls.lua (treesitter) on both; a function whose text
# changed has a changed signature when its written parameters or return
# differ (sigs.json, extract.lua), else a changed body.
#   python3 mock.py <now src> <base src> <now-decls> <base-decls> <now-sigs> <base-sigs>
import sys, os, json, difflib
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose
lib.W = W = 178
lib.SHOT_CSS += (" .nv .da{background:#20303b} .nv .dd{background:#37222c} .nv .gr{color:#9ece6a} .nv .rd{color:#f7768e}"
                 " .nv .ye{color:#e0af68} .nv .or{color:#ff9e64} .nv .st{text-decoration:line-through} .nv .vdel{background:#2d202a;color:#8c6c7a}")
NOW, BASE = sys.argv[1].rstrip("/") + "/", sys.argv[2].rstrip("/") + "/"
ND = {f["path"]: f for f in json.load(open(sys.argv[3]))}
BD = {f["path"]: f for f in json.load(open(sys.argv[4]))}
def sigmap(p):
    o = {}
    for f in json.load(open(p))["files"]:
        for x in f["fns"]: o[(f["path"], x["name"])] = (tuple((q["name"], q.get("type")) for q in x["params"]), x.get("ret"))
    return o
NS, BS = sigmap(sys.argv[5]), sigmap(sys.argv[6])

def classify(path):
    """[(name, kind, exported, state)] in the file's order now, the gone after"""
    a = {d["name"]: d for d in ND.get(path, {}).get("decls", [])}
    b = {d["name"]: d for d in BD.get(path, {}).get("decls", [])}
    out = []
    for n, d in a.items():
        if n not in b: st = "new"
        elif d["text"] == b[n]["text"]: st = ""
        elif d["kind"] == "type": st = "changed"
        elif NS.get((path, n)) != BS.get((path, n)): st = "signature"
        else: st = "body"
        out.append((n, d["kind"], d["exported"], st))
    for n, d in b.items():
        if n not in a: out.append((n, d["kind"], d["exported"], "gone"))
    return out

def file_state(path):
    if path not in BD: return "new"
    if path not in ND: return "gone"
    return sum(1 for *_, st in classify(path) if st)

def folder_count(prefix):
    paths = set(p for p in list(ND) + list(BD) if p.startswith(prefix) and not p.endswith((".test.ts", ".perf.ts")))
    return sum(1 for p in paths if file_state(p))

GIT0 = True
WORD = {"new": "new", "gone": "gone", "signature": "signature changed", "body": "body changed", "changed": "changed"}
SIGN = {"new": ("gr", "+"), "gone": ("rd", "_"), "signature": ("ye", "~"), "body": ("ye", "~"), "changed": ("ye", "~")}
COL = {"new": "gr", "gone": "rd st", "signature": "or", "body": "ye", "changed": "ye"}

def name_seg(n, kind, st, mode, dim):
    shown = n + ("()" if kind == "function" else "")
    if mode == "colour" and st:
        return s(COL[st], shown)
    c = "ty" if kind == "type" else "b" if kind == "function" else "fg"
    if dim: c = "fd" if kind != "type" else "ty"
    if st == "gone": c = "c st"
    return s(c, shown)

def tree_rows(mode, w, cursor, only=False, opened=("problems.ts", "storage/adapter.ts")):
    rows = []
    def add(depth, seg, st="", key=None, word=None):
        if only and not st: return
        r = []
        if mode == "sign":
            c, g = SIGN.get(st, ("", " ")) if st else ("", " ")
            r += s(c, g) + s("", " ")
        else:
            r += s("", "  ")
        r += s("", "  " * depth) + seg
        word = word if word is not None else WORD.get(st, "")
        if mode == "word" and word:
            r += s("", " " * max(2, w - lib.width(r) - len(word) - 1)) + s("c", word)
        rows.append((r, "sel" if key == cursor else ""))
    def file(path, depth):
        st = file_state(path)
        name = path.split("/")[-1]
        stt = "new" if st == "new" else "changed" if st else ""
        word = "new file" if st == "new" else f"{st} changed" if st else ""
        seg = s(COL[stt], name) if mode == "colour" and stt else s("fg", name)
        add(depth, seg, stt, path, word)
        if path in opened:
            items = classify(path)
            for exported in (True, False):
                for n, kind, ex, st in items:
                    if ex == exported:
                        add(depth + 1, name_seg(n, kind, st, mode, not ex), st, n)
    def folder(name, depth, prefix, closed=True):
        k = folder_count(prefix)
        seg = s("c", "▸ ") + s("fg", name) if closed else s("fg", name)
        add(depth, seg, "changed" if k else "", name, f"{k} files" if k else "")
    add(0, s("fg", "packages/"), "changed", word="")
    add(1, s("hcor bold", "core") + s("fg", "/src/"), "changed", word="")
    folder("checklists/", 2, "checklists/")
    file("problems.ts", 2)
    folder("run/", 2, "run/")
    folder("storage/", 2, "storage/", closed=False)
    for p in ("storage/adapter.ts", "storage/link.ts", "storage/migrations.ts", "storage/records.ts"):
        file(p, 3)
    folder("walkthrough/", 2, "walkthrough/")
    return rows

def tabs(have, on):
    r = s("", " ")
    for t in have:
        r += s("tab bold" if t == on else "c", f" {t} ") + s("", "  ")
    return (r, "")
VIEWS = ["Code", "Types", "Built from", "Used by", "Map", "Changed"]

def lines_of(root, path, a=None, b=None):
    L = open(root + path).read().split("\n")
    return L if a is None else L[a - 1:b]

def diff_git(base, now, b0, n0, w):
    """the hunks as git shows them, with three lines around each"""
    out = []
    for g in difflib.SequenceMatcher(None, base, now, autojunk=False).get_grouped_opcodes(3):
        i1, i2, j1, j2 = g[0][1], g[-1][2], g[0][3], g[-1][4]
        out.append((s("cy", f"@@ -{b0 + i1},{i2 - i1} +{n0 + j1},{j2 - j1} @@"), ""))
        for tag, a1, a2, c1, c2 in g:
            if tag == "equal":
                for k in range(c1, c2): out.append((s("c", " ") + ts(now[k]), ""))
            if tag in ("replace", "delete"):
                for k in range(a1, a2): out.append((s("rd", "-") + ts(base[k]), "dd"))
            if tag in ("replace", "insert"):
                for k in range(c1, c2): out.append((s("gr", "+") + ts(now[k]), "da"))
    return out

def diff_now(base, now, n0, w, around=None):
    """the code as it is now: a bar on lines added or changed, the removed as lines without numbers"""
    out = []
    for tag, a1, a2, c1, c2 in difflib.SequenceMatcher(None, base, now, autojunk=False).get_opcodes():
        if tag in ("replace", "delete"):
            for k in range(a1, a2): out.append((s("rd", "▁") + s("", "     ") + s("vdel", base[k]), ""))
        for k in range(c1, c2):
            bar = s("", " ") if tag == "equal" else s("gr" if tag == "insert" else "ye", "▎")
            out.append((bar + s("c", str(n0 + k).rjust(4)) + s("", "  ") + ts(now[k]), ""))
    return out

def decl_lines(D, root, path, name):
    d = next(x for x in D[path]["decls"] if x["name"] == name)
    return lines_of(root, path, d["from"], d["to"]), d["from"]

def head(name_seg, rest):
    return [(s("", " ") + name_seg + s("c", "   " + rest), ""), blank()[0]]

BASE_NAME = "run-redesign"
def screen(name, left, right, lw, status, trail):
    hd = [(s("c", " Seams › ") + s("fg bold", trail) + s("c", "   changed since ") + s("y", BASE_NAME), ""), (s("d3", "─" * W), "")]
    n = max(len(left), len(right)) + 1
    scr = compose(hd, [(left + blank(n - len(left)), lw), (right + blank(n - len(right)), W - lw - 1)],
                  status, "<Tab> view   <C-Tab> display   gb base   gc only changed")
    lib.write_shot(name, scr)

LW = 58
RW = W - LW - 1
sf_base, sb0 = decl_lines(BD, BASE, "problems.ts", "storageFailed")
sf_now, sn0 = decl_lines(ND, NOW, "problems.ts", "storageFailed")
sf_head = head(s("b bold", "storageFailed") + s("pun", "()"), "function in problems.ts:72   signature changed")
sf_sig = [(s("", " ") + s("c", "was  ") + s("pun", "(") + s("fg", "record") + s("pun", ": ") + ts('"tasks" | "walkthrough"') + s("pun", ", ") + s("fg", "error") + s("pun", ": ") + s("m", "unknown") + s("pun", ")") + s("c", " → ") + s("b", "storageFailed") + s("c", " → ") + s("ty", "WaymarkProblem<never>"), ""),
          (s("", " ") + s("c", "now  ") + s("pun", "(") + s("fg", "error") + s("pun", ": ") + s("m", "unknown") + s("pun", ")") + s("c", " → ") + s("b", "storageFailed") + s("c", " → ") + s("ty", "WaymarkProblem<never>"), ""), blank()[0]]
right = sf_head + [tabs(VIEWS, "Changed"), blank()[0]] + sf_sig + diff_git(sf_base, sf_now, sb0, sn0, RW)

# ── 8b. marks on the tree, three ways ───────────────────────────────────
for mode, cap in [("sign", "a"), ("colour", "b"), ("word", "c")]:
    screen(f"changed-tree-{cap}", [blank()[0]] + tree_rows(mode, LW, "storageFailed"), right, LW,
           "storageFailed()  changed", "problems.ts › storageFailed()")

# ── 8d. the Changed view on a file, two displays ────────────────────────
pb, pn = lines_of(BASE, "problems.ts"), lines_of(NOW, "problems.ts")
fhead = head(s("fg bold", "problems.ts"), "file in packages/core/src/   " + ", ".join(f"{sum(1 for *_, st in classify('problems.ts') if st == k)} {w}" for k, w in [("signature", "signatures"), ("changed", "types"), ("body", "body"), ("new", "new")])) + [tabs(VIEWS, "Changed"), blank()[0]]
LW2 = 46
screen("changed-view-a", [blank()[0]] + tree_rows("word", LW2, "problems.ts", opened=("problems.ts",)),
       fhead[:2] + [tabs(VIEWS, "Changed"), (s("", " ") + s("c", "display  ") + s("fg", "diff"), ""), blank()[0]] + diff_git(pb, pn, 1, 1, W - LW2 - 1)[:58],
       LW2, "problems.ts  changed · diff", "problems.ts")
screen("changed-view-b", [blank()[0]] + tree_rows("word", LW2, "problems.ts", opened=("problems.ts",)),
       fhead[:2] + [tabs(VIEWS, "Changed"), (s("", " ") + s("c", "display  ") + s("fg", "as it is now"), ""), blank()[0]] + diff_now(pb, pn, 1, W - LW2 - 1)[:58],
       LW2, "problems.ts  changed · as it is now", "problems.ts")

# ── 8c. only what changed, Used by on the changed signature ─────────────
def place(path, n, root, mark=None):
    t = lines_of(root, path, n, n)[0].strip()
    r = s("", "     ") + s("c", str(n).rjust(4)) + s("", "  ") + ts(t)
    return (r, "")
ub = head(s("b bold", "storageFailed") + s("pun", "()"), "signature changed   used by 2 places now, 5 at the base") + [tabs(VIEWS, "Used by"), blank()[0]] + sf_sig
ub += [(s("", " ") + s("fg bold", "now"), ""), blank()[0],
       (s("", "   ") + s("fg", "storage/link.ts") + s("c", "   new file   in createLink()"), ""),
       place("storage/link.ts", 84, NOW), place("storage/link.ts", 106, NOW), blank()[0],
       (s("", " ") + s("fg bold", "at the base"), "") , blank()[0]]
for path, ns in [("run/run.ts", [93]), ("checklists/checklists.ts", [178, 180]), ("walkthrough/walkthrough.ts", [63, 107])]:
    st = file_state(path)
    what = "file gone" if st == "gone" else f"{st} changed in the file"
    ub.append((s("", "   ") + s("fg", path) + s("c", "   " + what), ""))
    for n in ns: ub.append(place(path, n, BASE))
    ub.append(blank()[0])
screen("changed-lens", [blank()[0]] + tree_rows("sign", LW, "storageFailed", only=True), ub, LW,
       "only what changed   storageFailed()  used by", "problems.ts › storageFailed()")
print("ok")

# ── round two: gitsigns in the tree, CodeDiff's inline diff in the pane ─
lib.SHOT_CSS += (" .nv .dl{background:#3b2230;color:#b8a0a8} .nv .dlx{background:#6e2a3a;color:#e8c8d0}"
                 " .nv .ax{background:#2c5a4a} .nv .ad{background:#1d3a35}")
GIT = {"new": ("gr", "+"), "gone": ("rd", "_"), "signature": ("ye", "~"), "body": ("ye", "~"), "changed": ("ye", "~")}
SIGN.update(GIT)

import re as _re
def chars(a, b):
    """the spans of a and of b that differ, word by word, as (start, end) lists"""
    ta = [m for m in _re.finditer(r"\w+|\s+|[^\w\s]", a)]
    tb = [m for m in _re.finditer(r"\w+|\s+|[^\w\s]", b)]
    sa, sb = [], []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, [m.group() for m in ta], [m.group() for m in tb], autojunk=False).get_opcodes():
        if tag != "equal":
            for toks, x1, x2, out in ((ta, i1, i2, sa), (tb, j1, j2, sb)):
                while x1 < x2 and not toks[x1].group().strip(): x1 += 1
                while x2 > x1 and not toks[x2 - 1].group().strip(): x2 -= 1
                if x2 > x1: out.append((toks[x1].start(), toks[x2 - 1].end()))
    return sa, sb

def spans(text, marks, base, strong):
    out, k = [], 0
    for i, j in marks:
        if i > k: out.append((base, text[k:i]))
        out.append((strong, text[i:j])); k = j
    if k < len(text): out.append((base, text[k:]))
    return out

def inline(base, now, n0, collapse, ctx=3):
    """CodeDiff's inline layout: removed lines as lines without numbers above, added on green;
    collapse folds every run of unchanged lines longer than twice the context"""
    rows = []
    ops = difflib.SequenceMatcher(None, base, now, autojunk=False).get_opcodes()
    for oi, (tag, a1, a2, c1, c2) in enumerate(ops):
        if tag == "equal":
            ks = list(range(c1, c2))
            if collapse:
                head = ks[:ctx] if oi > 0 else []
                tail = ks[-ctx:] if oi < len(ops) - 1 else []
                if len(ks) > len(head) + len(tail) + 1:
                    for k in head: rows.append((s("", " ") + s("c", str(n0 + k).rjust(4)) + s("", "  ") + ts(now[k]), ""))
                    hidden = len(ks) - len(head) - len(tail)
                    rows.append((s("", "      ") + s("d3", f"⋯ {hidden} lines unchanged"), ""))
                    for k in tail: rows.append((s("", " ") + s("c", str(n0 + k).rjust(4)) + s("", "  ") + ts(now[k]), ""))
                    continue
            for k in ks: rows.append((s("", " ") + s("c", str(n0 + k).rjust(4)) + s("", "  ") + ts(now[k]), ""))
            continue
        old, new = base[a1:a2], now[c1:c2]
        pairs = min(len(old), len(new)) if tag == "replace" else 0
        for i, t in enumerate(old):
            m = chars(t, new[i])[0] if i < pairs else []
            r = s("dl", "       ") + spans(t, m, "dl", "dlx")
            rows.append((r + s("dl", " " * max(0, PW - lib.width(r))), ""))
        for i, t in enumerate(new):
            m = chars(old[i], t)[1] if i < pairs else []
            r = s("ad", " ") + s("ad c", str(n0 + c1 + i).rjust(4)) + s("ad", "  ")
            r += [(c + " ad", x) for c, x in ts(t)] if not m else spans(t, m, "ad", "ax")
            rows.append((r + s("ad", " " * max(0, PW - lib.width(r))), ""))
    return rows

RANGE = s("c", "   changes ") + s("y", BASE_NAME) + s("c", " → ") + s("y", "now")
def screen2(name, left, right, lw, status, trail, keys="<Tab> view   <C-Tab> display   ]c [c next change   gc only changed   L lens"):
    hd = [(s("c", " Seams › ") + s("fg bold", trail) + RANGE, ""), (s("d3", "─" * W), "")]
    n = max(len(left), len(right)) + 1
    lib.write_shot(name, compose(hd, [(left + blank(n - len(left)), lw), (right + blank(n - len(right)), W - lw - 1)], status, keys))

LW3 = 46
PW = W - LW3 - 1
def fpane(display):
    return head(s("fg bold", "problems.ts"), "file in packages/core/src/") + [tabs(VIEWS, "Changed"),
            (s("", " ") + s("c", "display  ") + s("fg", display), ""), blank()[0]]
screen2("changed-signs", [blank()[0]] + tree_rows("sign", LW3, "problems.ts", opened=("problems.ts", "storage/adapter.ts")),
        fpane("changes only") + inline(pb, pn, 1, True)[:60], LW3, "problems.ts  changed · changes only", "problems.ts")
screen2("changed-signs-only", [blank()[0]] + tree_rows("sign", LW3, "problems.ts", only=True, opened=("problems.ts", "storage/adapter.ts")),
        fpane("changes only") + inline(pb, pn, 1, True)[:60], LW3, "only what changed   problems.ts  changes only", "problems.ts")
screen2("changed-whole", [blank()[0]] + tree_rows("sign", LW3, "problems.ts", opened=("problems.ts",)),
        fpane("whole file") + inline(pb, pn, 1, False)[:60], LW3, "problems.ts  changed · whole file", "problems.ts")

# the lens, the range on its first rows
def lens_float():
    w = 100
    def r(*segs): return (s("", " ") + sum(segs, []), "")
    rows = [r(s("c", "")),
            r(s("fg bold", "changes"), s("c", "   from  "), s("y", "HEAD"), s("c", "   to  "), s("y", "working tree"), s("c", "      what the signs and ]c [c follow")),
            r(s("c", "")),
            r(s("c", " " * 44 + "contracts  built from  used by")),
            r(s("", "  "), s("pr", "*.test.*"), s("c", " " * 26 + "12"), s("c", "       ·        hide       hide")),
            r(s("", "  "), s("fg", "e2e/"), s("c", " " * 30 + " 9"), s("c", "      hide      hide       hide")),
            r(s("", "  "), s("b", "+ add: pick folders and files, or type a pattern")),
            r(s("c", "")),
            r(s("c", "  on changes: "), s("fg", "f"), s("c", " from  "), s("fg", "t"), s("c", " to   a branch, a tag, a hash, HEAD~3; "), s("fg", "x"), s("c", " back to HEAD → working tree")),
            r(s("c", ""))]
    return rows, w
lrows, lw_ = lens_float()
base_left = [blank()[0]] + tree_rows("sign", LW3, "problems.ts", opened=("problems.ts",))
right = fpane("changes only") + inline(pb, pn, 1, True)[:40]
n = max(len(base_left), len(right)) + 1
L2, R2 = base_left + blank(n - len(base_left)), right + blank(n - len(right))
# draw the float over the middle: rows 4.. of the composite, columns 30..
hd = [(s("c", " Seams › ") + s("fg bold", "problems.ts") + s("c", "   changes ") + s("y", "HEAD") + s("c", " → ") + s("y", "working tree"), ""), (s("d3", "─" * W), "")]
body = compose(hd, [(L2, LW3), (R2, W - LW3 - 1)], "lens", "j k row   f from   t to   x reset   q close")
import html as H
lines = body.split("\n")
top = 5
box = ["╭─ lens " + "─" * (lw_ - 8) + "╮"] + ["│" + lib.html_row(rw, lw_) + "│" for rw, _ in lrows] + ["╰" + "─" * lw_ + "╯"]
for i, b in enumerate(box):
    lines[top + i] = '<span class="d3">' + " " * 30 + "</span>" + (f'<span class="fg">{b}</span>' if i in (0, len(box) - 1) else '<span class="fg">│</span>' + b[1:-1] + '<span class="fg">│</span>') + '<span>' + " " * (W - 30 - lw_ - 2) + "</span>"
lib.write_shot("changed-range", "\n".join(lines))
print("round two ok")
