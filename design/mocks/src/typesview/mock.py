# The Types view, mocked from raf core's written signatures (sigs.json, made
# by extract.lua with treesitter from the code as written; returns not
# written come from the server's hover in seam's types.json).
#   python3 mock.py <sigs.json>   -> /tmp/seam-tree/v6/types-view-*.html
import sys, json, re, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lens"))
import lib
from lib import s, ts, blank, compose, code
lib.W = W = 178
LW = 44
RW = W - LW - 1
D = json.load(open(sys.argv[1]))
F = {f["path"]: f for f in D["files"]}
SRC = "packages/core/src/"

# ── type text as raf writes it, Readonly<> taken off (raf wraps every type in it)
def unwrap(t):
    while True:
        i = t.find("Readonly<")
        if i < 0: return t
        depth, j = 0, i + 8
        for j in range(i + 8, len(t)):
            if t[j] == "<": depth += 1
            elif t[j] == ">" and t[j - 1] != "=":
                depth -= 1
                if depth == 0: break
        t = t[:i] + t[i + 9:j] + t[j + 1:]

def simple(t):
    t = re.sub(r"/\*\*.*?\*/", "", t)
    t = unwrap(t)
    t = re.sub(r"\s+", " ", t)
    t = re.sub(r";\s*}", " }", t).replace("; ", ", ")
    return t.strip()

def parts(t):
    """{ a: A, b: B } -> ['a: A', 'b: B'] at the top level"""
    t = t.strip()[1:-1]
    out, depth, cur, prev = [], 0, "", ""
    for ch in t:
        if ch in "<({[": depth += 1
        if ch in ")}]" or (ch == ">" and prev != "="): depth -= 1
        prev = ch
        if ch == "," and depth == 0:
            out.append(cur.strip()); cur = ""
        else: cur += ch
    if cur.strip(): out.append(cur.strip())
    return out

def ret_of(fn):
    if fn.get("ret"): return as_bound(fn, simple(fn["ret"]))
    h = fn.get("hover") or ""
    if "=>" in h:
        r = simple(h.rsplit("=>", 1)[1])
        return r if r.count("{") == r.count("}") else "{ … }"
    return "void"

def constraints(fn):
    tp = (fn.get("tparams") or "").strip("<>")
    out = {}
    for part in re.split(r",\s*(?![^<]*>)", tp):
        m = re.match(r"(?:const\s+)?(\w+)(?:\s+extends\s+([^=]+))?", part.strip())
        if m: out[m.group(1)] = (m.group(2) or "unknown").strip()
    return out

def as_bound(fn, t):
    for name, bound in constraints(fn).items():
        t = re.sub(r"\b%s\b" % name, bound, t)
    return t

def takes(fn, generics="written"):
    ps = fn["params"]
    if len(ps) == 1 and ps[0].get("type") and simple(ps[0]["type"]).startswith("{"):
        return as_bound(fn, simple(ps[0]["type"]))
    return "(" + ", ".join(as_bound(fn, simple(p["type"])) if p.get("type") else p["name"] for p in ps) + ")"

def fn(path, name):
    return next(x for x in F[path]["fns"] if x["name"] == name)

def typ(path, name):
    return next(x for x in F[path]["types"] if x["name"] == name)

# ── one signature line: takes → name → gives, the names in one column
def wrap(text, w, level=1):
    """break after commas, shallowest first, to fit w; continuation lines indented 2"""
    if len(text) <= w: return [text]
    pieces, depth, angle, cur, prev = [], 0, 0, "", ""
    for i, ch in enumerate(text):
        cur += ch
        if ch in "({[": depth += 1
        if ch in ")}]": depth -= 1
        if ch == "<": angle += 1
        if ch == ">" and prev != "=": angle -= 1
        prev = ch
        if ch == "," and depth <= level and angle == 0:
            pieces.append(cur); cur = ""
    pieces.append(cur)
    out, line = [], ""
    for pc in pieces:
        if line and len(line) + len(pc) > w:
            out.append(line.rstrip()); line = "  " + pc.lstrip()
        else:
            line += pc
    if line.strip(): out.append(line.rstrip())
    if level < 4 and any(len(l) > w for l in out):
        return [x if i == 0 or x.startswith("  ") else "  " + x for i, x in enumerate(wrap(text, w, level + 1))]
    return out

