# The Code view and the code screen, mocked on raf core's createRun.
# Types after names: the name written in the declared return of the call that
# made the value (sigs.json), else the server's inlay hint when it is short
# and has no shape in it (.proto/caps.txt), else `{ … }`. Nothing is added
# where the type is written.
#   python3 mock.py <raf>/packages/core/src   -> /tmp/seam-tree/v6/code-*.html
import sys, os, re
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose
lib.W = W = 178
lib.SHOT_CSS += " .nv .vt{color:#737aa2;font-style:italic} .nv .vtc{color:#545c7e}"
SRC = sys.argv[1].rstrip("/") + "/"
LINES = {}
def src(path):
    if path not in LINES: LINES[path] = open(SRC + path).read().split("\n")
    return LINES[path]
RUN = src("run/run.ts")
FIRST, LAST = 33, 100

# line -> [(text the type follows, type, where it comes from)]
#   ret: the declared return of the call that made it    hint: the server, short
T = {
    35: [("()", "Document | Element", "hint")],
    36: [("report", "ReportProblem<Step>", "ret")],
    37: [("queue", "Queue", "ret")],
    38: [("adapter", "StorageAdapter | undefined", "hint")],
    51: [("()", "RunState", "ret")],
    52: [("()", "boolean", "hint")],
    53: [("()", "{ … }", "hint")],
    65: [("(msg: Msg)", "void", "hint")],
    67: [("page", "Page", "ret")],
    69: [("link", "Link", "ret")],
    75: [("(read", '"failed" | Parsed', "hint")],
    76: [("(value", "unknown", "hint")],
    77: [("read", "Parsed", "ret")],
    81: [("(error", "RecordUnreadableError", "hint")],
    85: [("(replacement: StoredRecord | null)", "void", "hint")],
    86: [("parsed", "Parsed", "ret")],
    92: [("(msg: Msg)", "void", "hint")],
    93: [("next", "Updated", "ret")],
    98: [("(effects: readonly Effect[])", "void", "hint")],
}
IMPORTED = {"groupOf", "inDevelopment", "problemReporter", "recordUnreadable", "createQueue", "adapterOf",
            "createLink", "parseRecord", "listen", "createPage", "LOADING", "READY", "userRecordAt", "taskOf",
            "initialModel", "runStateOf", "update", "viewChecklist", "openOf", "Change", "Command", "Effect",
            "Given", "Model", "Msg", "StoredRecord", "Walkthrough", "Run", "RunOptions", "RunSnapshot",
            "AnyTask", "Checklist", "ChecklistDefinition", "ChecklistGroup", "ChecklistSnapshot"}

def at(line, text):
    """index just after the first `text` past the `=` or `(` that starts the value"""
    i = line.find(text)
    return i + len(text)

def row(n, text, mode, w, on=None, lit=False, gut=None):
    """one code line; mode: inline | eol | none; gut: the left column's width"""
    segs = []
    if gut is not None:
        t = T.get(n)
        g = ""
        if t and t[0][0][0] != "(" and t[0][0] != "()": g = t[0][1]
        elif t: g = "→ " + t[0][1]
        segs += s("vtc", (" " + g).ljust(gut)[:gut])
    segs += s("c", str(n).rjust(4)) + s("", "  ")
    if mode == "inline" and n in T:
        cuts = sorted((at(text, a), ty) for a, ty, _ in T[n])
        k = 0
        for i, ty in cuts:
            segs += ts(text[k:i], IMPORTED, on)
            segs += s("vt", ": " + ty)
            k = i
        segs += ts(text[k:], IMPORTED, on)
    else:
        segs += ts(text, IMPORTED, on)
        if mode == "eol" and n in T:
            name = re.search(r"(?:const|let)\s+(\w+)|function\s+(\w+)|(\w+):\s*\(", text)
            label = "  ".join((("→ " if a.startswith("(") else "") + ty) for a, ty, _ in T[n])
            segs += s("", " " * max(3, 74 - lib.width(segs) + 6)) + s("vtc", label)
    return (segs, "ref" if lit else "")

def code_lines(mode, w, on=None, lit=(), gut=None):
    return [row(n, RUN[n - 1], mode, w, on, n in lit, gut) for n in range(FIRST, LAST + 1)]

def tabs(have, on):
    r = s("", " ")
    for t in have:
        r += s("tab bold" if t == on else "c", f" {t} ") + s("", "  ")
    return (r, "")

VIEWS = ["Code", "Types", "Built from", "Used by", "Map", "Changed"]

