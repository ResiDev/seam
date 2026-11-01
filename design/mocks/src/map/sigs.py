# Round seven: both ways with the signatures in it. Five ways to draw what
# each function takes and gives inside the Map, on raf core's real calls
# and signatures, so Built from and Used by could fold into it.
#   python3 sigs.py <treesitter.json> <sigs.json> <raf core src>
#       -> /tmp/seam-tree/v6/maps-*.html, /tmp/seam-tree/v6/map-sigs.html
import sys, os, re, posixpath, collections, html as H
HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "ideas.py")).read()
# the facts and the canvas from ideas.py, none of its shots
exec(compile(src[:src.index("# ── 1. tree guides")], "ideas.py", "exec"))
lib.W = W = 200
LW = 44
PW = W - LW - 3
lib.SHOT_CSS = lib.SHOT_CSS.replace("width:1380px", "width:1640px")
SRCDIR = sys.argv[3]

# ── facts ───────────────────────────────────────────────────────────────
BUILTIN = {"string", "number", "boolean", "unknown", "void", "never", "any", "undefined", "null", "Record", "Set", "Error", "readonly"}
def tsegs(t, dim=False):
    """a type as pieces: the repo's types bright, builtins and punctuation dim"""
    out = []
    for m in re.finditer(r'("[^"]*"|[A-Za-z_$][\w$]*|[^"A-Za-z_$]+)', t):
        w = m.group(0)
        if w.startswith('"'): c = "g"
        elif re.match(r"[A-Za-z_$]", w): c = "c" if w in BUILTIN else ("ty" if w[0].isupper() else "fd")
        else: c = "c"
        out.append(("c" if dim and c != "ty" else c, w))
    return out
def tw(segs): return sum(len(t) for _, t in segs)
def where(p):
    d = posixpath.dirname(short(p)) if p.startswith(CORE) else posixpath.dirname(p.replace("packages/", ""))
    return (d + "/") if d else "core/src/ files"
def base(p): return posixpath.basename(p)
def callee_line(r, k): return next(l for c, l, _ in N[r]["calls"] if c == k)
def code_at(path, line):
    f = os.path.join(SRCDIR, short(path)) if path.startswith(CORE) else None
    if not f or not os.path.exists(f): return ""
    return open(f).read().split("\n")[line - 1].strip()
def full_sig(i):
    x = SIG.get((N[i]["path"], N[i]["name"]))
    if not x: return None
    ps = ", ".join(p["name"] + ("?" if p.get("optional") else "") + ": " + simple(p.get("type") or "unknown") for p in x["params"])
    return ps, sig(i)[1]
def label(i): return N[i]["name"] or "(top level)"

def sides(r, tests=False):
    left = [k for k in kids(r)]
    right = [c for c in CALLERS[r] if tests or not is_test(N[c]["path"])]
    return left, right
def by_file(ids):
    """ids grouped by folder then file, the folder with the most first"""
    g = collections.OrderedDict()
    for i in ids:
        g.setdefault(where(N[i]["path"]), collections.OrderedDict()).setdefault(N[i]["path"], []).append(i)
    return sorted(g.items(), key=lambda kv: -sum(len(v) for v in kv[1].values()))

# ── the screen ──────────────────────────────────────────────────────────
TABS = ["Code", "Types", "Built from", "Used by", "Map"]
def phead(title, rest, cur="both ways", tabs=TABS, opts=("both ways", "size")):
    r = s("", " ")
    for t in tabs: r += s("tab bold" if t == "Map" else "c", f" {t} ") + s("", "  ")
    r += s("", " ")
    for j, o in enumerate(opts):
        if j: r += s("d3", " · ")
        r += s("fg bold" if o == cur else "c", o)
    return [(s("", " ") + title + s("c", "   " + rest), ""), blank()[0], (r, ""), blank()[0]]
def tree(cursor, file="walkthroughs.ts", fns=("open", "verifyOne", "verifyAll", "start", "request", "act")):
    rows = [blank()[0]]
    T = [("packages/", 0, "fg"), ("core/src/", 1, "hcor"), ("▸ checklists/", 2, "fg"), ("run/", 2, "fg"), ("▸ input.ts", 3, "fg"),
         ("▸ record.ts", 3, "fg"), ("▸ run.ts", 3, "fg") if file != "run.ts" else None, (file, 3, "fg")]
    T = [t for t in T if t]
    T += [(f + "()", 4, "b") for f in fns]
    T += [("▸ update.ts", 3, "fg"), ("▸ storage/", 2, "fg"), ("▸ walkthrough/", 2, "fg"), ("problems.ts", 2, "fg"), ("queue.ts", 2, "fg")]
    for t, d, c in T:
        rows.append((s("", "  " + "  " * d) + s(c, t), "sel" if t == cursor else ""))
    return rows
SHOTS = []
def screen(name, title, cap, right, status, cursor, trail, keys="l show   T types   J code   <Tab> view   <C-Tab> display"):
    hd = [(s("c", " Seams › ") + s("fg bold", trail), ""), (s("d3", "─" * W), "")]
    left = tree(cursor) if "createRun" not in trail else tree(cursor, "run.ts", ("createRun",))
    n = max(len(left), len(right)) + 1
    body = compose(hd, [(left + blank(n - len(left)), LW), (right + blank(n - len(right)), PW + 2)], status, keys)
    lib.write_shot(name, body)
    SHOTS.append((name, title, cap, body))

VO = byname("verifyOne")
CR = byname("createRun")
def fhead(i):
    n = N[i]
    k = len(kids(i)); c = len(CALLERS[i])
    return (s("b bold", n["name"]) + s("pun", "()"),
            f"function in {short(n['path'])}:{n['line']}   called by {c}, calls {k}")