def cut(text, w):
    return text if len(text) <= w else text[: w - 1] + "…"

def sig_rows(items, pw, mode="wrap", on=None, kept=(), gap=False, opened=()):
    """items: (takes, name, gives). mode: wrap | cut | parts"""
    nw = max(len(n) for _, n, _ in items)
    if mode == "wrap":  # a first line that can't break inside a type moves the column out
        pw = max([pw] + [len(wrap(tk, pw)[0]) for tk, _, _ in items])
    rows = []
    for k, (tk, name, gv) in enumerate(items):
        if gap and k: rows.append(([], ""))
        nm = s("fd" if name in kept else "b", name.ljust(nw))
        if name in opened:
            if tk.startswith("{"):
                ps = parts(tk)
                rows.append((s("", " ") + ts("{".ljust(pw), on=on) + s("c", " → ") + nm + s("c", " → ") + ts(gv, on=on), ""))
                for p in ps:
                    rows.append((s("", "   ") + ts(p + ","), ""))
                rows.append((s("", " ") + ts("}"), ""))
            else:  # (a, b): a parameter a line
                rows.append((s("", " ") + ts("(".ljust(pw), on=on) + s("c", " → ") + nm + s("c", " → ") + ts(gv, on=on), ""))
                for p in parts("(" + tk[1:-1] + ")"):
                    rows.append((s("", "   ") + ts(p + ",", on=on), ""))
                rows.append((s("", " ") + ts(")"), ""))
            continue
        if mode == "parts" and tk.startswith("{") and len(tk) > pw:
            ps = parts(tk)
            first = "{ " + ps[0] + ","
            rows.append((s("", " ") + ts(first.ljust(pw), on=on) + s("c", " → ") + nm + s("c", " → ") + ts(gv, on=on), ""))
            for i, p in enumerate(ps[1:]):
                end = " }" if i == len(ps) - 2 else ","
                rows.append((s("", " ") + ts(("  " + p + end), on=on), ""))
            continue
        if mode == "cut" or len(tk) <= pw:
            rows.append((s("", " ") + ts(cut(tk, pw).ljust(pw), on=on) + s("c", " → ") + nm + s("c", " → ") + ts(gv, on=on), ""))
            continue
        ls = wrap(tk, pw)
        rows.append((s("", " ") + ts(ls[0].ljust(pw), on=on) + s("c", " → ") + nm + s("c", " → ") + ts(gv, on=on), ""))
        for l in ls[1:]:
            rows.append((s("", " ") + ts(l, on=on), ""))
    return rows

def title(t):
    return (s("", " ") + s("fg bold", t), "")

def decl(path, name, label):
    t = typ(path, name)
    doc = t.get("doc") or ""
    lines = (doc + "\n" if doc else "") + t["text"]
    ls = lines.split("\n")
    first = t["line"] - (len(doc.split("\n")) if doc else 0)
    head = (s("", " ") + s("c", label + " ") + s("ty bold", name) + s("c", f"   type in {SRC}{path}:{t['line']}"), "")
    rows, inside = [], False
    for i, l in enumerate(ls):
        st = l.strip()
        is_c = inside or st.startswith("/**") or st.startswith("//")
        if st.startswith("/**") and "*/" not in st: inside = True
        elif inside and "*/" in st: inside = False
        body = s("c it", l) if is_c else ts(l)
        if is_c and "*/" in st and not st.endswith("*/"): body = ts(l)
        rows.append((s("c", str(first + i).rjust(4)) + s("", "  ") + body, ""))
    return [head] + rows

# ── the screen: the tree on the left, the views on the right
def tree(open_, cursor):
    rows = []
    def r(depth, seg, key=None, dim=False):
        row = s("hcor", "▎") + s("", "  " * depth) + seg
        rows.append((row, "sel" if key == cursor else ""))
    rows.append((s("", "  ") + s("fd", "packages/"), ""))
    r(1, s("hcor bold", "core") + s("fd", "/src/"))
    for folder, files in [("checklists/", None), ("run/", [("run.ts", ["createRun"]), ("update.ts", ["runStateOf", "initialModel", "update"]), ("rules.ts", None), ("views.ts", None), ("walkthroughs.ts", None)]),
                          ("storage/", [("adapter.ts", ["adapterOf"]), ("link.ts", ["createLink"]), ("records.ts", ["parseRecord", "changesBetween", "replacing", "storedRecord", "staleness", "applyChanges"])]),
                          ("walkthrough/", None)]:
        is_open = folder in open_
        r(2, s("c", "" if is_open else "▸ ") + s("fd", folder), key=folder)
        if not is_open: continue
        for file, names in files:
            if names is None or file not in open_:
                r(3, s("c", "▸ ") + s("fd", file), key=file); continue
            r(3, s("fd", file), key=file)
            for n in names:
                r(4, s("b", n) + s("pun", "()"), key=n)
    r(2, s("fd", "state.ts"), key="state.ts")
    for n in ["Model", "Given", "RunState", "Updated", "Msg"]:
        r(3, s("ty", n), key=n)
    return rows