def decl(path, line, lit=(), upto=None):
    """the declaration at `line` with its doc comment above, as written"""
    L = src(path)
    a = line
    while a > 1 and (L[a - 2].strip().startswith(("*", "/**")) or L[a - 2].strip() == "*/"): a -= 1
    b = line
    if not L[line - 1].rstrip().endswith(";"):
        while not L[b - 1].startswith("}"): b += 1
    out = []
    com = False
    for n in range(a, (upto or b) + 1):
        t = L[n - 1]
        st = t.strip()
        if st.startswith("/**"): com = True
        r = s("c", str(n).rjust(4)) + s("", "  ")
        r += s("c it", t) if com or st.startswith("//") else ts(t)
        if com and st.endswith("*/"): com = False
        out.append((r, "ref" if n in lit else ""))
    if upto and upto < b: out.append((s("c", "     ⋯"), ""))
    return out

def head(name_seg, rest):
    return [(s("", " ") + name_seg + s("c", "   " + rest), ""), blank()[0]]

def sig(takes, name, gives):
    return (s("", " ") + s("pun", "(") + takes + s("pun", ")") + s("c", "  → ") + s("b", name) + s("c", " → ") + gives, "")

def ty(t): return s("ty", t)

def label(word, name, where):
    return (s("", " ") + s("c", word + " ") + s("ty bold", name) + s("c", "   " + where), "")

def screen(name, left, right, lw, status, trail="createRun()"):
    hd = [(s("c", " Seams › ") + s("fg bold", trail), ""), (s("d3", "─" * W), "")]
    n = max(len(left), len(right)) + 1
    scr = compose(hd, [(left + blank(n - len(left)), lw), (right + blank(n - len(right)), W - lw - 1)],
                  status, "<Tab> view   <C-Tab> display   J enter   K back")
    lib.write_shot(name, scr)

LEFT_HEAD = [(s("", " ") + s("b bold", "createRun") + s("pun", "()") + s("c", "   function in packages/core/src/run/run.ts:33"), ""), blank()[0]]
QUEUE_USES = {59, 65, 67, 71}

# ── 7a. a value's type where none is written; the cursor on `queue` ─────
qpane = head(s("fg bold", "queue"), "made by createQueue, line 37   used 12 times, 4 on screen") + [tabs(VIEWS, "Types"), blank()[0],
        label("is", "Queue", "type in packages/core/src/queue.ts:9")] + decl("queue.ts", 9)
for mode, lw, gut, cap in [("inline", 112, None, "a"), ("eol", 112, None, "b"), ("none", 120, 30, "c")]:
    left = LEFT_HEAD + code_lines(mode, lw, on="queue", lit=QUEUE_USES, gut=gut)
    screen(f"code-types-{cap}", left, qpane, lw, "createRun()  code   queue: Queue")

# ── 7b. the Code view's types display ───────────────────────────────────
def trow(ind, name, t, n, kind="fg"):
    r = s("", " " * ind) + s(kind, name)
    r += s("", " " * max(2, 18 - len(name) - ind + 2)) + t
    return (r, n)

def tline(rows, w):
    out = []
    for r, n in rows:
        if r is None: out.append(blank()[0]); continue
        if n: r = r + s("", " " * max(2, w - lib.width(r) - 6)) + s("c", str(n).rjust(4))
        out.append((r, ""))
    return out

def fn_head(ind, name, takes, gives, n):
    return (s("", " " * ind) + s("pun", "(") + takes + s("pun", ")") + s("c", " → ") + s("b bold" if ind == 1 else "b", name) + s("c", " → ") + gives, n)

P = lambda t: ts(t)
TY_ROWS = [
    fn_head(1, "createRun", s("fg", "options") + s("pun", ": ") + ty("RunOptions"), ty("Run"), 33),
    trow(3, "root", P("() => Document | Element"), 35),
    trow(3, "report", P("ReportProblem<Step>"), 36),
    trow(3, "queue", P("Queue"), 37),
    trow(3, "adapter", P("StorageAdapter | undefined"), 38),
    trow(3, "given", P("Given"), 41),
    trow(3, "model", P("Model"), 47),
    trow(3, "listeners", P("Set<(snapshot: RunSnapshot) => void>"), 48),
    trow(3, "handles", P("Map<ChecklistDefinition<AnyTask>, Handle>"), 49),
    trow(3, "runState", P("() => RunState"), 51),
    trow(3, "loading", P("() => boolean"), 52),
    trow(3, "getSnapshot", P("() => { … }"), 53),
    trow(3, "verdicts", P('Change["verdicts"]'), 55),
    trow(3, "send", P("(msg: Msg) => void"), 65),
    trow(3, "page", P("Page"), 67),
    trow(3, "link", P("Link"), 69),
    (None, None),
    fn_head(5, "loaded", s("fg", "read") + s("pun", ": ") + P('"failed" | Parsed'), ty("void"), 75),
    (None, None),
    fn_head(5, "heard", s("fg", "value") + s("pun", ": ") + ty("unknown"), ty("void"), 76),
    trow(7, "read", P("Parsed"), 77),
    (None, None),
    fn_head(5, "refused", s("fg", "error") + s("pun", ": ") + ty("RecordUnreadableError"), ty("void"), 81),
    (None, None),
    fn_head(3, "replace", s("fg", "replacement") + s("pun", ": ") + P("StoredRecord | null"), ty("void"), 85),
    trow(5, "parsed", P("Parsed"), 86),
    (None, None),
    fn_head(3, "step", s("fg", "msg") + s("pun", ": ") + ty("Msg"), ty("void"), 92),
    trow(5, "next", P("Updated"), 93),
    (None, None),
    fn_head(3, "perform", s("fg", "effects") + s("pun", ": ") + P("readonly Effect[]"), ty("void"), 98),
    trow(5, "effect", P("Effect"), 99),
]
lw = 112
left = [(s("", " ") + s("b bold", "createRun") + s("pun", "()") + s("c", "   function in packages/core/src/run/run.ts:33   ") + s("fg", "types"), ""), blank()[0]]
tl = tline(TY_ROWS, lw)
tl[3] = (tl[3][0], "vis")
left += tl
screen("code-types-only-a", left, qpane, lw, "createRun()  types   queue: Queue")

