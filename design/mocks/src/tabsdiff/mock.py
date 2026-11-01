# The pane's two tabs with Used by, Built from and the Map aside on gu gb gm,
# and the diff as a toggle, D, on the code and the types, both sides. Mocked
# on a git repository whose HEAD is raf-run-redesign (Oct 17) and whose
# working tree is seam's copy of raf (Oct 23), as /tmp/seam-changed is.
#   python3 mock.py /tmp/seam-changed   -> /tmp/seam-tree/v6/{tabs-aside,diff-code,diff-types}.html
#   then for each: chromium --headless --force-device-scale-factor=2 --window-size=1400,1100 --screenshot=<n>.png <n>.html
#   and magick <n>.png -fuzz 3% -trim +repage <n>.png
import sys, os, subprocess, difflib, re, html as H
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose
lib.W = W = 178
lib.SHOT_CSS += (" .nv .gr{color:#9ece6a} .nv .rd{color:#f7768e} .nv .ye{color:#e0af68} .nv .st{text-decoration:line-through}"
                 " .nv .dl{background:#3b2230;color:#b8a0a8} .nv .dlx{background:#6e2a3a;color:#e8c8d0}"
                 " .nv .ax{background:#2c5a4a} .nv .ad{background:#1d3a35}"
                 " .nv .k{color:#7aa2f7;font-weight:700} .nv .kw{color:#737aa2} .nv .kg{color:#3b4261}")
REPO = sys.argv[1].rstrip("/") + "/"
SRC = "packages/core/src/"

def now(path):
    return open(REPO + SRC + path).read().split("\n")
def base(path):
    return subprocess.run(["git", "-C", REPO, "show", "HEAD:" + SRC + path], capture_output=True, text=True).stdout.split("\n")

# ── the diff, as seam lays it out: removed lines unnumbered on red, added numbered on green
def chars(a, b):
    ta = list(re.finditer(r"\w+|\s+|[^\w\s]", a)); tb = list(re.finditer(r"\w+|\s+|[^\w\s]", b))
    sa, sb = [], []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, [m.group() for m in ta], [m.group() for m in tb], autojunk=False).get_opcodes():
        if tag != "equal":
            for toks, x1, x2, out in ((ta, i1, i2, sa), (tb, j1, j2, sb)):
                while x1 < x2 and not toks[x1].group().strip(): x1 += 1
                while x2 > x1 and not toks[x2 - 1].group().strip(): x2 -= 1
                if x2 > x1: out.append((toks[x1].start(), toks[x2 - 1].end()))
    return sa, sb

def spans(text, marks, plain, strong):
    out, k = [], 0
    for i, j in marks:
        if i > k: out.append((plain, text[k:i]))
        out.append((strong, text[i:j])); k = j
    if k < len(text): out.append((plain, text[k:]))
    return out

def fill(r, cls, w):
    return r + s(cls, " " * max(0, w - lib.width(r)))

def diffed(old, new, n0, w, gutter=4, fold=True, ctx=3, lead=" ", signs=False):
    """the rows of old → new, new's first line numbered n0; fold the unchanged runs"""
    rows = []
    ops = difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes()
    def same(k):
        rows.append((s("", lead) + s("c", str(n0 + k).rjust(gutter)) + s("", "  ") + ts(new[k]), ""))
    for oi, (tag, a1, a2, c1, c2) in enumerate(ops):
        if tag == "equal":
            ks = list(range(c1, c2))
            head = ks[:ctx] if oi > 0 else []
            tail = ks[-ctx:] if oi < len(ops) - 1 else []
            if fold and len(ks) > len(head) + len(tail) + 1:
                for k in head: same(k)
                rows.append((s("", " " * (gutter - 1 + len(lead))) + s("d3", f"  ⋯ {len(ks) - len(head) - len(tail)} lines unchanged"), ""))
                for k in tail: same(k)
            else:
                for k in ks: same(k)
            continue
        o, n = old[a1:a2], new[c1:c2]
        pairs = min(len(o), len(n)) if tag == "replace" else 0
        for i, t in enumerate(o):
            m = chars(t, n[i])[0] if i < pairs else []
            r = (s("dl rd", "-") + s("dl", " " * (gutter + 1 + len(lead)))) if signs else s("dl", " " * (gutter + 2 + len(lead)))
            rows.append((fill(r + spans(t, m, "dl", "dlx"), "dl", w), ""))
        for i, t in enumerate(n):
            m = chars(o[i], t)[1] if i < pairs else []
            r = s("ad gr" if signs else "ad", "+" if signs else lead) + s("ad c", str(n0 + c1 + i).rjust(gutter)) + s("ad", "  ")
            r += [(c + " ad", x) for c, x in ts(t)] if not m else spans(t, m, "ad", "ax")
            rows.append((fill(r, "ad", w), ""))
    return rows

