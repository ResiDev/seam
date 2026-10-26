import sys, json, html as H, fnmatch
sys.path.insert(0, "/tmp/seam-tree/v6")
import lib
from lib import s, ts, width, W
from data import *

LENS_CSS = """
.nv .ln{color:#ff5fa8}.nv .lnd{color:#b0507f}.nv .lnb{background:#ff5fa8;color:#15161e;font-weight:700}
.nv .lnedge{background:#ff5fa8;display:inline-block;height:1.35em;vertical-align:top}.nv .lnband{background:#2a1524}.nv .lnsl{background:#2a1524;color:#ff9cc8}.nv .lq{color:#c45c5c}.nv .lqd{color:#565f89}
"""
lib.SHOT_CSS = lib.CSS + LENS_CSS + " body{background:#0f0f14;padding:10px;width:1380px} .nv{font-size:12.5px}"

HUEP = [("apps/demo", "hdemo"), ("e2e", "he2e"), ("packages/react", "hre"), ("packages/core", "hcor")]
def hue(path):
    for p, h in HUEP:
        if path.startswith(p): return h
    return "c"

def plural(n, w, ws=None): return f"{n} {w if n == 1 else (ws or w + 's')}"

# ── the lens: rules as lens.lua has them ─────────────────────────────────
def test(rule):
    if "path" in rule:
        d = rule["path"]
        return (lambda p: p.startswith(d)) if d.endswith("/") else (lambda p: p == d)
    pat = rule["pattern"]
    return lambda p: fnmatch.fnmatch(p.rsplit("/", 1)[-1].lower(), pat.lower())
def label(rule): return rule.get("path") or rule.get("pattern")

def visibility(rules):
    def vis(path, col):
        only = [test(r) for r in rules if r["cols"].get(col) == "only"]
        hide = [test(r) for r in rules if r["cols"].get(col) == "hide"]
        show = not only or any(t(path) for t in only)
        return show and not any(t(path) for t in hide)
    return vis

# ── rows: a row is a list of segments, full width ─────────────────────────
def pad(r, w):
    return lib.pad(r, w)

def withcls(r, cls):
    return [((c + " " + cls).strip(), t) for c, t in r] if cls else r

def place(cells, w=None):
    out, at = [], 0
    for seg, col in cells:
        if col > at: out.append(("", " " * (col - at))); at = col
        elif col < at and out: out.append(("", " ")); at += 1
        out += seg; at += width(seg)
    return out

def columns(cols, sep=("d3", "│")):
    """cols: [(rows, width)], a row (segs, cls); returns full rows"""
    n = max(len(rows) for rows, _ in cols)
    out = []
    for i in range(n):
        r = []
        for j, (rows, w) in enumerate(cols):
            if j: r.append(sep)
            segs, cls = rows[i] if i < len(rows) else ([], "")
            r += withcls(pad(segs, w), cls)
        out.append(r)
    return out

def overlay(rows, at_row, at_col, box):
    """paint box rows (full segs) over rows at a position"""
    for k, b in enumerate(box):
        i = at_row + k
        flat = []
        for c, t in rows[i]:
            flat += [(c, ch) for ch in t]
        bw = width(b)
        new = flat[:at_col] + [(c, ch) for c, t in b for ch in t] + flat[at_col + bw:]
        merged = []
        for c, ch in new:
            if merged and merged[-1][0] == c: merged[-1] = (c, merged[-1][1] + ch)
            else: merged.append((c, ch))
        rows[i] = merged
    return rows

def to_html(rows, status, frame=False):
    out = []
    for r in rows + [status]:
        r = pad(r, W - 2) if frame else pad(r, W)
        if frame: r = [("lnedge", " ")] + r + [("lnedge", " ")]
        parts = []
        for c, t in r:
            parts.append(f'<span class="{c}">{H.escape(t)}</span>' if c else H.escape(t))
        out.append("".join(parts))
    return '<pre class="nv">' + "\n".join(out) + "</pre>"

def status(left, right, mode=("mode", " NORMAL "), cls="sl", w=W):
    n = len(mode[1]) + len(left) + len(right) + 1
    return [mode, (cls, left + " " * (w - n) + right + " ")]