def tabs(have, on="Types"):
    row = s("", " ")
    for t in have:
        row += s("tab bold" if t == on else "c", f" {t} ") + s("", "  ")
    return (row, "")

def shot(name, crumb, cursor, open_, right, status):
    hd = [(s("c", " Seams › ") + s("fg bold", crumb), ""), (s("d3", "─" * W), "")]
    L = tree(open_, cursor)
    n = max(len(L), len(right)) + 1
    scr = compose(hd, [(L + blank(n - len(L)), LW), (right + blank(n - len(right)), RW)], status, "<Tab> view   l open   J page   K back")
    lib.write_shot(name, scr)

def page(name, blocks):
    """several small screens with a caption each"""
    body = ""
    for cap, rows in blocks:
        body += f"<h3>{cap}</h3>" + compose([], [(rows + blank(1), RW)], "", "").replace(
            '<span class="mode"> NORMAL </span>', "").rsplit("\n", 1)[0] + "</pre>"
    open(f"/tmp/seam-tree/v6/{name}.html", "w").write(
        f"<!doctype html><html><head><meta charset='utf-8'><style>{lib.SHOT_CSS}</style></head><body>{body}</body></html>")
    if name.endswith("-ways"):  # each way on its own too
        for k, (cap, rows) in enumerate(blocks):
            one = f"<h3>{cap}</h3>" + compose([], [(rows + blank(1), RW)], "", "").replace(
                '<span class="mode"> NORMAL </span>', "").rsplit("\n", 1)[0] + "</pre>"
            open(f"/tmp/seam-tree/v6/{name[:-5]}-{'abc'[k]}.html", "w").write(
                f"<!doctype html><html><head><meta charset='utf-8'><style>{lib.SHOT_CSS}</style></head><body>{one}</body></html>")

PW = 46

# 1. a folder: what storage/ hands the rest of core
outside = ["adapterOf", "createLink", "parseRecord", "changesBetween", "replacing", "storedRecord", "staleness", "applyChanges"]
where = {"adapterOf": "storage/adapter.ts", "createLink": "storage/link.ts"}
items = [(takes(fn(where.get(n, "storage/records.ts"), n)), n, ret_of(fn(where.get(n, "storage/records.ts"), n))) for n in outside]
R = [(s("", " ") + s("fg bold", "storage/") + s("c", f"   folder in {SRC}storage/   3 files · 8 functions and 9 types used outside it"), ""), blank()[0],
     tabs(["Types", "Built from", "Used by"]), blank()[0],
     title("functions used outside storage/")] + sig_rows(items, 52, "cut", gap=True) + [blank()[0], title("types used outside storage/")]
tys = [("StoredRecord", 5), ("RecordChanges", 3), ("RecordUnreadableError", 3), ("Parsed", 2), ("Read", 2), ("StorageAdapter", 1), ("SaveAdapter", 1), ("SavePartialAdapter", 1), ("DroppedEntry", 1)]
for n, c in tys:
    R.append((s("", " ") + s("ty", n.ljust(24)) + s("c", f"{c} file" + ("s" if c > 1 else "")), ""))
shot("types-view-folder", "storage/", "storage/", {"storage/", "adapter.ts", "link.ts", "records.ts"}, R, "storage/  types")
R = R[:5] + sig_rows(items, 52, "cut", gap=True, opened={"createLink", "changesBetween"}) + R[5 + len(sig_rows(items, 52, "cut", gap=True)):]
shot("types-view-opened", "storage/", "storage/", {"storage/", "adapter.ts", "link.ts", "records.ts"}, R, "storage/  types  createLink and changesBetween opened")