# ── the status line, as seam draws it: where you are, then the keys lit in three groups
def status(left, groups):
    # the groups that fit, the last dropped first, as seam.hints does
    plain = lambda gs: "  │  ".join("   ".join(f"{k} {w}" for k, w in g) for g in gs)
    while len(groups) > 1 and len(plain(groups)) > W - 20 - len(left):
        groups = groups[:-1]
    parts, n = [], 0
    for j, g in enumerate(groups):
        if j: parts.append('<span class="kg">  │  </span>'); n += 5
        for i, (k, w) in enumerate(g):
            if i: parts.append("   "); n += 3
            parts.append(f'<span class="k">{H.escape(k)}</span> <span class="kw">{H.escape(w)}</span>'); n += len(k) + 1 + len(w)
    pad = W - 8 - len(left) - n - 1
    return '<span class="mode"> NORMAL </span><span class="sl">' + H.escape(left) + " " * pad + "".join(parts) + " </span>"

def screen(name, headrow, cols, left, groups):
    hd = [(headrow, ""), (s("d3", "─" * W), "")]
    n = max(len(r) for r, _ in cols) + 1
    cols = [(r + blank(n - len(r)), w) for r, w in cols]
    doc = compose(hd, cols, "", "")
    doc = doc[:doc.rindex('<span class="mode">')] + status(left, groups) + "</pre>"
    lib.write_shot(name, doc)

# ── the pane's head: what the row is, then the two tabs, an aside lit after them
def tabs(on, aside=None, display=None, have=("Code", "Types")):
    r = s("", " ")
    for i, t in enumerate(have):
        if i: r += s("", "   ")
        r += s("tab bold" if t == on and not aside else "c", f" {t} ")
    if aside:
        r += s("", "      ") + s("tab bold", f" {aside} ")
    if display:
        r += s("c", "   " + display)
    return (r, "")

# ── the tree on the left, its signs in the left column
SIGN = {"+": "gr", "~": "ye", "_": "rd"}
def trow(sign, depth, seg, cur=False):
    return (s(SIGN.get(sign, ""), sign or " ") + s("", " " + "  " * depth) + seg, "sel" if cur else "")
fn = lambda n, c="b": s(c, n) + s("pun", "()")
def tree(cursor):
    return [blank()[0],
            trow("~", 0, s("fg", "packages/")),
            trow("~", 1, s("hcor", "core") + s("fg", "/src/")),
            trow("~", 2, s("c", "▸ ") + s("fg", "checklists/")),
            trow("~", 2, s("c", "▸ ") + s("fg", "run/")),
            trow("~", 2, s("c", "▸ ") + s("fg", "storage/")),
            trow("~", 2, s("c", "▸ ") + s("fg", "walkthrough/")),
            trow("+", 2, s("c", "▸ ") + s("fg", "dev.ts")),
            trow("~", 2, s("fg", "problems.ts"), cursor == "problems.ts"),
            trow("~", 3, fn("everyProblem")),
            trow("~", 3, fn("storageFailed"), cursor == "storageFailed"),
            trow("~", 3, fn("recordUnreadable")),
            trow("~", 3, fn("recordDropped")),
            trow("+", 3, fn("entryDropped")),
            trow("", 3, fn("callbackThrew")),
            trow("", 3, fn("problemReporter")),
            trow("+", 2, s("fg", "state.ts")),
            trow("+", 2, s("c", "▸ ") + s("fg", "subscribe.ts"))]

LW = 46
PW = W - LW - 1
TREE_HEAD = s("c", " Seams › ") + s("fg bold", "storageFailed()")
SF_HEAD = s("", " ") + s("b bold", "storageFailed") + s("pun bold", "()") + s("c", "   function in packages/") + s("hcor", "core") + s("c", "/src/problems.ts:72")
ROW_KEYS = [("]c [c", "change"), ("gc", "only changed"), ("J", "code")]

# ═══ 1. Used by aside: gu on storageFailed(), its head lit after Code and Types
P = "problems.ts"
sig_was = s("pun", "(") + s("fg", "record") + s("pun", ": ") + ts('"tasks" | "walkthrough"') + s("pun", ", ") + s("fg", "error") + s("pun", ": ") + s("m", "unknown") + s("pun", ")")
sig_now = s("pun", "(") + s("fg", "error") + s("pun", ": ") + s("m", "unknown") + s("pun", ")")
gives = s("c", " → ") + s("b", "storageFailed") + s("c", " → ") + s("ty", "WaymarkProblem") + s("pun", "<") + s("m", "never") + s("pun", ">")

def place(path, n, lines, name="storageFailed"):
    t = lines[n - 1].strip()
    r = s("", "   ") + s("c", str(n).rjust(4)) + s("", "  ")
    i = t.find(name)
    r += ts(t[:i]) + s("b ul", name) + ts(t[i + len(name):])
    return (r, "")