# ── A. the wires carry the types ────────────────────────────────────────
# one function a line, gathered under its file; what it takes after its
# name, what it gives written on its line into the row, a bare line when it
# gives nothing. The row's own: what it takes under it, what it gives on the
# line out to its callers.
def wires(r, cursor=None):
    L, R = sides(r)
    def lines(ids, side):
        out = []
        for d, files in by_file(ids):
            if out: out.append(None)
            out.append(("head", s("fg bold", d)))  # a folder
            for p, fs in files.items():
                for k, i in enumerate(fs): out.append(("fn", i, base(p) if k == 0 else ""))
        return out
    def rlines(ids):
        out = []
        for d, files in by_file(ids):
            for p, fs in files.items():
                if out: out.append(None)
                out.append(("head", s("fg bold", d if not d.endswith(" files") else d[:-6]) + s("fd", base(p))))
                for i in fs: out.append(("fn", i, ""))
        return out
    lL, lR = lines(L, "l"), rlines(R)
    def takes(i):
        x = sig(i, 20)
        return tsegs("(" + x[0] + ")", dim=True) if x else []
    def gives(i):
        x = sig(i, 20)
        return cut(x[1], 18) if x else None
    fw = max([len(base(N[i]["path"])) for i in L] + [0]) + 2
    nw = max([len(label(i)) for i in L] + [0])
    tk = max([tw(takes(i)) for i in L] + [0])
    gx = 2 + fw + nw + 1 + tk + 4
    gw = max([len(gives(i) or "") for i in L] + [0])
    bus = gx + gw + 2
    n = max(len(lL), len(lR)) + 2
    mid = n // 2
    cv = Canvas(PW, n)
    l0 = mid - len(lL) // 2; r0 = mid - len(lR) // 2
    ys = []
    for j, ln in enumerate(lL):
        y = l0 + j
        if ln is None: continue
        if ln[0] == "head": cv.seg(ln[1], 0, y); continue
        i = ln[1]
        cv.put(2, y, ln[2], "fd")
        x = cv.seg(s("b vis" if label(i) == cursor else "b", label(i)), 2 + fw, y)
        x = cv.seg(takes(i), 2 + fw + nw + 1, y)
        cv.h(x + 1, bus, y); ys.append(y)
        g = gives(i)
        if g and g != "void": cv.seg(s("", " ") + tsegs(cut(g, 26)) + s("", " "), gx - 1, y)
    cv.v(bus, min(ys + [mid]), max(ys + [mid])); cv.h(bus, bus + 3, mid)
    cx = bus + 4
    nm = N[r]["name"]
    cv.put(cx, mid, nm, "b bold")
    t, g = sig(r, 40)
    t = cut(t, 20)
    cv.seg(tsegs("(" + t + ")", dim=True), cx, mid + 1)
    ox = cx + len(nm) + 1
    gl = s("", " ") + tsegs(g) + s("", " ")
    bx = max(ox + 2 + tw(gl) + 2, cx + len(t) + 4)
    cv.h(ox, bx, mid); cv.seg(gl, ox + 2, mid)
    ys = []
    for j, ln in enumerate(lR):
        y = r0 + j
        if ln is None: continue
        if ln[0] == "head": cv.seg(ln[1], bx + 2, y); continue
        i = ln[1]
        cv.h(bx, bx + 3, y); ys.append(y)
        x = cv.seg(s("b vis" if label(i) == cursor else "b", label(i)), bx + 4, y)
        x2 = sig(i, 22)
        if x2: cv.seg(tsegs("(" + x2[0] + ") → " + cut(x2[1], 14), dim=True), x + 1, y)
    cv.v(bx, min(ys + [mid]), max(ys + [mid]))
    return cv.rows()

# ── B. gathered by what each gives ──────────────────────────────────────
# today's Map with the type in the file's place: each side's functions
# gathered under the type they give, the repo's types first, builtins
# after, nothing given last; each type's names after it, a line a type.
def by_gives(r):
    L, R = sides(r)
    def groups(ids):
        g = collections.OrderedDict()
        for i in ids:
            x = sig(i, 30)
            k = x[1] if x else "?"
            g.setdefault(k, []).append(i)
        def rank(k):
            words = re.findall(r"[A-Za-z_$][\w$]*", k)
            repo = any(w[0].isupper() and w not in BUILTIN for w in words)
            return (0 if repo else 2 if k in ("void", "?") else 1, -len(g[k]))
        return sorted(g.items(), key=lambda kv: rank(kv[0]))
    gL, gR = groups(L), groups(R)
    def line(k, ids, kw):
        tseg = s("c", "nothing") if k == "void" else s("c", "?") if k == "?" else tsegs(cut(k, 24))
        out = tseg + s("", " " * (kw + 2 - tw(tseg)))
        for j, i in enumerate(ids):
            if j: out += s("", "  ")
            out += s("b", label(i))
        return out
    def shown(k): return 7 if k == "void" else len(cut(k, 24))
    kl = max(shown(k) for k, _ in gL); kr = max(shown(k) for k, _ in gR)
    lL = [line(k, v, kl) for k, v in gL]; lR = [line(k, v, kr) for k, v in gR]
    lw = max(tw(x) for x in lL)
    n = max(len(lL), len(lR)) + 2
    mid = n // 2
    cv = Canvas(PW, n)
    l0 = mid - len(lL) // 2; r0 = mid - len(lR) // 2
    bus = lw + 2; ys = []
    for j, x in enumerate(lL):
        e = cv.seg(x, 0, l0 + j); cv.h(e + 1, bus, l0 + j); ys.append(l0 + j)
    cv.v(bus, min(ys + [mid]), max(ys + [mid])); cv.h(bus, bus + 3, mid)
    cx = bus + 4; nm = N[r]["name"]
    cv.put(cx, mid, nm, "b bold")
    t, g = sig(r, 40)
    cv.seg(tsegs("(" + t + ") → " + g, dim=True), cx, mid + 1)
    bx = cx + len(nm) + 1; ys = []
    r0 = mid - len(lR)  # above the row's signature
    for j, x in enumerate(lR):
        y = r0 + j; cv.h(bx + 3, bx + 5, y); ys.append(y); cv.seg(x, bx + 6, y)
    cv.h(bx, bx + 3, mid); cv.v(bx + 3, min(ys + [mid]), max(ys + [mid]))
    return cv.rows()