# 2. a file: run/update.ts, its exports, then what it keeps
up = F["run/update.ts"]["fns"]
ex = [(takes(x), x["name"], ret_of(x)) for x in up if x["exported"]]
kp = [(takes(x), x["name"], ret_of(x)) for x in up if not x["exported"]]
R = [(s("", " ") + s("fg bold", "update.ts") + s("c", f"   file in {SRC}run/   3 exported · 10 kept to itself"), ""), blank()[0],
     tabs(["Code", "Types", "Built from", "Used by"]), blank()[0], title("exported")] + sig_rows(ex, 40, "cut", gap=True) + \
    [blank()[0], title("kept in update.ts")] + sig_rows(kp, 40, "cut", kept={n for _, n, _ in kp}, gap=True)
shot("types-view-file", "run/update.ts", "update.ts", {"run/", "update.ts", "run.ts"}, R, "update.ts  types")

# 3. a function: createRun
cr = fn("run/run.ts", "createRun")
R = [(s("", " ") + s("b bold", "createRun") + s("pun", "()") + s("c", f"   function in {SRC}run/run.ts:{cr['line']}"), ""), blank()[0],
     tabs(["Code", "Types", "Built from", "Used by"]), blank()[0]] + sig_rows([(takes(cr), "createRun", ret_of(cr))], 14) + [blank()[0]] + \
    decl("run/types.ts", "RunOptions", "takes") + [blank()[0]] + decl("run/types.ts", "Run", "gives")[:22] + [(s("c", "     ⋯"), "")]
shot("types-view-function", "createRun()", "createRun", {"run/", "run.ts", "update.ts"}, R, "createRun()  types")

# 4. a type: Model, who gives it, who takes it, what holds it
givers, takers = [], []
for f in D["files"]:
    for x in f["fns"]:
        g, ps = ret_of(x), takes(x)
        if re.search(r"\bModel\b", g): givers.append((ps, x["name"], g))
        if re.search(r"\bModel\b", ps): takers.append((ps, x["name"], g))
R = [(s("", " ") + s("ty bold", "Model") + s("c", f"   type in {SRC}state.ts:152   2 functions give one · 7 take one"), ""), blank()[0],
     tabs(["Code", "Types", "Built from", "Used by"]), blank()[0], title("gives a Model")] + sig_rows(givers, 34, "cut", on="Model", gap=True) + \
    [blank()[0], title("takes a Model")] + sig_rows(takers, 34, "cut", on="Model", gap=True) + [blank()[0], title("holds a Model")] + \
    [(s("", " ") + ts("Updated  { model: Model, effects: readonly Effect[] }", on="Model"), ""), blank()[0]] + decl("state.ts", "Model", "")[1:]
shot("types-view-type", "state.ts › Model", "Model", {"run/"}, R, "Model  types")

# 5. a long signature, three ways
li = [(takes(fn("storage/link.ts", "createLink")), "createLink", "Link"),
      (takes(fn("storage/records.ts", "changesBetween")), "changesBetween", "RecordChanges | undefined"),
      (takes(fn("storage/records.ts", "parseRecord")), "parseRecord", "Parsed")]
page("types-view-long", [("A. Wrapped under itself, the arrows kept in line", sig_rows(li, PW, "wrap")),
                         ("B. Cut with …, opened with the expand key", sig_rows(li, PW, "cut")),
                         ("C. One part per line, as a declaration reads", sig_rows(li, PW, "parts"))])

# 6. generics, three ways
pr = fn("problems.ts", "problemReporter"); sa = fn("run/rules.ts", "stepAt"); dw = fn("walkthrough/walkthrough.ts", "defineWalkthrough")
A = [("<TStep extends Step>(ProblemHandlers<TStep>)", "problemReporter", "ReportProblem<TStep>"),
     ("<TStep extends Step>(Walkthrough<TStep>, number)", "stepAt", "TStep"),
     ("<TWalkthrough extends Walkthrough = Walkthrough>(RunOptions<TWalkthrough>)", "createRun", "Run<TWalkthrough>"),
     ("<const TStep extends TShape, TShape extends Step = Step>(WalkthroughDefinition<TStep, TShape>)", "defineWalkthrough", "Walkthrough<NoInfer<TStep>>")]