# B: the code with the lines that make no named value folded
def folded(w):
    keep = sorted(set(T) | {33, 41, 47, 48, 49, 55, 92, 98})
    out, prev = [], FIRST - 1
    for n in keep:
        if n > prev + 1:
            k = n - prev - 1
            out.append((s("c", "     ") + s("d3", f"⋯ {k} line" + ("s" if k > 1 else "")), ""))
        out.append(row(n, RUN[n - 1], "inline", w, on="queue", lit=n == 37))
        prev = n
    return out
left = LEFT_HEAD[:1] + [blank()[0]] + folded(lw)
screen("code-types-only-b", left, qpane, lw, "createRun()  folded   queue: Queue")

# ── 7d. the cursor on each kind of name: the right side, the Types view kept
def pane(title_seg, rest, body, h=34):
    p = head(title_seg, rest) + [tabs(VIEWS, "Types"), blank()[0]] + body
    return p[:h] + blank(max(0, h - len(p)))

call = pane(s("b bold", "runStateOf") + s("pun", "()"), "function in run/update.ts:14   called at line 51",
            [sig(ty("Model") + s("pun", ", ") + ty("Given"), "runStateOf", ty("RunState")), blank()[0],
             label("gives", "RunState", "type in state.ts:80")] + decl("state.ts", 80) + [blank()[0],
             label("takes", "Model", "type in state.ts:152")] + decl("state.ts", 152))
method = pane(s("fg bold", "queue") + s("pun", ".") + s("b bold", "fail"), "member of Queue, queue.ts:22   queue made at line 37",
              [sig(ty("CallbackName") + s("pun", ", ") + s("m", "unknown"), "fail", s("m", "void")), blank()[0],
               label("in", "Queue", "type in queue.ts:9")] + decl("queue.ts", 9, lit={21, 22}) + [blank()[0],
               label("takes", "CallbackName", "type in problems.ts:5")] + decl("problems.ts", 5))
param = pane(s("fg bold", "options"), "parameter of createRun, line 33   used 11 times",
             [label("is", "RunOptions", "type in run/types.ts:145")] + decl("run/types.ts", 145))
field = pane(s("fg bold", "options") + s("pun", ".") + s("pr bold", "storage"), "field of RunOptions, run/types.ts:153",
             [label("in", "RunOptions", "type in run/types.ts:145")] + decl("run/types.ts", 145, lit={148, 149, 150, 151, 152, 153}, upto=155) + [blank()[0],
              label("is", "StorageAdapter", "type in storage/adapter.ts:57")] + decl("storage/adapter.ts", 57))

def grid(name, panes, cw):
    hd = [(s("c", " Seams › ") + s("fg bold", "createRun()") + s("c", "   the right side, the Types view kept, with the cursor on four kinds of name"), ""), (s("d3", "─" * W), "")]
    (a, b), (c, d) = panes
    top = compose(hd, [(a, cw), (b, W - cw - 1)], "line 51 runStateOf          line 59 queue.fail", "")
    bot = compose([(s("d3", "─" * W), "")], [(c, cw), (d, W - cw - 1)], "line 33 options             line 38 options.storage", "")
    open(f"/tmp/seam-tree/v6/{name}.html", "w").write(
        f"<!doctype html><html><head><meta charset='utf-8'><style>{lib.SHOT_CSS}</style></head><body>{top}<br>{bot}</body></html>")

grid("code-cursor", [(call, method), (param, field)], 88)
print("ok")