# ── C. top to bottom, the signature in columns ──────────────────────────
# built from above, the row, used by below, each function a line: its
# name, what it takes, what it gives, each in a column so the eye runs
# down them, its file and line at the right. One line down the left joins
# them to the row.
def columns(r, cursor=None):
    L, R = sides(r)
    def tk(i):
        x = sig(i, 44)
        return "(" + x[0] + ")" if x else ""
    def gv(i):
        x = sig(i, 44)
        return cut(x[1], 26) if x else ""
    allids = L + R + [r]
    nw = max(len(label(i)) for i in allids)
    tkw = max(len(tk(i)) for i in allids)
    gvw = max(len(gv(i)) for i in allids) + 2
    def fn_row(i, lead, bold=False):
        row = s("c", lead) + s("b bold" if bold else ("b vis" if label(i) == cursor else "b"), label(i).ljust(nw)) + s("", "  ")
        t = tsegs(tk(i), dim=not bold); row += t + s("", " " * (tkw - tw(t) + 2))
        g = tsegs(gv(i)) if gv(i) else []
        row += s("c", "→ " if g else "  ") + g + s("", " " * (gvw - tw(g)))
        return row
    rows = []
    def side(ids, top):
        # built from in the order the body calls them, the line of each call
        # in the gutter as code numbers its lines, where each lives at the
        # right; used by by file, each caller's file and line at the right
        if top:
            flat = sorted(ids, key=lambda i: callee_line(r, i))
        else:
            flat = [i for _, files in by_file(ids) for fs in files.values() for i in fs]
        for k, i in enumerate(flat):
            first, last = k == 0, k == len(flat) - 1
            lead = ("┌╴ " if first else "├╴ ") if top else ("├╴ " if not last else "└╴ ")
            gut = str(callee_line(r, i)).rjust(4) + " " if top else "     "
            row = s("c", gut) + fn_row(i, lead)
            if top:
                row += s("fd", base(N[i]["path"]))
            else:
                row += s("fd", base(N[i]["path"])) + s("c", f":{callee_line(i, r)}")
            rows.append((row, "sel" if label(i) == cursor else ""))
    rows.append((s("c", "        built from"), ""))
    side(L, True)
    rows.append((s("c", "     │"), ""))
    rows.append((s("c", str(N[r]["line"]).rjust(4) + " ") + fn_row(r, "●  ", bold=True) + s("fd", base(N[r]["path"])), ""))
    rows.append((s("c", "     │"), ""))
    rows.append((s("c", "        used by"), ""))
    side(R, False)
    return rows

# ── D. each name over what it gives ─────────────────────────────────────
# today's Map, each name with what it gives under it, the two as one cell
def chips(r):
    L, R = sides(r)
    def side(ids, room):
        out = []
        for d, files in by_file(ids):
            if out: out.append(([], [], False))
            out.append((s("fg bold", d), [], False))
            mf = max(len(base(p)) for p in files)
            for p, fs in files.items():
                cells = []
                for i in fs:
                    g = (sig(i, 22) or (None, "?"))[1]
                    g = "nothing" if g == "void" else cut(g, 22)
                    cells.append((label(i), g, max(len(label(i)), len(g))))
                rowsets, cur, w = [], [], 0
                for c in cells:
                    if cur and w + c[2] + 2 > room - mf - 4: rowsets.append(cur); cur, w = [], 0
                    cur.append(c); w += c[2] + 2
                rowsets.append(cur)
                for k, rs in enumerate(rowsets):
                    a = s("", "  ") + s("fd", (base(p) if k == 0 else "").ljust(mf + 2))
                    b = s("", " " * (mf + 4))
                    for nm, g, cw in rs:
                        a += s("b", nm.ljust(cw + 2))
                        b += (s("c", g) if g in ("nothing", "?") else tsegs(g, dim=True)) + s("", " " * (cw + 2 - len(g)))
                    out.append((a, b, k == 0))
        return out
    room = (PW - 30) // 2
    lL, lR = side(L, room), side(R, room)
    def rowsof(lines):
        out = []
        for a, b, j in lines:
            out.append((a, j))
            if b: out.append((b, False))
        return out
    lL, lR = rowsof(lL), rowsof(lR)
    lw = max(tw(a) for a, _ in lL)
    n = max(len(lL), len(lR)) + 1; mid = n // 2
    cv = Canvas(PW, n)
    l0 = mid - len(lL) // 2; r0 = mid - len(lR) // 2
    bus = lw + 2; ys = []
    for j, (a, jn) in enumerate(lL):
        e = cv.seg(a, 0, l0 + j)
        if jn: cv.h(len("".join(t for _, t in a).rstrip()) + 1, bus, l0 + j); ys.append(l0 + j)
    cv.v(bus, min(ys + [mid]), max(ys + [mid])); cv.h(bus, bus + 3, mid)
    cx = bus + 4; nm = N[r]["name"]
    cv.put(cx, mid, nm, "b bold")
    t, g = sig(r, 40)
    cv.seg(tsegs(g, dim=True), cx, mid + 1)
    bx = cx + len(nm) + 1; ys = []
    for j, (a, jn) in enumerate(lR):
        y = r0 + j
        if jn: cv.h(bx + 3, bx + 5, y); ys.append(y)
        cv.seg(a, bx + 4, y)
    cv.h(bx, bx + 3, mid); cv.v(bx + 3, min(ys + [mid]), max(ys + [mid]))
    return cv.rows()

