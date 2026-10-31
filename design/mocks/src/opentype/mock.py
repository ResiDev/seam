# Opening a type with + and closing it with -, mocked on raf core.
#   python3 mock.py <raf core src (now)>   -> /tmp/seam-tree/v6/open-type-*.html
# The declarations are read from the files; the Changed one compares the two
# copies of raf on disk (Oct 17 and Oct 23), as changed/mock.py does.
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose, width
lib.W = W = 178
lib.SHOT_CSS += (" .nv .dl{background:#3b2230} .nv .ad{background:#1d3a35} .nv .gr{color:#9ece6a} .nv .rd{color:#f7768e} .nv .ye{color:#e0af68}")
SRC = sys.argv[1]
LW = 44
RW = W - LW - 1

def lines(rel, a, b):
    src = open(os.path.join(SRC, rel)).read().split("\n")
    return [(n, src[n - 1]) for n in range(a, b + 1)]

VIEWS = ["Code", "Types", "Built from", "Used by", "Map", "Changed"]
def tabs(on):
    r = s("", " ")
    for t in VIEWS: r += s("tab bold" if t == on else "c", f" {t} ") + s("", "  ")
    return (r, "")

def tsx(src, on=None):
    st = src.strip()
    if st.startswith(("/**", "*", "*/")) and not st.startswith("**"): return s("", src[:len(src) - len(src.lstrip())]) + s("c it", st)
    return ts(src, on=on)
def code_row(n, src, ind=0, on=None, cls="", gutter=True, sign=None):
    num = s("c", str(n).rjust(4)) if gutter else s("", "    ")
    lead = s("", " " * ind)
    sg = s(sign[0], sign[1]) if sign else s("", " ")
    return (s("", " ") + lead + num + sg + s("", " ") + tsx(src, on=on), cls)

def opened(name, where, decl, ind, on=None, nested=None, diff=None):
    """a type opened under the line it is named on: a bar down its left, its declaration as written"""
    rows = [(s("", " " + " " * ind) + s("d3", "│ ") + s("ty bold", name) + s("c", "   type in " + where), "")]
    for n, src in decl:
        mark = diff.get(n) if diff else None
        cls = {"-": "dl", "+": "ad"}.get(mark, "")
        sign = {"-": ("rd", "-"), "+": ("gr", "+")}.get(mark, ("", " "))
        rows.append((s("", " " + " " * ind) + s("d3", "│") + s(sign[0], sign[1]) + s("c", str(n).rjust(4)) + s("", "  ") + tsx(src, on=on), cls))
        if nested and n == nested[0]:
            rows += opened(*nested[1:], ind=ind + 8)
    return rows

def tree(rows_, cursor):
    out = [blank()[0]]
    for t, d, c in rows_:
        out.append((s("", "  " + "  " * d) + (c if isinstance(c, list) else s(c, t)), "sel" if t == cursor else ""))
    return out

def screen(name, left, right, status, keys, trail):
    hd = [(s("c", " Seams › ") + s("fg bold", trail), ""), (s("d3", "─" * W), "")]
    n = max(len(left), len(right)) + 1
    lib.write_shot(name, compose(hd, [(left + blank(n - len(left)), LW), (right + blank(n - len(right)), RW)], status, keys))

TREE = [("packages/", 0, "fg"), ("core/src/", 1, "hcor"), ("▸ checklists/", 2, "fg"), ("run/", 2, "fg"), ("▸ input.ts", 3, "fg"),
        ("run.ts", 3, "fg"), ("createRun()", 4, "b"), ("▸ update.ts", 3, "fg"), ("▸ storage/", 2, "fg"), ("▸ walkthrough/", 2, "fg"), ("state.ts", 2, "fg")]

# ── the Types view: + on a type named in a declaration ──────────────────
def types_view(nested):
    head = [(s("", " ") + s("b bold", "createRun") + s("pun", "()") + s("c", "   function in run/run.ts:33"), ""), blank()[0], tabs("Types"),
            (s("", " ") + s("c", "+ opens the type under the cursor   - closes it"), ""), blank()[0],
            (s("", " ") + s("pun", "(") + s("ty", "RunOptions") + s("pun", ")") + s("c", " → ") + s("b", "createRun") + s("c", " → ") + s("ty", "Run"), ""),
            blank()[0],
            (s("", " ") + s("c", "takes ") + s("ty bold", "RunOptions") + s("c", "   type in run/types.ts:145"), "")]
    body = []
    for n, src in lines("run/types.ts", 145, 158):
        if n == 154: src = src[:96] + "…"
        on = "StoredRecord" if n == 155 and not nested else None
        body.append(code_row(n, src, on=on))
        if n == 155:
            wp = None
            if nested:
                wp = (14, "WalkthroughProgress", "walkthrough/types.ts:97", lines("walkthrough/types.ts", 97, 105))
            body += opened("StoredRecord", "storage/records.ts:12", lines("storage/records.ts", 12, 16), ind=8,
                           on="WalkthroughProgress" if nested else None, nested=wp)
    body.append((s("", "      ") + s("c", "⋯"), ""))
    return head + body

