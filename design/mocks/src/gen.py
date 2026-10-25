import html, re, sys
W = 100

def seg(s):
    # "{cls:text}" spans; plain text otherwise. Returns list of (cls, text).
    out, i = [], 0
    for m in re.finditer(r"\{([a-z0-9 -]+):((?:[^{}]|\{\})*)\}", s):
        if m.start() > i: out.append(("", s[i:m.start()]))
        out.append((m.group(1), m.group(2)))
        i = m.end()
    if i < len(s): out.append(("", s[i:]))
    return out

def width(segs): return sum(len(t) for _, t in segs)

def render(segs, w=W, fill=""):
    n = width(segs)
    if n > w: raise SystemExit(f"row too wide ({n}>{w}): {''.join(t for _,t in segs)!r}")
    segs = segs + [(fill, " " * (w - n))]
    return "".join(f'<span class="{c}">{html.escape(t)}</span>' if c else html.escape(t) for c, t in segs)

def row(s, fill=""): return render(seg(s), W, fill)

def split(l, r, lw=50):
    L, R = seg(l), seg(r)
    return render(L, lw) + '<span class="d3">│</span>' + render(R, W - lw - 1)

def screen(rows):
    return '<pre class="nv">' + "\n".join(rows) + "</pre>"

def status(left, right):
    n = len(left) + len(right) + 1
    pad = W - 8 - n
    return '<span class="mode"> NORMAL </span><span class="sl">' + html.escape(left + " " * pad + right + " ") + "</span>"