B = [("<TStep extends Step>(ProblemHandlers<TStep>)", "problemReporter", "ReportProblem<TStep>"),
     ("<TStep extends Step>(Walkthrough<TStep>, number)", "stepAt", "TStep"),
     ("(RunOptions)", "createRun", "Run"),
     ("<TStep extends Step>(WalkthroughDefinition<TStep>)", "defineWalkthrough", "Walkthrough<TStep>")]
C = [("(ProblemHandlers<Step>)", "problemReporter", "ReportProblem<Step>"),
     ("(Walkthrough<Step>, number)", "stepAt", "Step"),
     ("(RunOptions<Walkthrough>)", "createRun", "Run<Walkthrough>"),
     ("(WalkthroughDefinition<Step, Step>)", "defineWalkthrough", "Walkthrough<Step>")]
page("types-view-generics", [("A. As written", sig_rows(A, 78)),
                             ("B. A type parameter left out where its default is used, NoInfer and const left out", sig_rows(B, 56)),
                             ("C. Each type parameter replaced by what it extends", sig_rows(C, 56))])
print("ok")

# ── layouts: where Types sits in today's explorer, on storage/
def resolve(frm, spec):
    if not spec.startswith("."): return None
    p = os.path.normpath(os.path.join(os.path.dirname(frm), spec))
    for c in (p + ".ts", p + "/index.ts"):
        if c in F: return c
    return p

def users_of(folder):
    out = {}
    for f in D["files"]:
        if f["path"].startswith(folder): continue
        for im in f["imports"]:
            r = resolve(f["path"], im["from"])
            if r and r.startswith(folder): out.setdefault(f["path"], []).extend(im["names"])
    return out

def draws_on(folder):
    out = {}
    for f in D["files"]:
        if not f["path"].startswith(folder): continue
        for im in f["imports"]:
            r = resolve(f["path"], im["from"])
            if r and not r.startswith(folder): out.setdefault(r, []).extend(n for n in im["names"] if n not in out.get(r, []))
    return out

def file_tree(by, w, bars=False):
    rows, last = [], None
    for path in sorted(by, key=lambda p: (p.count("/") == 0, p)):
        d = os.path.dirname(path) + "/" if "/" in path else ""
        if d != last:
            if d: rows.append((s("hcor", "▎") + s("", " ") + s("fd", d), ""))
            last = d
        names = by[path]
        ind = "   " if d else " "
        head = s("hcor", "▎") + s("", ind) + s("fg", os.path.basename(path)) + s("c", "  " + str(len(names)))
        rows.append((head, ""))
        line = ", ".join(names)
        rows.append((s("hcor", "▎") + s("", ind + "  ") + ts(cut(line, w - len(ind) - 4)), ""))
    return rows

TY_ROWS = R[:4] + R[4:]  # the folder's Types view as drawn above (opened)
types_rows = [r for r in R]
ub, bf = users_of("storage/"), draws_on("storage/")

def shot3(name, cols, status):
    hd = [(s("c", " Seams › ") + s("fg bold", "storage/"), ""), (s("d3", "─" * W), "")]
    L = tree({"storage/", "adapter.ts", "link.ts", "records.ts"}, "storage/")
    n = max([len(L)] + [len(c) for c, _ in cols]) + 1
    allc = [(L + blank(n - len(L)), LW)] + [(c + blank(n - len(c)), w) for c, w in cols]
    lib.write_shot(name, compose(hd, allc, status, "<Tab> view   l open   J page   K back"))

# B: Types in the middle, Used by on the right
MW = 82; UW = W - LW - MW - 2
plain = [(takes(fn(where.get(n, "storage/records.ts"), n)), n, ret_of(fn(where.get(n, "storage/records.ts"), n))) for n in outside]
mid = [(s("", " ") + s("fg bold", "storage/") + s("c", "   8 functions and 9 types used outside it"), ""), blank()[0], title("Types"), blank()[0]] + sig_rows(plain, 34, "cut", gap=True)
right = [(s("", " ") + s("c", "used by  ") + s("fg", f"{len(ub)} files"), ""), blank()[0], title("Used by"), blank()[0]] + file_tree(ub, UW)
shot3("types-view-layout-b", [(mid, MW), (right, UW)], "storage/  types · used by")

# C: today's two trees, Types across the top of them
TW = (W - LW - 2) // 2
band = [(s("", " ") + s("fg bold", "storage/") + s("c", f"   folder in {SRC}storage/   8 functions and 9 types used outside it"), ""), blank()[0]] + \
       sig_rows(plain, 52, "cut")[:5] + [(s("c", "  ⋯ 3 more"), ""), (s("d3", "─" * (W - LW - 1)), "")]