# ── E. today's Map, the one under the cursor told at the foot ───────────
def today(r, cursor):
    L, R = sides(r)
    def side(ids, room):
        out = []
        for d, files in by_file(ids):
            if out: out.append(([], False))
            out.append((s("fg bold", d), False))
            mf = max(len(base(p)) for p in files)
            for p, fs in files.items():
                row = s("", "  ") + s("fd", base(p).ljust(mf + 2))
                for j, i in enumerate(fs):
                    if j: row += s("", "  ")
                    row += s("b vis" if label(i) == cursor else "b", label(i))
                out.append((row, True))
        return out
    lL, lR = side(L, 80), side(R, 80)
    lw = max(tw(a) for a, _ in lL)
    n = max(len(lL), len(lR)) + 1; mid = n // 2
    cv = Canvas(PW, n)
    l0 = mid - len(lL) // 2; r0 = mid - len(lR) // 2
    bus = lw + 2; ys = []
    for j, (a, jn) in enumerate(lL):
        e = cv.seg(a, 0, l0 + j)
        if jn: cv.h(e + 1, bus, l0 + j); ys.append(l0 + j)
    cv.v(bus, min(ys + [mid]), max(ys + [mid])); cv.h(bus, bus + 3, mid)
    cx = bus + 4; nm = N[r]["name"]
    cv.put(cx, mid, nm, "b bold")
    bx = cx + len(nm) + 1; ys = []
    for j, (a, jn) in enumerate(lR):
        y = r0 + j
        if jn: cv.h(bx + 3, bx + 5, y); ys.append(y)
        cv.seg(a, bx + 6, y)
    cv.h(bx, bx + 3, mid); cv.v(bx + 3, min(ys + [mid]), max(ys + [mid]))
    return cv.rows() + foot(r, cursor)

def foot(r, cursor):
    """the name under the cursor at the foot: its whole signature, then the
    line that calls it, as Used by and Built from write a place"""
    i = next(k for k in kids(r) + CALLERS[r] if label(k) == cursor)
    inside = i in kids(r)
    ps, g = full_sig(i)
    caller = r if inside else i
    ln = callee_line(r, i) if inside else callee_line(i, r)
    line = code_at(N[caller]["path"], ln)
    at = f"{base(N[caller]['path'])}:{ln}"
    rows = [blank()[0], (s("d3", " " + "─" * PW), "")]
    rows.append((s("", " ") + s("b bold", label(i)) + s("pun", "(") + tsegs(ps) + s("pun", ")") + s("c", " → ") + tsegs(g) +
                 s("c", "   " + short(N[i]["path"]) + ":" + str(N[i]["line"])), ""))
    code = s("", " ") + s("c", at.ljust(22)) + ts(line, on=N[i]["name"] if inside else N[r]["name"])
    pad = PW - tw(code) - len("in " + label(caller))
    rows.append((code + s("", " " * max(pad, 2)) + s("c", "in ") + s("b", label(caller)), ""))
    return rows

# ── the shots ───────────────────────────────────────────────────────────
t, rest = fhead(VO)
screen("maps-a-wires", "A. The lines carry the types",
       "One function a line under its file. What it takes after its name, dim; what it gives written on its line into verifyOne, so the column by the join is everything verifyOne gets back. A bare line gives nothing. verifyOne's own: what it takes under it, what it gives on the line out to its callers. The cursor's call at the foot.",
       phead(t, rest) + wires(VO, cursor="verified") + foot(VO, "verified"),
       "verifyOne()  map · both ways", "verifyOne()", "verifyOne()")
screen("maps-b-gives", "B. Gathered by what each gives",
       "Today's Map with the type where the file was: each side's functions under the type they give, the repo's types first. Reads as: verifyOne turns these into RunState, asks these for a boolean, and so on. The files go to the foot.",
       phead(t, rest) + by_gives(VO),
       "verifyOne()  map · both ways", "verifyOne()", "verifyOne()")
screen("maps-c-columns", "C. Top to bottom, the signatures in columns",
       "Built from above, verifyOne, used by below, the order of the tabs. Each function a line: name, takes, gives, each in a column; its file and the line of the call at the right. The full width goes to the signatures, so nothing is cut.",
       phead(t, rest) + columns(VO, cursor="verified"),
       "verifyOne()  map · both ways", "verifyOne()", "verifyOne()")
screen("maps-d-chips", "D. Each name over what it gives",
       "Today's Map, each name with the type it gives under it, the two one cell. Takes stay in the foot.",
       phead(t, rest) + chips(VO),
       "verifyOne()  map · both ways", "verifyOne()", "verifyOne()")
screen("maps-e-foot", "E. Today's Map, the cursor's signature and call at the foot",
       "The Map as it is; the name under the cursor told in full at the foot: its signature with the parameter names, then the line that calls it, as Used by writes a place.",
       phead(t, rest) + today(VO, "verified"),
       "verifyOne()  map · both ways", "verifyOne()", "verifyOne()")
t, rest = fhead(CR)
screen("maps-a-wires-big", "A on createRun, 17 calls",
       "The same, on a function with many calls.",
       phead(t, rest) + wires(CR),
       "createRun()  map · both ways", "createRun()", "createRun()")
screen("maps-b-gives-big", "B on createRun",
       "The same, on a function with many calls.",
       phead(t, rest) + by_gives(CR),
       "createRun()  map · both ways", "createRun()", "createRun()")
screen("maps-c-columns-big", "C on createRun",
       "The same, on a function with many calls.",
       phead(t, rest) + columns(CR),
       "createRun()  map · both ways", "createRun()", "createRun()")

# ── round eight: Built from, Used by and size go; the Map has folder and type
TABS8 = ["Code", "Types", "Map"]
OPTS8 = ("folder", "type")
def phead8(r, cur, opts=OPTS8):
    a, b = fhead(r)
    return phead(a, b, cur, tabs=TABS8, opts=opts)

