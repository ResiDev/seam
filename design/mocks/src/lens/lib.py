import html as H, re

W = 150

# ── rows: a row is a list of (cls, text) ────────────────────────────────
def s(cls, text):
    return [(cls, text)]

def width(r):
    return sum(len(t) for _, t in r)

def pad(r, w, fill=""):
    n = width(r)
    if n > w:
        print("clip", w, repr(''.join(t for _, t in r))[:90])
        out, at = [], 0
        for c, t in r:
            if at + len(t) > w - 1:
                out.append((c, t[:w - 1 - at])); out.append(("c", "…")); return out
            out.append((c, t)); at += len(t)
    return r + [(fill, " " * (w - n))]

def html_row(r, w, line_cls=""):
    out, merged = [], []
    for c, t in pad(r, w):
        c = (c + " " + line_cls).strip()
        if merged and (merged[-1][0] == c or (not t.strip() and not line_cls and merged[-1][0] in ("", c))):
            merged[-1] = (merged[-1][0], merged[-1][1] + t)
        else:
            merged.append((c, t))
    for c, t in merged:
        out.append(f'<span class="{c}">{H.escape(t)}</span>' if c else H.escape(t))
    return "".join(out)

# ── a small TS/TSX highlighter, tokyonight-night ────────────────────────
KW = {"export", "function", "const", "let", "return", "if", "else", "import", "from", "type", "extends",
      "of", "in", "new", "null", "undefined", "true", "false", "typeof", "async", "await"}
IT = {"const", "let", "return", "if", "else", "await"}
TOK = re.compile(r"(//.*|/\*.*?\*/)|(\"[^\"]*\"|'[^']*'|`[^`]*`)|(\b\d+\b)|(</?)([A-Za-z_]\w*)|([A-Za-z_$][\w$]*)|([^\sA-Za-z_$\d]+)|(\s+)")

def ts(src, ul=(), on=None, dim=False):
    out = []
    for m in TOK.finditer(src):
        t = m.group(0)
        if dim:
            out.append(("d3", t)); continue
        before, after = src[:m.start()], src[m.end():]
        if m.group(1): out.append(("c it", t)); continue
        if m.group(2): out.append(("g", t)); continue
        if m.group(3): out.append(("o", t)); continue
        if m.group(4):
            name = m.group(5)
            out.append(("pun", m.group(4)))
            c = "ty" if name[0].isupper() else "r"
            if name in ul: c += " ul"
            if name == on: c += " vis"
            out.append((c, name)); continue
        if m.group(6):
            if t in KW: c = "m it" if t in IT else "m"
            elif re.match(r"=[{\"]", after): c = "cy"
            elif before.endswith(".") or before.endswith("?."):
                c = "b" if re.match(r"\??\.?\(", after) else "pr"
            elif re.match(r"(<[^>]*>)?\(", after) or re.match(r"\?\.\(", after): c = "b"
            elif t[0].isupper(): c = "ty"
            else: c = "fg"
            if t in ul: c += " ul"
            if t == on: c += " vis"
            out.append((c, t)); continue
        if m.group(7): out.append(("pun", t)); continue
        out.append(("", t))
    return out

def code(lines, first, lit=(), ul=(), on=None, dimmed=False, keep=(), gutter=5):
    """lines: str or None for a gap. lit: line numbers with a background."""
    rows = []
    n = first
    for src in lines:
        if src is None:
            rows.append((s("c", " " * (gutter - 1) + "⋯"), "")); continue
        if isinstance(src, tuple):
            n, src = src
        d = dimmed and n not in lit and n not in keep
        rows.append((s("c" if not d else "d3", str(n).rjust(gutter)) + s("", "  ") + ts(src, ul, on, d),
                     "ref" if n in lit else ""))
        n += 1
    return rows

# ── the screen ──────────────────────────────────────────────────────────
HUE = {"core": "hcor", "react": "hre", "demo": "hdemo", "e2e": "he2e"}

def head(crumb, kind, pkg, rest, tab, counts=("8", "5 files")):
    r1 = s("c", " Seams › ")
    for i, c in enumerate(crumb):
        last = i == len(crumb) - 1
        r1 += s("fg bold" if last else "fd", c) + ([] if last else s("c", " › "))
    r1 += s("c", f"   {kind} in packages/") + s(HUE[pkg] + " bold", pkg) + s("c", rest)
    tabs = [("Built from " + counts[0]), ("Used by " + counts[1]), "Calls"]
    r2 = s("", "  ")
    for t in tabs:
        r2 += s("tab bold" if t == tab else "c", f" {t} ") + s("", "   ")
    return [(r1, ""), (r2, ""), (s("d3", "─" * W), "")]

