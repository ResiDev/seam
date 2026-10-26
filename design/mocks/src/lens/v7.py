from common import *
# V7: one count in the title of each column the lens took from, with "L lens"
# beside it; no rows, no tags, nothing taking a line of its own.
q = lambda t: s("lq", t)
mark = lambda n, unit: q(f"   {n} {unit} hidden") + s("c", "  L lens")
def drop_lens_rows(rows):
    return rows
EX_SL = ("  contracts  by folder", "<Tab> most used  / search  d folder  L lens")
CA_SL = ("  createRun()  ›  called by  ›  start()", "j/k row  h parent  l open  ~ calls  <CR> anchor  L lens")

R2 = [{"path": "packages/core/", "cols": {"contracts": "only"}}, {"pattern": "*.test.*", "cols": {"used": "hide"}}]
vis = visibility(R2)
hidden_files = len({e["path"] for e in EX if e["uses"] and not vis(e["path"], "contracts")})
def used2(shown, gone, urow):
    return [(s("", " ") + s("d3", "▸ apps/"), ""), (s("", " ") + s("c", "e2e/"), ""),
            (s("he2e", "▎") + s("", "   ") + s("he2e bold", "fixtures") + s("c", "/"), ""), urow("e2e/fixtures/main.ts", 2),
            (s("", " ") + s("c", "packages/"), ""),
            (s("hcor", "▎") + s("", "   ") + s("hcor bold", "core") + s("c", "/src/run/  its own folder"), ""),
            urow("packages/core/src/run/run.perf.ts", 3, dim=True),
            (s("hre", "▎") + s("", "   ") + s("hre bold", "react") + s("c", "/src/"), ""), urow("packages/react/src/useRun.ts", 3)]
rows, I = explorer(R2, contracts_note=(s("", " ") + q(f"{hidden_files} files hidden") + s("c", "  L lens"), ""),
                   used_title_extra=lambda g: q(f"  +{len(g)} hidden") + s("c", "  L lens"), used_body=used2, nrows=46)
shot("v7-explorer", "Explorer, two rules", "", to_html(rows, status(*EX_SL)))

RC = [{"path": "packages/react/", "cols": {"used": "hide"}}]
left, CI = calls(RC, hidden_row="plain")
LOST = len(CI["lost"])
out = []
for r, c in left:
    txt = "".join(t for _, t in r)
    if "hidden by the lens" in txt: continue
    if "above it" in txt and "━━" in txt:
        base = s("fg bold", "━━ ") + fn("createRun") + s("c", f"  run.ts:75   called from {plural(CI['nabove'], 'function')} above it") + q(f"   +{LOST} hidden") + s("c", "  L lens") + s("", "  ")
        r = base + s("d3", "━" * (LW - width(base)))
    out.append((r, c))
rw = W - LW - 1
body = columns([(out, LW), (calls_right(rw), rw)])
rows = [crumb(), s("", "")] + body
while len(rows) < 24: rows.append([])
shot("v7-calls", "Call tree", "", to_html(rows, status(*CA_SL)))
print(hidden_files, LOST)