SHOTS = []
def shot(nm, title, cap, html_):
    lib.write_shot(nm, html_); SHOTS.append({"name": nm, "title": title, "caption": cap})
def save_caps():
    path = "/tmp/seam-tree/v6/captions.json"
    try: old = json.load(open(path))
    except Exception: old = []
    names = {c["name"] for c in SHOTS}
    old = [c for c in old if c["name"] not in names] + SHOTS
    json.dump(sorted(old, key=lambda c: c["name"]), open(path, "w"), indent=1)

fn = lambda n: s("b", n) + s("pun", "()")
comp = lambda n: s("pun", "<") + s("ty", n) + s("pun", ">")
def cname(e, dim=False):
    k, n = e["kind"], e["name"]
    if dim: return s("d3", f"<{n}>" if k == "component" else (n + "()" if k == "function" else n))
    if k == "component": return comp(n)
    if k == "function": return fn(n)
    if k in ("type", "interface", "class", "enum"): return s("ty", n)
    return s("fg", n)

# ═════════════════════════════════════════════════════════════════════════
# the explorer
CW, BW = 46, 50
UW = W - CW - BW - 2
CUR = [e for e in EX if e["name"] == "createRun"][0]

def explorer(rules, *, w=W, contracts_note=None, used_title_extra=None, used_inplace=False, contracts_inplace=False, top_rows=None, tag=None, nrows=46, start_top=False, con_title_extra=None, hidden_row_fn=None, used_body=None):
    vis = visibility(rules)
    uw = w - CW - BW - 2
    # contracts column -----------------------------------------------------
    con = [e for e in EX if e["uses"] and vis(e["path"], "contracts")]
    hidden_con = [e for e in EX if e["uses"] and not vis(e["path"], "contracts")]
    def counts(e):
        files = {u["path"] for u in e["uses"] if vis(u["path"], "used")}
        names = {d["name"] for d in e["deps"] if vis(d["target"].split(":")[0], "built")}
        return len(files), len(names)
    byfile = {}
    for e in con: byfile.setdefault(e["path"], []).append(e)
    tree = {}
    for p in byfile:
        d = tree
        for part in p.split("/")[:-1]: d = d.setdefault(part + "/", {})
        d.setdefault("", []).append(p)
    rows, cur_i = [], 0
    def walk(d, path, depth):
        nonlocal cur_i
        subs = sorted(k for k in d if k)
        for k in subs:
            sub, name_, full = d[k], k, path + k
            while len([x for x in sub if x]) == 1 and "" not in sub and depth > 0:
                (k2, sub), = sub.items(); name_ += k2; full += k2
            h = hue(full)
            if depth == 0:
                rows.append((s("", "  ") + s("c", name_), ""))
            else:
                segs = []
                for part in name_.rstrip("/").split("/"):
                    pk = part in ("demo", "e2e", "core", "react") and depth == 1
                    segs += s(h + " bold" if pk else "c", part) + s("c", "/")
                rows.append((s(h, "▎") + s("", " " + "  " * depth) + segs, ""))
            walk(sub, full, depth + 1)
        for p in sorted(d.get("", [])):
            h = hue(p)
            rows.append((s(h, "▎") + s("", " " + "  " * depth) + s("c", p.rsplit("/", 1)[-1]), ""))
            for e in sorted(byfile[p], key=lambda e: e["line"]):
                u, b = counts(e)
                is_cur = e is CUR
                if is_cur: cur_i = len(rows)
                cells = [(s(h, "▎") + s("", " " + "  " * (depth + 1)) + cname(e), 0),
                         (s("fd", str(u).rjust(3)), 31), (s("fd", str(b).rjust(3)), 42)]
                rows.append((place(cells), "sel" if is_cur else ""))
    if contracts_inplace:
        # where the hidden packages would sit, one pink folded row each
        hp = {}
        for e in hidden_con:
            for p, _ in HUEP:
                if e["path"].startswith(p): hp[p] = hp.get(p, 0) + 1
        tree["__hidden__"] = hp
    hid = tree.pop("__hidden__", None)
    walk(tree, "", 0)
    if hid:
        # apps/, e2e/ above packages/, packages/react after core
        def hrow(p, n, depth):
            nm = p.split("/")[-1] + "/" if depth else p + "/"
            return (s("lnd", "▎") + s("", " " + "  " * depth) + s("ln", "▸ " + nm) + s("ln", f"  {n} hidden"), "")
        hrow = hidden_row_fn or hrow
        top = [hrow("apps/demo", hid["apps/demo"], 0), hrow("e2e/fixtures", hid["e2e/fixtures"], 0) if "e2e/fixtures" in hid else hrow("e2e", hid["e2e"], 0)]
        rows = top + rows + [hrow("packages/react", hid["packages/react"], 1)]
        cur_i += 2
    head_c = [(s("", " ") + s("b bold", "Contracts") + s("c", "   by folder") + (con_title_extra or []), "")]
    head_c.append(contracts_note or (s("", " ") + s("c", "/ search"), ""))
    head_c.append((place([(s("c", "used by"), 27), (s("c", "built from"), 35)]), ""))
    body = nrows - len(head_c)
    run_i = next(i for i, (r, c) in enumerate(rows) if "".join(x for _, x in r).strip().endswith("run/") and "".join(x for _, x in r).strip().startswith("▎") or "".join(x for _, x in r).endswith("    run/"))
    start = max(0, min(run_i, len(rows) - body))
    if contracts_inplace:
        start = 0 if cur_i < body - 2 else start
    if start_top: start = 0
    left = head_c + rows[start:start + body]
    # built from -----------------------------------------------------------
    deps = {}
    for d in CUR["deps"]:
        p = d["target"].split(":")[0]
        deps.setdefault(p, []).append(d["name"])
    kinds = {e["name"]: e["kind"] for e in EX}
    B = [(s("", " ") + s("b bold", "built from") + s("c", f"   {plural(len(deps), 'file')} · {plural(sum(len(v) for v in deps.values()), 'name')}"), ""), ([], ""),
         (s("", " ") + s("d3", "▸ apps/"), ""), (s("", " ") + s("d3", "▸ e2e/"), ""), (s("", " ") + s("c", "packages/"), ""),
         (s("hcor", "▎") + s("", "   ") + s("hcor bold", "core") + s("c", "/src/  its own folder"), "")]
    def depline(p, depth, note=""):
        nm = []
        for n in deps[p]:
            k = kinds.get(n, "type")
            nm += (fn(n) if k == "function" else s("ty", n)) + s("", "  ")
        return (place([(s("hcor", "▎") + s("", " " + "  " * depth) + s("fd", p.rsplit("/", 1)[-1]) + s("c", note), 0), (nm, 26)]), "")
    B += [(s("hcor", "▎") + s("", "     ") + s("c", "run/"), ""),
          depline("packages/core/src/run/run.ts", 3),
          depline("packages/core/src/run/types.ts", 3),
          (s("hcor", "▎") + s("", "     ") + s("c", "walkthrough/"), ""),
          depline("packages/core/src/walkthrough/types.ts", 3),
          depline("packages/core/src/problems.ts", 2),
          (s("", "   ") + s("d3", "▸ react/"), "")]
    # used by --------------------------------------------------------------
    allu = Counter(u["path"] for u in CUR["uses"])
    shown = {p: n for p, n in allu.items() if vis(p, "used")}
    gone = {p: n for p, n in allu.items() if not vis(p, "used")}
    def bar(p, n, dim):
        h = "d3" if dim else hue(p)
        return s(h, "━" * min(12, max(1, n))) + s("fd", f" {n}")
    def urow(p, depth, dim=False):
        nm = p.rsplit("/", 1)[-1]
        return (place([(s(hue(p), "▎") + s("", " " + "  " * depth) + s("d3 it" if dim else "fd", nm), 0), (bar(p, shown[p], dim), 34)]), "")
    title = s("", " ") + s("b bold", "used by") + s("c", f"   {plural(len(shown), 'file')} · {plural(sum(shown.values()), 'reference')}")
    if used_title_extra: title += used_title_extra(gone)
    if used_body: U = [(title, ""), ([], "")] + used_body(shown, gone, urow); U_done = True
    else: U_done = False
    if not U_done: U = [(title, ""), ([], ""),
         (s("", " ") + s("d3", "▸ apps/"), ""),
         (s("", " ") + s("c", "e2e/"), ""),
         (s("he2e", "▎") + s("", "   ") + s("he2e bold", "fixtures") + s("c", "/"), ""),
         urow("e2e/fixtures/main.ts", 2),
         (s("", " ") + s("c", "packages/"), ""),
         (s("hcor", "▎") + s("", "   ") + s("hcor bold", "core") + s("c", "/src/run/  its own folder"), "")]
    run_files = sorted(p for p in shown if p.startswith("packages/core/src/run/"))
    for p in ([] if U_done else run_files): U.append(urow(p, 3, dim=True))
    if used_inplace and gone and not U_done:
        U.append((place([(s("lnd", "▎") + s("", "     ") + s("ln", f"▸ {len(gone)} hidden by ") + s("ln bold", "*.test.*"), 0),
                         (s("ln", "┅" * 12 + f" {sum(gone.values())}"), 34)]), ""))
    if not U_done: U += [(s("hre", "▎") + s("", "   ") + s("hre bold", "react") + s("c", "/src/"), ""), urow("packages/react/src/useRun.ts", 3)]
    # header across built from and used by
    mid = BW + 1 + uw
    hdr = [(s("", " ") + fn("createRun") + s("c", "   function in packages/") + s("hcor", "core") + s("c", "/src/run/run.ts:75"), ""),
           (s("", " ") + ts("export function createRun<TStep extends Step>("), ""),
           (s("", "   ") + ts("walkthrough: Walkthrough<TStep>, options: RunOptions<TStep> = {}): Run<TStep>"), ""),
           ([], "")]
    if tag:
        hdr[0] = (place([(hdr[0][0], 0), (tag, mid - width(tag) - 1)]), "")
    mids = columns([(B, BW), (U, uw)])
    right = [(r, "") for r in [pad(h[0], mid) for h in hdr] + mids]
    rows_ = columns([(left, CW), (right, mid)])
    return (top_rows or []) + rows_[:nrows], dict(con=len(con), hidden_con=len(hidden_con), shown=shown, gone=gone,
                                                   hidden_by_pkg=Counter(next(p for p, _ in HUEP if e["path"].startswith(p)) for e in hidden_con))

