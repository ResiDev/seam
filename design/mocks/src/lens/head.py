from common import *
lib.SHOT_CSS += " .nv .tabon{background:#3b4261;color:#c0caf5;font-weight:700} .nv .lq{color:#c45c5c}"
q = lambda t: s("lq", t)
SL = ("  createRun()  ›  start()", "~ calls   / anchor on   j/k row   l open   <CR> anchor here   K back")

def head(lost=0):
    r0 = s("c", " Seams › ") + s("c", "startRun() › ") + s("b bold", "createRun") + s("pun", "()") + s("c", "   packages/core/src/run/run.ts:75")
    r2 = s("", " ") + s("fd", " Calls 2 ") + s("", " ") + s("tabon", " Called by 6 ")
    if lost: r2 += q(f"    +{lost} hidden") + s("c", "  L lens")
    return [r0, [], r2]

def screen(rules, picker=None, sl=SL):
    left, CI = calls(rules)
    lost = len(CI["lost"])
    body = [x for x in left[3:] if "hidden by the lens" not in "".join(t for _, t in x[0])]
    ch = (place([(s("c", "above"), C_ABOVE - 1), (s("c", "used by"), C_USED - 1), (s("c", "file"), C_FILE), (s("c", "line"), C_LINE)]), "")
    tree = [ch] + body
    rw = W - LW - 1
    cols = columns([(tree, LW), (calls_right(rw)[1:], rw)])
    rows = head(lost if rules else 0) + [[]] + cols
    while len(rows) < 26: rows.append([])
    rows = [pad(r, W) for r in rows]
    if picker: rows = overlay(rows, 3, 6, picker)
    return to_html(rows, status(*sl))

shot("v8-head", "Head: where you are, which way, one line each",
     "", screen([]))
shot("v8-head-lens", "Head with a lens", "", screen([{"path": "packages/react/", "cols": {"used": "hide"}}]))

# the picker: / from the call tree
PW = 84
items = [("startRun", "function", "packages/core/src/run/run.ts", 83, 2, "s t a r t"),
         ("start", "function", "e2e/fixtures/main.ts", 71, 2, ""),
         ("start", "function", "packages/core/src/run/rules.ts", 349, 1, ""),
         ("startScreencast", "function", "apps/demo/record.ts", 67, 1, ""),
         ("GettingStarted", "component", "apps/demo/app/App.tsx", 405, 1, "")]
def item(e, sel):
    n, k, p, l, u, _ = e
    nm = comp(n) if k == "component" else fn(n)
    d, f = p.rsplit("/", 1)
    r = place([(s("", "  ") + nm, 0), (s("c", d + "/") + s("fd", f) + s("c", f":{l}"), 26), (s("fd", str(u).rjust(3)), PW - 6)])
    return withcls(pad(r, PW), "sel" if sel else "")
box = [s("c", "╭─") + s("fd", " anchor on ") + s("c", "─" * (PW - 13) + "╮")]
inner = [place([(s("", " ") + s("b", "> ") + s("fg", "start") + s("tabon", " "), 0), (s("c", "5 of 382 functions"), PW - 19)]),
         place([(s("c", "used by"), PW - 8)])] + [item(e, i == 0) for i, e in enumerate(items)] + [[],
         s("c", "  <CR> anchor   <C-n>/<C-p> next   <Esc> back")]
for r in inner: box.append(s("c", "│") + pad(r, PW) + s("c", "│"))
box.append(s("c", "╰" + "─" * PW + "╯"))
shot("v8-picker", "/ anchors on any function", "", screen([], picker=box,
     sl=("  anchor on", "<CR> anchor   <C-n>/<C-p> next   <Esc> back")))
print("ok")