# type: each side gathered by the type its functions give, the repo's types
# first; a line for each file under a type, its folder and file, then its
# names; a line from each into the row. The row's own signature under it.
def by_type(r, cursor=None):
    L, R = sides(r)
    def lines(ids):
        g = collections.OrderedDict()
        for i in ids:
            x = sig(i, 30)
            k = x[1] if x else "?"
            g.setdefault(k, collections.OrderedDict()).setdefault(N[i]["path"], []).append(i)
        def rank(k):
            words = re.findall(r"[A-Za-z_$][\w$]*", k)
            repo = any(w[0].isupper() and w not in BUILTIN for w in words)
            return (0 if repo else 2 if k in ("void", "?") else 1, -sum(len(v) for v in g[k].values()))
        out = []
        for k, files in sorted(g.items(), key=lambda kv: rank(kv[0])):
            for j, (p, fs) in enumerate(files.items()):
                ty = [] if j else (s("c", "nothing") if k == "void" else s("c", "?") if k == "?" else tsegs(cut(k, 24)))
                d = where(p)
                d = d[:-6] if d.endswith(" files") else d
                out.append((ty, s("c", d) + s("fd", base(p)), fs))
        return out
    def render(lines_):
        kw = max(tw(a) for a, _, _ in lines_)
        pw = max(tw(b) for _, b, _ in lines_)
        rows = []
        for a, b, fs in lines_:
            row = a + s("", " " * (kw + 2 - tw(a))) + b + s("", " " * (pw + 2 - tw(b)))
            for j, i in enumerate(fs):
                if j: row += s("", "  ")
                row += s("b vis" if label(i) == cursor else "b", label(i))
            rows.append(row)
        return rows
    lL, lR = render(lines(L)), render(lines(R))
    lw = max(tw(x) for x in lL)
    n = max(len(lL), len(lR) * 2 + 2, 3); mid = n // 2
    cv = Canvas(PW, n)
    l0 = mid - len(lL) // 2
    bus = lw + 2; ys = []
    for j, x in enumerate(lL):
        e = cv.seg(x, 0, l0 + j); cv.h(e + 1, bus, l0 + j); ys.append(l0 + j)
    cv.v(bus, min(ys + [mid]), max(ys + [mid])); cv.h(bus, bus + 3, mid)
    cx = bus + 4; nm = N[r]["name"]
    cv.put(cx, mid, nm, "b bold")
    t_, g_ = sig(r, 40)
    cv.seg(tsegs("(" + t_ + ") → " + g_, dim=True), cx, mid + 1)
    bx = cx + len(nm) + 1; ys = []
    r0 = mid - len(lR) + (1 if len(lR) > 1 else 0) - (1 if len(lR) > 2 else 0)
    r0 = min(r0, mid)
    for j, x in enumerate(lR):
        y = r0 + j
        if y == mid + 1: y = r0 + j  # the row's signature sits under it, left of here
        cv.h(bx + 3, bx + 5, y); ys.append(y); cv.seg(x, bx + 6, y)
    cv.h(bx, bx + 3, mid); cv.v(bx + 3, min(ys + [mid]), max(ys + [mid]))
    return cv.rows()

# C as a map: calls above, flowing down a line into the row; the row
# writing what it takes, its name, what it gives; what it gives flowing on
# to its callers below, set off to the right where its output ends. Each
# call's line in the gutter, each name's signature in columns.
def flow(r, cursor=None):
    L, R = sides(r)
    def tk(i, w=44):
        x = sig(i, w)
        return "(" + x[0] + ")" if x else ""
    def gv(i):
        x = sig(i, 44)
        return cut(x[1], 26) if x else ""
    calls = sorted(L, key=lambda i: callee_line(r, i))
    nw = max(len(label(i)) for i in calls)
    tkw = max(len(tk(i)) for i in calls)
    gvw = max(len(gv(i)) for i in calls)
    fw = max(len(base(N[i]["path"])) for i in calls)
    rows = []
    G0 = 5  # the gutter
    for k, i in enumerate(calls):
        lead = "┌╴ " if k == 0 else "├╴ "
        row = s("c", str(callee_line(r, i)).rjust(4) + " ") + s("c", lead)
        row += s("b vis" if label(i) == cursor else "b", label(i).ljust(nw + 2))
        tt = tsegs(tk(i), dim=True); row += tt + s("", " " * (tkw - tw(tt) + 2))
        g = gv(i)
        gg = (s("c", "→ ") + tsegs(g)) if g and g != "void" else s("c", "  nothing" if g == "void" else "")
        row += gg + s("", " " * (gvw + 4 - tw(gg))) + s("fd", base(N[i]["path"]))
        rows.append((row, "sel" if label(i) == cursor else ""))
    rows.append((s("c", " " * G0 + "│"), ""))
    t_, g_ = sig(r, 60)
    centre = s("c", str(N[r]["line"]).rjust(4) + " ") + s("c", "└──▶ ") + tsegs("(" + t_ + ")") + s("c", " → ") + s("b bold", N[r]["name"]) + s("c", " → ") + tsegs(g_) + s("c", " ──┐")
    rows.append((centre, ""))
    bx = tw(centre) - 1
    callers = [i for _, files in by_file(R) for fs in files.values() for i in fs]
    cnw = max([len(label(i)) for i in callers] + [0])
    ctk = max([len(tk(i, 30)) for i in callers] + [0])
    cgw = max([len(cut(sig(i, 30)[1], 16)) for i in callers if sig(i, 30)] + [0])
    for k, i in enumerate(callers):
        last = k == len(callers) - 1
        row = s("", " " * bx) + s("c", "└──▶ " if last else "├──▶ ")
        row += s("b vis" if label(i) == cursor else "b", label(i).ljust(cnw + 2))
        x = sig(i, 30)
        if x:
            tt = tsegs("(" + x[0] + ")", dim=True)
            row += tt + s("", " " * (ctk - tw(tt) + 2)) + s("c", "→ ") + tsegs(cut(x[1], 16), dim=True) + s("", " " * (cgw + 2 - len(cut(x[1], 16))))
        else:
            row += s("", " " * (ctk + cgw + 6))
        row += s("fd", base(N[i]["path"])) + s("c", f":{callee_line(i, r)}")
        rows.append((row, "sel" if label(i) == cursor else ""))
    return rows

r8 = []
def screen8(name, title, cap, r, body, cur, cursor, opts=OPTS8):
    nm = N[r]["name"] + "()"
    screen(name, title, cap, phead8(r, cur, opts) + body, f"{nm}  map · {cur}", nm, nm, keys="l show   J code   <Tab> view   <C-Tab> display")
    r8.append(name)
