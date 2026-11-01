# The key hints on each screen: the status line redrawn three ways over the
# locked screens' shots. Run the other mocks first; this reads their html.
#   python3 mock.py   -> /tmp/seam-tree/v6/keys-*.html
# A. plain, as today: what acts here, the key then its word.
# B. the keys lit, the words dim, in three groups: the row, the pane, seam.
# C. only what the cursor's thing does, then `? keys`; `?` opens every key.
import re, html as H

V6 = "/tmp/seam-tree/v6/"
W = 178
CSS = (" .nv .k,.float .k{color:#7aa2f7;font-weight:700} .float .kw{color:#737aa2} .nv .kw{color:#737aa2} .nv .kg{color:#3b4261}"
       " .wrap{position:relative;display:inline-block}"
       " .float{position:absolute;background:#1a1b26;border:1px solid #3b4261;border-radius:4px;padding:6px 14px 8px;"
       "font:12.5px/1.45 'JetBrains Mono',monospace;color:#a9b1d6;white-space:pre;box-shadow:0 6px 24px #000a}")

# each screen: its shot, where you are, and its keys in three groups.
# One word a key, the same word on every screen.
SCREENS = {
    "tree": ("where-underline-core", "update()  code",
             [[("l", "open"), ("h", "close"), ("J", "code")],
              [("<Tab>", "view"), ("<C-Tab>", "display")],
              [("s", "order"), ("/", "search"), ("L", "lens"), ("q", "close seam")]]),
    "pane": ("open-type-a", "createRun()  types",
             [[("+", "open type"), ("-", "close type"), ("J", "code")],
              [("<Tab>", "view"), ("<C-Tab>", "display")],
              [("<Esc>", "tree"), ("K", "back"), ("q", "close seam")]]),
    "code": ("code-types-a", "createRun()  code   queue: Queue",
             [[("n N", "import"), ("+", "open type"), ("J", "code"), ("K", "back")],
              [("<Tab>", "view"), ("<C-Tab>", "display")],
              [("/", "search"), ("q", "close seam")]]),
    "map": ("mapy-fn-tree", "createRun()  map · tree",
            [[("l", "open"), ("h", "close"), ("> <", "levels"), ("T", "types"), ("J", "code")],
             [("<Tab>", "view"), ("<C-Tab>", "display")],
             [("<Esc>", "tree"), ("q", "close seam")]]),
    "changed": ("changed-signs", "problems.ts  changed · changes only",
                [[("]c [c", "change"), ("gc", "only changed"), ("J", "code")],
                 [("<Tab>", "view"), ("<C-Tab>", "display")],
                 [("L", "lens"), ("q", "close seam")]]),
}
# every key on a screen, for C's float, grouped as KEYS.md will be
ALL_TREE = [("This row", [("j k", "move"), ("l", "open its calls"), ("h", "close them"), ("J", "the code screen on it"), ("+ -", "open and close a type")]),
            ("The pane", [("<Tab> <S-Tab>", "next and previous view"), ("<C-Tab> <C-S-Tab>", "next and previous display"),
                          ("<C-d> <C-u>", "scroll it half a screen"), ("<C-e> <C-y>", "scroll it a line")]),
            ("The tree", [("s", "order: by folder, most used, most calling"), ("/", "search the names"), ("gc", "only what changed"),
                          ("]c [c", "next and previous change")]),
            ("Seam", [("L", "the lens: range and rules"), ("gf gd", "that place in your own code"), ("R", "ask again"), ("q", "close seam")])]

def esc(t): return H.escape(t)
def plain(left, groups):
    flat = "   ".join(f"{k} {w}" for g in groups for k, w in g)
    n = len(left) + len(flat) + 1
    return '<span class="sl">' + esc(left + " " * (W - 8 - n) + flat + " ") + "</span>"
def lit(left, groups, more=None):
    parts, n = [], 0
    for j, g in enumerate(groups):
        if j: parts.append('<span class="kg">  │  </span>'); n += 5
        for i, (k, w) in enumerate(g):
            if i: parts.append("   "); n += 3
            parts.append(f'<span class="k">{esc(k)}</span> <span class="kw">{esc(w)}</span>'); n += len(k) + 1 + len(w)
    if more:
        parts.append('<span class="kg">  │  </span>' + f'<span class="k">?</span> <span class="kw">{more}</span>'); n += 5 + 2 + len(more)
    pad = W - 8 - len(left) - n - 1
    return '<span class="sl">' + esc(left) + " " * pad + "".join(parts) + " </span>"

HINTS = [r"\s{3,}T inputs and outputs", r"\s{3,}&gt; &lt; levels", r"\s{3,}l opens( a box)?", r"\+ opens the type under the cursor   - closes it",
         r"\s{3,}\+ opens the type under the cursor"]
def strip_hints(doc):
    for h in HINTS: doc = re.sub(h, lambda m: " " * len(H.unescape(m.group(0))), doc)
    return doc

def float_html():
    lines = []
    kw = max(len(k) for _, g in ALL_TREE for k, _ in g) + 3
    for j, (title, g) in enumerate(ALL_TREE):
        if j: lines.append("")
        lines.append(f'<span style="color:#c0caf5;font-weight:700">{title}</span>')
        for k, w in g: lines.append(f'  <span class="k">{esc(k.ljust(kw))}</span><span>{esc(w)}</span>')
    lines += ["", '<span class="kw">every key on this screen   ? or &lt;Esc&gt; closes</span>']
    return "\n".join(lines)

for scr, (shot, left, groups) in SCREENS.items():
    doc = open(V6 + shot + ".html").read()
    doc = doc.replace("</style>", CSS + "</style>", 1)
    doc = strip_hints(doc)
    head, sep, tail = doc.rpartition('<span class="mode"> NORMAL </span>')
    end = tail.index("</pre>")
    for v, sl in (("a", plain(left, groups)), ("b", lit(left, groups)), ("c", lit(left, groups[:1], more="keys"))):
        open(V6 + f"keys-{scr}-{v}.html", "w").write(head + sep + sl + tail[end:])
    if scr == "tree":
        out = head + sep + lit(left, groups[:1], more="keys") + tail[end:]
        out = out.replace('<pre class="nv">', '<div class="wrap"><pre class="nv">', 1).replace("</pre>", "</pre>"
              f'<div class="float" style="right:24px;bottom:34px">{float_html()}</div></div>', 1)
        open(V6 + "keys-tree-help.html", "w").write(out)
print("ok")