# ═════════════════════════════════════════════════════════════════════════
# the call tree: createRun, called by
LW = 82
C_ABOVE, C_USED, C_FILE, C_LINE = 37, 44, 51, 76
CR = "packages/core/src/run/run.ts:75:createRun"

def anc(i, hidden=lambda p: False):
    seen, st = set(), [i]
    while st:
        x = st.pop()
        for c in CALLERS[x]:
            p = N[c]["path"]
            if hidden(p) or is_test(p) or c in seen: continue
            seen.add(c); st.append(c)
    return seen

def trow(hue_, g, fold, nm, above="", used="", file="", ln="", note=None, cls=""):
    r = s(hue_, "▎") + s("", " ") + s("d3", g) + s("c", (fold + " ") if fold else "  ") + nm
    cells = [(r, 0)]
    if above != "": cells.append((s("fd", str(above).rjust(4)), C_ABOVE))
    if used != "": cells.append((s("fd", str(used).rjust(3)), C_USED))
    if file: cells.append((file if isinstance(file, list) else s("c", file), C_FILE))
    if note: cells.append((note, C_FILE if not file else C_FILE + 2))
    if ln: cells.append((s("c", ln), C_LINE))
    return (place(cells), cls)

def calls(rules, *, hidden_row="plain", cursor="start", lw=LW):
    vis = visibility(rules)
    hid = lambda p: not vis(p, "used")
    top_hidden = [c for c in CALLERS[CR] if hid(N[c]["path"]) and not is_test(N[c]["path"])]
    lost = anc(CR) - anc(CR, hid)
    mod = lambda p, at: s("fg", p.rsplit("/", 1)[-1]) + s("c", "  top of the file")
    pin = (s("", " ") + s("c", "↓ calls  ") + fn("startRun") + s("c", " run.ts:83 · ") + fn("problemReporter") + s("c", " problems.ts:103"), "")
    nabove = len(anc(CR, hid))
    foc = s("fg bold", "━━ ") + fn("createRun") + s("c", f"  run.ts:75   called from {plural(nabove, 'function')} above it  ")
    foc = (foc + s("d3", "━" * (lw - width(foc))), "")
    ch = (place([(s("c", "above"), C_ABOVE - 1), (s("c", "used by"), C_USED - 1), (s("c", "file"), C_FILE), (s("c", "line"), C_LINE)]), "")
    S = lambda n: "sel" if cursor == n else ""
    rows = [pin, foc, ch]
    rows += [
        trow("he2e", "", "▾", fn("start"), 2, 2, "e2e/fixtures/main.ts", ":82", cls=S("start")),
        trow("he2e", "├ ", "", mod("e2e/fixtures/main.ts", 231), ln=":231"),
        trow("he2e", "└ ", "▾", fn("apply"), 1, 1, ln=":121"),
        trow("he2e", "  └ ", "", mod("e2e/fixtures/main.ts", 232), ln=":232"),
        trow("he2e", "", "", mod("e2e/fixtures/main.ts", 229), ln=":229"),
        trow("hcor", "", "▾", fn("frameOf"), 1, 1, "core/src/run/run.perf.ts", ":37", cls=S("frameOf")),
        trow("hcor", "└ ", "", mod("run.perf.ts", 69), ln=":69"),
        trow("hcor", "", "▸", s("fd", "tests"), "", "", note=s("c", "3 files, folded")),
    ]
    if top_hidden:
        names = [N[c]["name"] for c in top_hidden]
        rest = len(lost) - len(top_hidden)
        if hidden_row == "loud":
            r = s("lnd", "▎") + s("", " ") + s("ln", "▸ ") + s("ln bold", f"{len(top_hidden)} hidden by the lens") + s("ln", "   ") + \
                s("ln", names[0] + "()") + s("ln", f" in packages/react/, and {rest} above it")
            rows.append((r, S("hidden")))
            rows.append((s("", "      ") + s("lnd", "hiding packages/react/ also cuts its callers in apps/demo/ and e2e/"), ""))
        else:
            r = s("c", "▎") + s("", " ") + s("c", "▸ ") + s("fd", f"{len(top_hidden)} hidden by the lens") + s("c", "   ") + fn(names[0]) + \
                s("c", f"  and {rest} above it")
            rows.append((r, S("hidden")))
    else:
        rows += [
            trow("hre", "", "▾", fn("useOwnedRun"), 11, 1, "react/src/useRun.ts", ":59"),
            trow("hre", "└ ", "▾", comp("ActiveWalkthrough"), 10, 1, "Walkthrough.tsx", ":82"),
            trow("hre", "  └ ", "▾", comp("Walkthrough"), 9, 8, "", ":69"),
            trow("hdemo", "    ├ ", "▸", comp("Guidance") + s("c", " ×3"), 2, 1, "demo/…/guidance.tsx", ":148"),
            trow("he2e", "    ├ ", "▸", comp("Guidance"), 4, 2, "e2e/…/guidance.tsx", ":297"),
            trow("he2e", "    ├ ", "▸", comp("WhatsNew"), 3, 1, "e2e/…/guidance.tsx", ":327"),
            trow("hre", "    └ ", "▸", s("fd", "tests"), "", "", note=s("c", "5 files, folded")),
        ]
    return rows, dict(top_hidden=top_hidden, lost=lost, nabove=nabove)

def calls_right(rw):
    r = [([], ""), (s("", " ") + s("c", "called at  ") + s("fd", "1 of 3") + s("c", "  ·  ") + fn("start") + s("c", "  e2e/fixtures/main.ts:82"), ""), ([], "")]
    r += lib.code([t for _, t in src("e2e/fixtures/main.ts", 71, 85)], 71, lit=(82,), ul=("createRun",))
    return [(withcls(pad(x, rw), c), "") if c else (x, "") for x, c in r]

def crumb(extra=None):
    r = s("c", " Seams › ") + fn("createRun") + s("c", "  called by")
    return r