screen8("map8-folder", "folder: today's both ways, the cursor's signature and call at the foot",
        "The Map as it is, by folder and file. The name under the cursor told at the foot: its signature with the parameter names, then the line that calls it, and what that line sits in.",
        VO, today(VO, "verified"), "folder", "verified")
screen8("map8-type", "type: gathered by what each gives, with its folder and file",
        "Each side gathered by the type its functions give, the repo's types first. A line for each file under a type: the type, the folder and file, the names. The cursor's signature and call at the foot.",
        VO, by_type(VO, "verified") + foot(VO, "verified"), "type", "verified")
screen8("map8-type-big", "type on createRun, 17 calls",
        "Where every call gives a type of its own, a line a call: the type, where it lives, its name.",
        CR, by_type(CR, "update") + foot(CR, "update"), "type", "update")
screen8("map8-flow", "C as a map: what it calls flowing into it, what it gives flowing on",
        "The calls above in the order the body makes them, a line down from them into verifyOne, written as what it takes → verifyOne → what it gives; from there on to its callers, set off to the right where its output ends. Each signature in full, in columns.",
        VO, flow(VO, "verified") + foot(VO, "verified"), "flow", "verified", opts=("folder", "type", "flow"))
screen8("map8-flow-big", "C as a map on createRun",
        "The same with 17 calls.",
        CR, flow(CR), "flow", None, opts=("folder", "type", "flow"))

UP = byname("update", "run/update.ts")
screen8("map8-type-files", "type, a type given from two files",
        "update's calls: Work comes from run/update.ts and from run/walkthroughs.ts, a line for each file, the type written once.",
        UP, by_type(UP) , "type", None)

# ── round nine: C grouped, by type and by folder; a type's foot ─────────
def decl_of(name):
    """a type's declaration as written, from the source: its file, line, lines"""
    for root, _, files in os.walk(SRCDIR):
        for f in files:
            if not f.endswith((".ts", ".tsx")) or ".test." in f: continue
            path = os.path.join(root, f)
            L = open(path).read().split("\n")
            for k, l in enumerate(L):
                if re.match(r"export (type|interface) " + name + r"\b", l):
                    out, depth = [], 0
                    for l2 in L[k:]:
                        out.append(l2)
                        depth += l2.count("{") - l2.count("}")
                        if depth <= 0 and (l2.rstrip().endswith((";", "}", ">;", "}>;")) or depth == 0 and len(out) > 1): break
                    return os.path.relpath(path, SRCDIR), k + 1, out
    return None
def type_flow(name):
    gives = [i for i in N if sig(i) and re.search(r"\b" + name + r"\b", SIG[(N[i]["path"], N[i]["name"])].get("ret") or "") and not is_test(N[i]["path"])]
    takes = [i for i in N if (N[i]["path"], N[i]["name"]) in SIG and any(re.search(r"\b" + name + r"\b", q.get("type") or "") for q in SIG[(N[i]["path"], N[i]["name"])]["params"]) and not is_test(N[i]["path"])]
    return gives, takes
def type_foot(name, cap=7):
    path, line, lines = decl_of(name)
    gives, takes = type_flow(name)
    rows = [blank()[0], (s("d3", " " + "─" * PW), "")]
    rows.append((s("", " ") + s("ty bold", name) + s("c", f"   type in {path}:{line}   made by {len(gives)}, taken by {len(takes)}"), ""))
    src = re.sub(r"/\*.*?\*/\s*", "", "\n".join(lines), flags=re.S).split("\n")
    src = [l for l in src if l.strip() and not l.strip().startswith("//")]
    lines = src
    for l in lines[:cap]:
        rows.append((s("", " ") + ts(l), ""))
    if len(lines) > cap:
        rows.append((s("c", f" ⋯ {len(lines) - cap} more lines"), ""))
    return rows