used = [(SF_HEAD + s("c", "   signature changed   used by 2 places now, 5 at HEAD"), ""), blank()[0],
        tabs("Code", aside="Used by", display="by file"), blank()[0],
        (s("", " ") + s("c", "was  ") + sig_was + gives, ""),
        (s("", " ") + s("c", "now  ") + sig_now + gives, ""), blank()[0],
        (s("", " ") + s("fg bold", "now"), ""), blank()[0],
        (s("", " ") + s("fg bold", "storage/link.ts") + s("c", "   2 places   storageFailed"), "")]
link = now("storage/link.ts")
used += [place("storage/link.ts", 84, link), place("storage/link.ts", 106, link), blank()[0],
         (s("", " ") + s("fg bold", "at HEAD"), "")]
for path, ns, what in [("checklists/checklists.ts", [178, 180], "4 changed in the file"), ("walkthrough/walkthrough.ts", [63, 107], "6 changed in the file"), ("run/run.ts", [93], "11 changed in the file")]:
    b = base(path)
    used += [blank()[0], (s("", " ") + s("fg bold", path) + s("c", "   " + what), "")]
    used += [place(path, n, b) for n in ns]
screen("tabs-aside", TREE_HEAD, [(tree("storageFailed"), LW), (used, PW)],
       "storageFailed()  used by · by file",
       [ROW_KEYS, [("<Tab>", "code"), ("gu", "used by"), ("gb", "built from"), ("gm", "map"), ("<C-Tab>", "display")], [("L", "lens"), ("q", "close seam")]])

# ═══ 2. the diff on, the code screen: problems.ts on the left, storageFailed() in the pane
pb, pn = base(P), now(P)
CW = 104
code = diffed(pb, pn, 1, CW, gutter=3, fold=False)
# from line 50 of now, as scrolled there, the cursor on storageFailed at 72
first = next(i for i, (r, _) in enumerate(code) if lib.width(r) > 4 and "".join(t for _, t in r[:2]).strip() == "49")
left = code[first:first + 68]
left = [(r, "sel" if len(r) > 1 and r[1][1].strip() == "72" else c) for r, c in left]
left = [(s("", " ") + s("b bold", "problems.ts") + s("c", "   file in packages/") + s("hcor", "core") + s("c", "/src/"), ""), blank()[0]] + left
sfb, sfn = pb[60:65], pn[71:75]
pane = [(SF_HEAD + s("c", "   signature changed"), ""), blank()[0], tabs("Code", display="changes only"), blank()[0]]
pane += diffed(sfb, sfn, 72, W - CW - 1, fold=True)
screen("diff-code", s("c", " Seams › ") + s("fg bold", "problems.ts"), [(left, CW), (pane, W - CW - 1)],
       "diff on   problems.ts  code   storageFailed()",
       [[("]c [c", "change"), ("D", "diff"), ("K", "back"), ("<S-Tab>", "code or types")],
        [("<Tab>", "view"), ("gu", "used by"), ("gb", "built from"), ("gm", "map"), ("<C-Tab>", "display")], [("/", "search"), ("q", "close seam")]])

# ═══ 3. the diff on, the Types view of storageFailed(): its line as it was and is, WaymarkProblem's own lines
def sigrow(sign, sig):
    cls = "dl" if sign == "-" else "ad"
    r = s(cls + (" rd" if sign == "-" else " gr"), sign) + s(cls, " ") + [((c + " " + cls).strip(), t) for c, t in sig + gives]
    return (fill(r, cls, PW), "")
def decl_of(lines, name):
    """a declaration's lines, from its line to the line before the next declaration, blanks dropped"""
    a = next(i for i, l in enumerate(lines) if l.startswith("export type " + name))
    b = next(i for i in range(a + 1, len(lines)) if lines[i].startswith(("export ", "/**")) and not lines[i - 1].startswith(" "))
    while not lines[b - 1].strip(): b -= 1
    return lines[a:b], a + 1
(wpb, _), (wpn, w0) = decl_of(pb, "WaymarkProblem"), decl_of(pn, "WaymarkProblem")
decl = diffed(wpb, wpn, w0, PW, gutter=4, fold=False, signs=True)
types = [(SF_HEAD + s("c", "   signature changed; WaymarkProblem, a type it names, changed"), ""), blank()[0], tabs("Types"), blank()[0],
         sigrow("-", sig_was), sigrow("+", sig_now), blank()[0],
         (s("c", " gives ") + s("ty bold", "WaymarkProblem") + s("c", "   type in problems.ts:16   ") + s("ye", "~") + s("c", " changed"), "")]
types += decl
screen("diff-types", TREE_HEAD, [(tree("storageFailed"), LW), (types, PW)],
       "diff on   storageFailed()  types",
       [ROW_KEYS, [("<Tab>", "view"), ("gu", "used by"), ("gb", "built from"), ("gm", "map"), ("D", "diff")], [("L", "lens"), ("q", "close seam")]])
print("ok")