def compose(headrows, cols, status_l, status_r):
    """cols: list of (rows, width); a row is (segments, line_cls)."""
    out = [html_row(r, W, c) for r, c in headrows]
    n = max(len(rows) for rows, _ in cols)
    for i in range(n):
        parts = []
        for j, (rows, w) in enumerate(cols):
            if j: parts.append('<span class="d3">│</span>')
            r, c = rows[i] if i < len(rows) else ([], "")
            parts.append(html_row(r, w, c))
        out.append("".join(parts))
    n = len(status_l) + len(status_r) + 1
    out.append('<span class="mode"> NORMAL </span><span class="sl">' +
               H.escape(status_l + " " * (W - 8 - n) + status_r + " ") + "</span>")
    return '<pre class="nv">' + "\n".join(out) + "</pre>"

def blank(n=1):
    return [([], "")] * n

def bar(pkg):
    return s(HUE[pkg], "▎")

def node(name, kind):
    """a node's name in its shape: fn(), <Component>"""
    if kind == "c": return s("ty", "<" + name + ">") if False else s("pun", "<") + s("ty", name) + s("pun", ">")
    if kind == "f": return s("b", name) + s("pun", "()")
    if kind == "file": return s("fg", name)
    return s("fg", name)

def line(cells, w):
    """cells: list of (segments, column start); fills spaces between."""
    out, at = [], 0
    for seg, col in cells:
        if col > at: out.append(("", " " * (col - at))); at = col
        elif col < at and out: out.append(("", " ")); at += 1
        out += seg; at += width(seg)
    return out

SCREENS = []
def screen(concept, title, cap, html_):
    SCREENS.append((concept, title, cap, html_))


CSS = """
:root{color-scheme:dark}
body{margin:0;font-family:var(--font-sans,system-ui)}
main{padding:0 0 30px}
h1{font-size:20px;margin:0 0 6px;color:var(--foreground)} h2{font-size:18px;margin:44px 0 4px;color:var(--foreground)}
h2 small{color:#7aa2f7;font-weight:600;margin-right:8px}
.lede{color:var(--muted-foreground);line-height:1.55;font-size:14px;max-width:900px;margin:0 0 6px}
h3{font-size:14px;margin:26px 0 6px;color:var(--foreground)}
.cap{font-size:13px;color:var(--muted-foreground);margin:0 0 10px;line-height:1.5;max-width:1000px}
.cap b,.lede b{color:var(--foreground)} code{font-family:ui-monospace,monospace;font-size:12px;color:#7dcfff}
kbd{font-family:ui-monospace,monospace;font-size:11.5px;padding:1px 5px;border-radius:4px;border:1px solid #3b4261;background:#1f2335;color:#c0caf5}
.nv{background:#1a1b26;color:#c0caf5;border-radius:8px;padding:14px 10px;margin:0;overflow-x:auto;line-height:1.35;white-space:pre;
  font-family:"JetBrainsMono Nerd Font","JetBrains Mono","DejaVu Sans Mono",ui-monospace,monospace;
  font-size:max(8.5px,min(12.5px,calc((100vw - 26px) / 90.5)));border:1px solid #292e42}
.nv span{white-space:pre}.nv{font-variant-ligatures:none}
.nv .fg{color:#c0caf5}.nv .fd{color:#a9b1d6}.nv .c{color:#565f89}.nv .d3{color:#3b4261}
.nv .b{color:#7aa2f7}.nv .cy{color:#7dcfff}.nv .ty{color:#2ac3de}.nv .m{color:#bb9af7}.nv .o{color:#ff9e64}
.nv .y{color:#e0af68}.nv .g{color:#9ece6a}.nv .r{color:#f7768e}.nv .pr{color:#73daca}.nv .pun{color:#89ddff}
.nv .bold{font-weight:700}.nv .it{font-style:italic}.nv .ul{text-decoration:underline;text-underline-offset:2px}
.nv .sel{background:#292e42}.nv .ref{background:#232a40}.nv .vis{background:#283457}.nv .focus{background:#1f2335}
.nv .tab{background:#2f3549;color:#c0caf5}
.nv .sl{background:#16161e;color:#a9b1d6}.nv .mode{background:#7aa2f7;color:#15161e;font-weight:700}
.nv .hcor{color:#7dcfff}.nv .hre{color:#bb9af7}.nv .hdemo{color:#9ece6a}.nv .he2e{color:#e0af68}
.diff{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:14px;margin:18px 0 0;max-width:1200px}
.diff div{background:#16161e;border:1px solid #292e42;border-radius:8px;padding:12px 14px;font-size:13px;line-height:1.5;color:#a9b1d6}
.diff b{color:#c0caf5;display:block;margin-bottom:4px}
"""

SHOT_CSS = CSS + " body{background:#0f0f14;padding:10px;width:1380px} .nv{font-size:12.5px}"

def write_shot(name, scr):
    """write /tmp/seam-tree/v6/<name>.html, one screen, for screenshotting"""
    open(f"/tmp/seam-tree/v6/{name}.html", "w").write(
        f"<!doctype html><html><head><meta charset='utf-8'><style>{SHOT_CSS}</style></head><body>{scr}</body></html>")