def gflow(r, key, cursor=None):
    """C grouped: what it calls above under a head, by the type each gives or
    by folder; a line down the left through the heads into the row; the row
    as what it takes → its name → what it gives; on from there to its
    callers, grouped the same way, set off where its output ends"""
    L, R = sides(r)
    def tk(i, w=44):
        x = sig(i, w)
        return "(" + x[0] + ")" if x else ""
    def gv(i):
        x = sig(i, 44)
        return cut(x[1], 26) if x else ""
    def gkey(i):
        if key == "type":
            g = gv(i)
            return "void" if g == "void" else (g or "?")
        return where(N[i]["path"])
    def head_segs(k):
        if key == "type":
            if k == "void": return s("c", "nothing")
            if k == "?": return s("c", "?")
            return tsegs(k)
        return s("fg bold", k[:-6] if k.endswith(" files") else k)
    def rank_type(k, n):
        words = re.findall(r"[A-Za-z_$][\w$]*", k)
        repo = any(w[0].isupper() and w not in BUILTIN for w in words)
        return (0 if repo else 2 if k in ("void", "?") else 1, -n)
    def groups(ids, order):
        g = collections.OrderedDict()
        for i in sorted(ids, key=order): g.setdefault(gkey(i), []).append(i)
        if key == "type": return sorted(g.items(), key=lambda kv: rank_type(kv[0], len(kv[1])))
        return sorted(g.items(), key=lambda kv: -len(kv[1]))
    def place(i):
        d = where(N[i]["path"]); d = d[:-6] if d.endswith(" files") else d
        return d, base(N[i]["path"])
    calls = groups(L, (lambda i: callee_line(r, i)) if key == "type" else (lambda i: (N[i]["path"], callee_line(r, i))))
    allc = [i for _, v in calls for i in v]
    nw = max(len(label(i)) for i in allc)
    tkw = max(len(tk(i)) for i in allc)
    gvw = max(len(gv(i)) for i in allc)
    fw = max(len(base(N[i]["path"])) for i in allc)
    pw = max(sum(map(len, place(i))) for i in allc)
    rows = []
    for gi, (k, ids) in enumerate(calls):
        hd = head_segs(k)
        lead = "┌─ " if gi == 0 else "├─ "
        rows.append((s("", "     ") + s("c", lead) + hd, "sel" if k == cursor else ""))
        prevf = None
        for i in ids:
            row = s("c", str(callee_line(r, i)).rjust(4) + " ") + s("c", "│    ")
            if key == "folder":
                f = base(N[i]["path"])
                row += s("fd", (f if f != prevf else "").ljust(fw + 2)); prevf = f
            row += s("b vis" if label(i) == cursor else "b", label(i).ljust(nw + 2))
            tt = tsegs(tk(i), dim=True); row += tt + s("", " " * (tkw - tw(tt) + 2))
            if key == "folder":
                g = gv(i)
                gg = (s("c", "→ ") + tsegs(g)) if g and g != "void" else s("c", "  nothing" if g == "void" else "")
                row += gg
            else:
                d, f = place(i)
                row += s("c", d) + s("fd", f)
            rows.append((row, "sel" if label(i) == cursor else ""))
    rows.append((s("c", "     │"), ""))
    t_, g_ = sig(r, 60)
    centre = s("c", str(N[r]["line"]).rjust(4) + " ") + s("c", "└──▶ ") + tsegs("(" + t_ + ")") + s("c", " → ") + s("b bold", N[r]["name"]) + s("c", " → ") + tsegs(g_) + s("c", " ──┐")
    rows.append((centre, ""))
    bx = tw(centre) - 1
    cg = groups(R, lambda i: (N[i]["path"], callee_line(i, r)))
    allr = [i for _, v in cg for i in v]
    cnw = max([len(label(i)) for i in allr] + [0])
    ctk = max([len(tk(i, 30)) for i in allr] + [0])
    for gi, (k, ids) in enumerate(cg):
        last = gi == len(cg) - 1
        rows.append((s("", " " * bx) + s("c", "└─ " if last else "├─ ") + head_segs(k), "sel" if k == cursor else ""))
        bar = "   " if last else "│  "
        for i in ids:
            row = s("", " " * bx) + s("c", bar + "  ")
            row += s("b vis" if label(i) == cursor else "b", label(i).ljust(cnw + 2))
            x = sig(i, 30)
            tt = tsegs("(" + x[0] + ")", dim=True) if x else []
            row += tt + s("", " " * (ctk - tw(tt) + 2))
            if key == "folder" and x:
                row += s("c", "→ ") + tsegs(cut(x[1], 16), dim=True) + s("", "  ")
            row += s("fd", base(N[i]["path"])) + s("c", f":{callee_line(i, r)}")
            rows.append((row, "sel" if label(i) == cursor else ""))
    return rows

O9 = ("folder", "type")
screen8("map9-type", "C grouped by type: what each gives as the head, then its name, what it takes, where it lives",
        "verifyOne's calls under the type each gives, the repo's types first; a line down the left through the types into verifyOne, written as what it takes → verifyOne → what it gives; its callers grouped by what they give, set off where its output ends. The cursor on a name: its signature and call at the foot.",
        VO, gflow(VO, "type", "verified") + foot(VO, "verified"), "type", "verified", opts=O9)
screen8("map9-type-cursor-type", "C grouped by type, the cursor on a type",
        "The cursor on UserRecord: its declaration as written at the foot, where it is, how many make and take it.",
        VO, gflow(VO, "type", "UserRecord") + type_foot("UserRecord"), "type", "UserRecord", opts=O9)
screen8("map9-folder", "C grouped by folder: each folder the head, then file, name, takes, gives",
        "The same flow by folder: each call's file, name, what it takes and what it gives, in columns.",
        VO, gflow(VO, "folder", "verified") + foot(VO, "verified"), "folder", "verified", opts=O9)
screen8("map9-type-big", "C grouped by type on update, 17 calls",
        "Work given from two files, one head over both.",
        UP, gflow(UP, "type"), "type", None, opts=O9)
screen8("map9-folder-big", "C grouped by folder on createRun",
        "The same by folder.",
        CR, gflow(CR, "folder"), "folder", None, opts=O9)