for name, nested in (("open-type-a", False), ("open-type-b", True)):
    screen(name, tree(TREE, "createRun()"), types_view(nested), "createRun()  types", "<Tab> view   + open   - close   J page   K back", "createRun()")

# ── Changed: the signature reads the same, a type in it changed ─────────
BASE = "/home/alex/Work/libs/raf-run-redesign/packages/core/src"
def base_lines(rel, a, b):
    src = open(os.path.join(BASE, rel)).read().split("\n")
    return [(n, src[n - 1]) for n in range(a, b + 1)]

def changed_view():
    head = [(s("", " ") + s("b bold", "keyAction") + s("pun", "()") + s("c", "   function in run/input.ts:79   a type it takes changed, and 1 line of its body"), ""),
            blank()[0], tabs("Changed"),
            (s("", " ") + s("c", "display  ") + s("fg bold", "changes only") + s("d3", " · ") + s("c", "whole file") +
             s("c", "     from HEAD  to working tree     + opens the type under the cursor"), ""), blank()[0]]
    sig = s("", " ") + s("pun", "(") + s("ty", "KeyboardEvent") + s("pun", ", ") + s("ty vis", "InputContext") + s("pun", ")") + s("c", " → ") + \
          s("b", "keyAction") + s("c", " → ") + s("ty", "Action") + s("fg", " | ") + s("m", "undefined")
    rows = [(sig, ""), ]
    # InputContext, base lines 3-9 against now lines 4-10: one field swapped
    now = lines("run/input.ts", 4, 10)
    decl = [now[0], (None, "  collapsed: boolean;"), now[1]] + now[2:]
    shown = []
    for n, src in decl:
        shown.append((n, src))
    rows += [(s("", "  " + " " * 15) + s("d3", "│ ") + s("ty bold", "InputContext") + s("c", "   type in run/input.ts:4   ") + s("ye", "~") + s("c", " changed"), "")]
    for n, src in decl:
        if n is None:
            rows.append((s("", "  " + " " * 15) + s("d3", "│") + s("rd", "-") + s("", "    ") + s("", "  ") + ts(src), "dl")); continue
        mark = "+" if n == 5 else None
        rows.append((s("", "  " + " " * 15) + s("d3", "│") + (s("gr", "+") if mark else s("", " ")) + s("c", str(n).rjust(4)) + s("", "  ") + ts(src),
                     "ad" if mark else ""))
    rows.append(blank()[0])
    # the body: the one line that read the field is gone
    b = base_lines("run/input.ts", 79, 84)
    nw = lines("run/input.ts", 79, 84)
    for n, src in nw[:4]: rows.append(code_row(n, src))
    rows.append((s("", " ") + s("", "    ") + s("rd", "-") + s("", " ") + ts(b[4][1]), "dl"))
    rows.append((s("", " ") + s("", "    ") + s("rd", "-") + s("", " ") + ts(b[5][1]), "dl"))
    for n, src in nw[4:6]: rows.append(code_row(n, src))
    rows.append((s("", "     ") + s("c", "⋯ 24 lines unchanged"), ""))
    return head + rows

CT = [("packages/", 0, "fg"), ("core/src/", 1, "hcor"), ("run/", 2, s("fg", "run/") + s("ye", "  ~")), ("input.ts", 3, s("fg", "input.ts") + s("ye", "  ~")),
      ("whereClicked()", 4, s("b", "whereClicked()") + s("ye", "  ~")), ("cycleFocus()", 4, "b"),
      ("keyAction()", 4, s("b", "keyAction()") + s("ye", "  ~")), ("▸ run.ts", 3, s("fg", "▸ run.ts") + s("ye", "  ~")), ("▸ storage/", 2, "fg")]
screen("open-type-changed", tree(CT, "keyAction()"), changed_view(), "keyAction()  changed", "<Tab> view   + open   - close   ]c next change   J page", "keyAction()")
print("ok")