bft = [title("built from"), blank()[0]] + file_tree(bf, TW)
ubt = [title("used by"), blank()[0]] + file_tree(ub, TW)
n = max(len(bft), len(ubt))
both = []
for i in range(n):
    a = bft[i] if i < len(bft) else ([], ""); b = ubt[i] if i < len(ubt) else ([], "")
    both.append((lib.pad(a[0], TW) + s("d3", "│") + b[0], ""))
shot3("types-view-layout-c", [(band + both, W - LW - 1)], "storage/  types · built from · used by")
print("layouts ok")

# ── Used by and Built from as single views, three ways each
U, seen = [], set()
for u in json.load(open(os.path.join(os.path.dirname(sys.argv[1]), "uses.json"))):
    if (u["file"], u["line"], u["name"]) in seen: continue
    seen.add((u["file"], u["line"], u["name"])); U.append(u)
def plural(n, w): return f"{n} {w}" + ("" if n == 1 else "s")
RAF = os.path.join(os.path.dirname(sys.argv[1]), "..", "raf", "packages", "core", "src")
PANE = RW - 2

def pane_head(title_seg, tab):
    return [(s("", " ") + title_seg, ""), blank()[0], tabs(["Code", "Types", "Built from", "Used by"] if tab != "folder" else ["Types", "Built from", "Used by"], on=tab_on), blank()[0]]

def code_row(n, text, w, right=None, ind=3):
    r = s("", " " * ind) + s("c", str(n).rjust(4)) + s("", "  ")
    room = w - ind - 6 - (len(right) + 2 if right else 0)
    r += ts(cut(text, room))
    if right:
        r += s("", " " * max(1, w - lib.width(r) - len(right))) + s("c", right)
    return (r, "")

def sig_of(path, name):
    for x in F.get(path, {}).get("fns", []):
        if x["name"] == name: return (takes(x), name, ret_of(x))
    return None

# Used by storage/
tab_on = "Used by"
uhead = s("fg bold", "storage/") + s("c", f"   folder in {SRC}storage/   used by 9 files, 52 places")
byfile = {}
for u in U: byfile.setdefault(u["file"], []).append(u)
A = pane_head(uhead, "folder")
for k, (f, us) in enumerate(sorted(byfile.items(), key=lambda kv: -len(kv[1]))):
    if k: A.append(blank()[0])
    names = []
    for u in us:
        if u["name"] not in names: names.append(u["name"])
    A.append((s("", " ") + s("fg bold", f) + s("c", "   " + plural(len({u["line"] for u in us}), "place") + "   ") + ts(", ".join(names)), ""))
    shown = []
    for u in us:
        if u["line"] not in [x["line"] for x in shown]: shown.append(u)
    for u in shown[:4]:
        A.append(code_row(u["line"], u["text"], PANE, "in " + (u["top"] or "?")))
    us = shown
    if len(us) > 4: A.append((s("c", f"         ⋯ {len(us) - 4} more"), ""))

order = outside + [n for n, _ in tys]
byname = {}
for u in U: byname.setdefault(u["name"], []).append(u)
B = pane_head(uhead, "folder")
first = True
for n in order:
    us = byname.get(n)
    if not us: continue
    if not first: B.append(blank()[0])
    first = False
    path = where.get(n, "storage/records.ts") if n in outside else None
    head = s("", " ") + (s("b bold", n) if n in outside else s("ty bold", n))
    sg = sig_of(path, n) if path else None
    if sg: head += s("c", "   ") + ts(cut(sg[0], 50)) + s("c", " → ") + ts(sg[2])
    files = sorted({u["file"] for u in us})
    head += s("c", "   " + plural(len(us), "place") + " in " + plural(len(files), "file"))
    B.append((head, ""))
    for u in us[:4]:
        B.append((s("", "   ") + s("fd", (u["file"] + ":" + str(u["line"])).ljust(24)) + s("c", (u["top"] or "").ljust(16)) + ts(cut(u["text"], PANE - 45)), ""))
    if len(us) > 4: B.append((s("c", f"   ⋯ {len(us) - 4} more"), ""))