# ── round ten: the flow in a narrow pane (105 columns) ──────────────────
NW = 105
def split_params(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "<({[": depth += 1
        if ch in ">)}]": depth -= 1
        if ch == "," and depth == 0: out.append(cur.strip()); cur = ""
        else: cur += ch
    if cur.strip(): out.append(cur.strip())
    return out
def raw_sig(i):
    x = SIG.get((N[i]["path"], N[i]["name"]))
    if not x: return None
    def part(p):
        t = simple(p.get("type") or p["name"])
        return "{ … }" if t.startswith("{") else t
    takes = ", ".join(part(p) for p in x["params"])
    g = sig(i, 200)[1]
    return takes, g
def narrow(r, mode, W=NW):
    """the flow by folder fitted to W columns: 'fit' cuts what it takes to
    the room left, what it gives whole; 'wrap' carries what it takes on to
    lines under it; 'ragged' writes what it gives straight after"""
    L, R = sides(r)
    home_calls = sorted(L, key=lambda i: (N[i]["path"], callee_line(r, i)))
    groups = collections.OrderedDict()
    for i in home_calls: groups.setdefault(where(N[i]["path"]), []).append(i)
    groups = sorted(groups.items(), key=lambda kv: -len(kv[1]))
    fw = max(len(base(N[i]["path"])) for i in L)
    nw = max(len(label(i)) for i in L)
    lead = 5 + 5          # gutter, the line and its indent
    x0 = lead + fw + 2 + nw + 2
    def gv(i):
        s_ = raw_sig(i); g = s_[1] if s_ else ""
        return "nothing" if g == "void" else g
    gw = min(max(len(gv(i)) for i in L) + 2, 28)
    room = W - x0 - gw - 2
    rows = []
    for gi, (d, ids) in enumerate(groups):
        rows.append((s("", "     ") + s("c", "┌─ " if gi == 0 else "├─ ") + s("fg bold", d[:-6] if d.endswith(" files") else d), ""))
        prev = None
        for i in ids:
            s_ = raw_sig(i); tk = "(" + s_[0] + ")" if s_ else ""
            g = gv(i)
            f = base(N[i]["path"])
            head = s("c", str(callee_line(r, i)).rjust(4) + " ") + s("c", "│    ") + s("fd", (f if f != prev else "").ljust(fw + 2)) + s("b", label(i).ljust(nw + 2))
            prev = f
            gseg = (s("c", "→ ") + tsegs(cut(g, gw - 2))) if g != "nothing" else s("c", "nothing")
            if mode == "fit":
                tt = tsegs(cut(tk, room), dim=True)
                rows.append((head + tt + s("", " " * (room - tw(tt) + 2)) + gseg, ""))
            elif mode == "ragged":
                full = tsegs(tk, dim=True) + s("", " ") + ((s("c", "→ ") + tsegs(g)) if g != "nothing" else s("c", "nothing"))
                line = head + full
                if tw(line) > W: 
                    # cut at the edge
                    out, n = [], 0
                    for c_, x_ in line:
                        if n + len(x_) > W - 1: out.append((c_, x_[:W - 1 - n])); out.append(("c", "…")); break
                        out.append((c_, x_)); n += len(x_)
                    line = out
                rows.append((line, ""))
            else:  # wrap
                parts = split_params(tk[1:-1]) if tk else []
                lines_, cur = [], "("
                for k, p_ in enumerate(parts):
                    piece = p_ + (", " if k < len(parts) - 1 else ")")
                    if len(cur) + len(piece) > room and cur != "(":
                        lines_.append(cur.rstrip()); cur = " "
                    cur += piece
                if not parts: cur = "()" if tk else ""
                lines_.append(cur)
                for k, l_ in enumerate(lines_):
                    tt = tsegs(l_, dim=True)
                    last = k == len(lines_) - 1
                    pre = head if k == 0 else s("c", "     │    ") + s("", " " * (fw + 2 + nw + 2))
                    rows.append((pre + tt + (s("", " " * max(room - tw(tt) + 2, 2)) + gseg if last else []), ""))
    rows.append((s("c", "     │"), ""))
    t_, g_ = raw_sig(r)
    centre = s("c", str(N[r]["line"]).rjust(4) + " ") + s("c", "└──▶ ") + tsegs("(" + t_ + ")") + s("c", " → ") + s("b bold", N[r]["name"]) + s("c", " → ") + tsegs(g_)
    rows.append((centre + s("c", " ──┐") if mode != "fit" else centre, ""))
    # callers: off the row's end, or for fit under the arrow, the line going on down
    callers = [i for _, files in by_file(R) for fs in files.values() for i in fs]
    cg = collections.OrderedDict()
    for i in callers: cg.setdefault(where(N[i]["path"]), []).append(i)
    if mode == "fit":
        bx = 8
        rows[-1] = (s("c", str(N[r]["line"]).rjust(4) + " ") + s("c", "└─┬▶ ") + tsegs("(" + t_ + ")") + s("c", " → ") + s("b bold", N[r]["name"]) + s("c", " → ") + tsegs(g_), "")
        bx = 7
    else:
        bx = tw(centre) + 3
    cnw = max(len(label(i)) for i in callers)
    for gi, (d, ids) in enumerate(cg.items()):
        lastg = gi == len(cg) - 1
        rows.append((s("", " " * bx) + s("c", "└─ " if lastg else "├─ ") + s("fg bold", d[:-6] if d.endswith(" files") else d), ""))
        for i in ids:
            s_ = raw_sig(i)
            room2 = W - bx - 5 - cnw - 2 - 20
            tk = cut("(" + s_[0] + ")", max(room2, 10)) if s_ else ""
            g = cut(s_[1], 16) if s_ else ""
            rows.append((s("", " " * bx) + s("c", "   " if lastg else "│  ") + s("", "  ") + s("b", label(i).ljust(cnw + 2)) + tsegs(tk, dim=True) + s("", "  ") + (s("c", "→ ") + tsegs(g, dim=True) if g else []) + s("", "  ") + s("fd", base(N[i]["path"])) + s("c", f":{callee_line(i, r)}"), ""))
    return rows
def narrow_shot(name, title, cap, rows):
    hd = phead8(CR, "folder")
    body = compose([], [(hd + rows + blank(2), NW + 2)], "createRun()  map · folder", "")
    lib.write_shot(name, body)
    SHOTS.append((name, title, cap, body))
narrow_shot("map10-now", "Now, at 105 columns", "What it does in a pane 105 wide: the takes padded to the widest, the gives pushed to the edge and cut.", gflow(CR, "folder")[:])
narrow_shot("map10-fit", "A. Fit: what it gives whole, what it takes cut to the room left",
            "What it gives is what the row gets back, so it stays whole; what it takes is cut to what the pane leaves, in full at the foot. The callers branch off the arrow instead of the row's end, so they get the width too.",
            narrow(CR, "fit"))
narrow_shot("map10-wrap", "B. Wrap: what it takes goes on to the next line",
            "Nothing is cut: a long list of what it takes breaks after a comma onto lines under it, what it gives on its last line.",
            narrow(CR, "wrap"))
narrow_shot("map10-ragged", "C. Ragged: what it gives straight after what it takes",
            "No columns past the name: each line as long as it is, cut only at the edge.",
            narrow(CR, "ragged"))

G = []
for k, (name, title, cap, body) in enumerate(SHOTS, 1):
    G.append(f"<h2>{H.escape(title)}</h2><p class='cap'>{H.escape(cap)}</p>{body}")
open("/tmp/seam-tree/v6/map-sigs.html", "w").write(
    "<!doctype html><html><head><meta charset='utf-8'><style>" + lib.SHOT_CSS.replace("width:1640px", "max-width:1640px") +
    " h2{color:#c0caf5;font-family:system-ui} .cap{color:#a9b1d6;font-family:system-ui}</style></head><body><main>" + "".join(G) + "</main></body></html>")
print("\n".join(n for n, *_ in SHOTS))