bytop = {}
for u in U: bytop.setdefault((u["file"], u["top"], u["kind"]), []).append(u)
items, extra = [], []
C = pane_head(uhead, "folder")
first = True
for (f, top, kind), us in sorted(bytop.items(), key=lambda kv: (kv[0][2] == "type_alias_declaration", kv[0][0])):
    names = []
    for u in us:
        if u["name"] not in names: names.append(u["name"])
    if not first: C.append(blank()[0])
    first = False
    sg = sig_of(f, top)
    if kind == "type_alias_declaration":
        C.append((s("", " ") + s("m", "type ") + s("ty", top) + s("c", f"   {f}"), ""))
    elif sg:
        C += [(r[0] + s("c", f"   {f}"), r[1]) for r in sig_rows([sg], 34, "cut")]
    else:
        C.append((s("", " ") + s("b", top) + s("pun", "()") + s("c", f"   {f}"), ""))
    C.append((s("", "   ") + s("c", "uses ") + ts(", ".join(names)), ""))
page("used-by-ways", [("A. By file: each file, then each place with its line of code", A),
                      ("B. By name: each thing storage/ hands out, then everyone who uses it", B),
                      ("C. By user, in the Types view's shape: each function or type that uses it, then what it uses", C)])

# Built from act
tab_on = "Built from"
act_lines = open(os.path.join(RAF, "run/walkthroughs.ts")).read().split("\n")
ACT = list(range(173, 189))
deps = [("obey", "run/walkthroughs.ts"), ("reset", "run/walkthroughs.ts"), ("verifyOne", "run/walkthroughs.ts"), ("openId", "run/walkthroughs.ts"),
        ("begin", "run/walkthroughs.ts"), ("place", "run/record.ts"), ("about", "run/walkthroughs.ts"), ("ended", "run/rules.ts"),
        ("putIn", "run/walkthroughs.ts"), ("Action", "run/types.ts"), ("Walkthrough", "walkthrough/types.ts"), ("Work", "state.ts")]
def first_use(n):
    for ln in ACT:
        if re.search(r"\b%s\b" % n, act_lines[ln - 1]): return ln, act_lines[ln - 1].strip()
deps.sort(key=lambda d: first_use(d[0])[0] * 100 + (1 if d[0][0].isupper() else 0))
ahead = s("b bold", "act") + s("pun", "()") + s("c", f"   function in {SRC}run/walkthroughs.ts:173   built from 6 files, 12 names")
A = pane_head(ahead, "fn")
groups = {}
for n, f in deps: groups.setdefault(f, []).append(n)
for k, (f, ns) in enumerate(sorted(groups.items(), key=lambda kv: (kv[0] != "run/walkthroughs.ts", kv[0]))):
    if k: A.append(blank()[0])
    A.append((s("", " ") + s("fg bold", f) + s("c", "   this file" if f == "run/walkthroughs.ts" else ""), ""))
    for n in ns:
        ln, text = first_use(n)
        A.append((s("", "   ") + (s("ty", n.ljust(12)) if n[0].isupper() else s("b", n.ljust(12))) + s("c", str(ln).rjust(4)) + s("", "  ") + ts(cut(text, PANE - 22), on=n), ""))
B = pane_head(ahead, "fn")
for k, (n, f) in enumerate(deps):
    if k: B.append(blank()[0])
    ln, text = first_use(n)
    sg = sig_of(f, n)
    head = s("", " ") + (s("ty bold", n) if n[0].isupper() else s("b bold", n))
    if sg: head += s("c", "   ") + ts(cut(sg[0], 44)) + s("c", " → ") + ts(cut(sg[2], 30))
    else: head += s("c", "   type")
    head += s("c", f"   {f}")
    B.append((head, ""))
    B.append(code_row(ln, text, PANE))
C = pane_head(ahead, "fn")
fs = [sig_of(f, n) for n, f in deps if not n[0].isupper()]
C += sig_rows(fs, 40, "cut", gap=True)
C += [blank()[0], (s("", " ") + s("c", "types  ") + s("ty", "Action   Walkthrough   Work"), "")]
page("built-from-ways", [("A. By file: each file it draws on, then each name with the line of act that uses it", A),
                         ("B. By name, in the order act first uses them: each with its signature, then that line", B),
                         ("C. In the Types view's shape: what it calls as signature lines, in the order it calls them, then the types it names", C)])
print("ways ok")
