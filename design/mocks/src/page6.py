import sys, html as H, json
sys.path.insert(0, "/tmp/surface")
from gen import seg

W, LW, MW = 176, 46, 60
RW = W - LW - MW - 2
def ren(markup, w, sel=False):
    segs = seg(markup)
    if sel: segs = [((c + " sel").strip(), t) for c, t in segs]
    n = sum(len(t) for _, t in segs)
    if n > w: raise SystemExit(f"too wide {n}>{w}: {''.join(t for _, t in segs)!r}")
    segs = segs + [("sel" if sel else "", " " * (w - n))]
    return "".join(f'<span class="{c}">{H.escape(t)}</span>' if c else H.escape(t) for c, t in segs)
SEP = '<span class="d3">│</span>'
def stat(left, right):
    pad = W - 8 - len(left) - len(right) - 1
    return '<span class="mode"> NORMAL </span><span class="sl">' + H.escape(left + " " * pad + right + " ") + "</span>"

# each top-level folder has a hue, used wherever its files appear
HUE = {"apps/web": "hweb", "apps/api": "hapi", "apps/worker": "hwkr", "packages/billing": "hbil",
       "packages/core": "hcor", "packages/db": "hdb", "packages/notify": "hnot", "packages/shared": "hsha", "packages/ui": "hui"}
TOPS = list(HUE)
BAR = "▎"
# a name is drawn the way code draws it: types plain, functions with (), components in <>
KIND = {"type": "fg", "fn": "fg", "class": "fg", "comp": "fg", "value": "fg"}
def nm(name, kind):
    shown = {"fn": name + "()", "comp": "<" + name + ">"}.get(kind, name)
    return shown, KIND[kind]

def lrow(top, name, kind, used, built, ind=4):
    shown, k = nm(name, kind)
    return "{" + HUE[top] + ":" + BAR + "}" + " " * (ind - 1) + "{" + k + ":" + shown.ljust(27 - ind) + "}" + "{fd:" + str(used).rjust(8) + "}" + "{fd:" + str(built).rjust(11) + "}"
def lhead(top, extra=""):
    return "{" + HUE[top] + ":" + BAR + "}" + " {" + HUE[top] + " bold:" + top + "}" + (" {c:" + extra + "}" if extra else "")
def lsub(top, path): return "{" + HUE[top] + ":" + BAR + "}" + "   {c:" + path + "}"
def lempty(top): return "{d3:" + BAR + "}" + " {d3:" + top + "}"

def bar(n, top, own=False):
    return "{" + ("d3" if own else HUE[top]) + ":" + "━" * min(n, 12) + "}" + " {fd:" + str(n) + "}"

def filelist(groups, w, own_top=None, names=False):
    """groups: {top: [(path, n or [names], test?)]}; every top shown in the same order, a blank row between."""
    out = []
    for t in TOPS:
        if t not in groups:
            out.append(" {d3:" + t + "}"); continue
        own = t == own_top
        out.append("{" + HUE[t] + ":" + BAR + "}" + "{" + HUE[t] + " bold:" + t + "}" + ("  {c:its own folder}" if own else ""))
        for path, v, *rest in groups[t]:
            test = rest and rest[0]
            pc = "c it" if test else ("fd" if own else "fg")
            pre = "{" + HUE[t] + ":" + BAR + "}" + "  {" + pc + ":" + path + "}"
            if names:
                out.append(pre + " " * max(2, 34 - len(path)) + "  ".join("{fd:" + nm(*x)[0] + "}" for x in v))
            else:
                out.append(pre + " " * max(2, 40 - len(path)) + bar(v, t, own or test))
        out.append("")
    return out[:-1]

def screen(left, head, mid, right, sel, st):
    rows = []
    rows.append(ren(left[0], LW) + SEP + ren(head[0], W - LW - 1))
    rows.append(ren(left[1], LW) + SEP + ren(head[1], W - LW - 1))
    rows.append(ren(left[2], LW) + SEP + ren("", W - LW - 1))
    body = left[3:]
    n = max(len(body), len(mid), len(right))
    body += [""] * (n - len(body)); mid += [""] * (n - len(mid)); right += [""] * (n - len(right))
    for i in range(n):
        rows.append(ren(body[i], LW, i + 3 == sel) + SEP + ren(mid[i], MW) + SEP + ren(right[i], RW))
    rows.append(stat(*st))
    return '<pre class="nv">' + "\n".join(rows) + "</pre>"

COLS = "{c:" + " " * 27 + " used by" + " built from}"

# ── 1: by folder (the default) ────────────────────────────────────
left = [" {b bold:Contracts}  {fd:by folder}", " {c:/ search}", COLS,
 lhead("apps/web"), lrow("apps/web", "OrderSummary", "comp", 1, 2), "",
 lempty("apps/api"), lempty("apps/worker"), "",
 lhead("packages/billing"), lrow("packages/billing", "PaymentProvider", "type", 3, 3), lrow("packages/billing", "StripeProvider", "class", 1, 2), lrow("packages/billing", "refundPayment", "fn", 1, 3), "",
 lhead("packages/core"), lsub("packages/core", "src/orders/"), lrow("packages/core", "Order", "type", 11, 4, 6), lrow("packages/core", "Cart", "type", 5, 1, 6), lrow("packages/core", "placeOrder", "fn", 3, 7, 6), lrow("packages/core", "PlaceOrderError", "type", 2, 1, 6),
 lsub("packages/core", "src/cart/"), lrow("packages/core", "priceCart", "fn", 2, 2, 6), lsub("packages/core", "src/events.ts"), lrow("packages/core", "DomainEvent", "type", 3, 1, 6), "",
 lhead("packages/db"), lrow("packages/db", "transaction", "fn", 2, 1), lrow("packages/db", "OrderRepo", "class", 1, 2), lrow("packages/db", "getSession", "fn", 1, 1), "",
 lhead("packages/notify"), lrow("packages/notify", "NotifyChannel", "type", 1, 1), "",
 lhead("packages/shared"), lrow("packages/shared", "Result", "type", 31, 0), lrow("packages/shared", "formatMoney", "fn", 23, 1), lrow("packages/shared", "Money", "type", 14, 0), "",
 lhead("packages/ui"), lrow("packages/ui", "Button", "comp", 9, 1), lrow("packages/ui", "Price", "comp", 3, 2), lrow("packages/ui", "Card", "comp", 4, 0)]
head = [" {fg bold:Order}   {c:interface in} {hcor:packages/core}{c:/src/orders/types.ts:8}", ""]
mid = [" {m bold:built from}   {c:3 files · 4 names}", ""] + filelist({
 "packages/core": [("src/orders/types.ts", [("LineItem","type"), ("OrderStatus","type")]), ("src/delivery/slot.ts", [("Slot","type")])],
 "packages/shared": [("src/money.ts", [("Money","type")])]}, MW, "packages/core", names=True)
right = [" {b bold:used by}   {c:11 files · 26 references}", ""] + filelist({
 "apps/web": [("src/components/OrderSummary.tsx", 4), ("src/app/checkout/page.tsx", 2), ("src/hooks/useCheckout.ts", 1)],
 "apps/api": [("src/routes/orders.ts", 2), ("src/routes/admin/replayOrder.ts", 1)],
 "apps/worker": [("src/jobs/sendReceipt.ts", 3), ("src/jobs/reconcilePayments.ts", 2)],
 "packages/billing": [("src/refunds.ts", 2)],
 "packages/core": [("src/orders/OrderService.ts", 5), ("src/orders/OrderService.test.ts", 3, True)],
 "packages/db": [("src/repos/orderRepo.ts", 3)],
 "packages/notify": [("src/email.ts", 1)]}, RW, "packages/core")
sel = left.index(lrow("packages/core", "Order", "type", 11, 4, 6))
S = [("By folder", "The default. Contracts sit under the folders they live in, and every top-level folder has its own colour. That colour runs down a thin bar on the left of each group, in all three columns. So once you're past the header you can tell where an Order's users live from the colours alone: green web, cyan api, teal worker, and so on. Names are coloured and shaped like code: types plain, functions with <code>()</code>, components in <code>&lt;&gt;</code>. Files in the contract's own folder, and tests, are dimmed, so the bright bars are the uses that cross a folder.", screen(left, head, mid, right, sel, (" contracts  by folder", "<Tab> most used  / search  d folder")))]

# ── 2: <Tab>, most used first ────────────────────────────────────
flat = [("packages/shared", "Result", "type", 31, 0), ("packages/shared", "formatMoney", "fn", 23, 1), ("packages/shared", "Money", "type", 14, 0),
        ("packages/core", "Order", "type", 11, 4), ("packages/ui", "Button", "comp", 9, 1), ("packages/core", "Cart", "type", 5, 1),
        ("packages/ui", "Card", "comp", 4, 0), ("packages/core", "placeOrder", "fn", 3, 7), ("packages/billing", "PaymentProvider", "type", 3, 3),
        ("packages/core", "DomainEvent", "type", 3, 1), ("packages/ui", "Price", "comp", 3, 2), ("packages/db", "transaction", "fn", 2, 1),
        ("packages/core", "priceCart", "fn", 2, 2), ("packages/core", "PlaceOrderError", "type", 2, 1), ("packages/db", "OrderRepo", "class", 1, 2),
        ("packages/db", "getSession", "fn", 1, 1), ("apps/web", "OrderSummary", "comp", 1, 2), ("packages/notify", "NotifyChannel", "type", 1, 1),
        ("packages/billing", "StripeProvider", "class", 1, 2), ("packages/billing", "refundPayment", "fn", 1, 3)]
left = [" {b bold:Contracts}  {fd:most used first}", " {c:/ search}", "{c:" + " " * 28 + "}{b bold:used by}{c: built from}"] + [lrow(t, n, k, u, b, 2) for t, n, k, u, b in flat]
head = [" {fg bold:placeOrder()}   {c:method of} {fg:OrderService}{c: in} {hcor:packages/core}{c:/src/orders/OrderService.ts:42}",
        " {fd:placeOrder(cart: Cart, customer: CustomerId): Promise<Result<Order, PlaceOrderError>>}"]
mid = [" {m bold:built from}   {c:7 files · 8 names}", ""] + filelist({
 "packages/billing": [("src/PaymentProvider.ts", [("PaymentProvider","type")])],
 "packages/core": [("src/orders/types.ts", [("Order","type"), ("Cart","type")]), ("src/cart/pricing.ts", [("priceCart","fn")]), ("src/events.ts", [("emit","fn")])],
 "packages/db": [("src/client.ts", [("transaction","fn")]), ("src/repos/orderRepo.ts", [("OrderRepo","class")])],
 "packages/shared": [("src/result.ts", [("Result","type")])]}, MW, "packages/core", names=True)
right = [" {b bold:used by}   {c:3 files · 4 calls}", ""] + filelist({
 "apps/api": [("src/routes/orders.ts", 1), ("src/routes/admin/replayOrder.ts", 1)],
 "packages/billing": [("src/refunds.ts", 1)],
 "packages/core": [("src/orders/OrderService.test.ts", 1, True)]}, RW, "packages/core")
S.append(("Most used first", "<kbd>&lt;Tab&gt;</kbd> cycles the order: by folder, most used, most built from, by name. Out of the folder tree, each row keeps its folder's colour in the bar, so you still see where things live: the top of this list is all <code>shared</code>, and the next band is <code>core</code>. The cursor is on <code>placeOrder()</code>. It's built from four folders, but called only from api and from one billing file.", screen(left, head, mid, right, 3 + 7, (" contracts  most used", "<Tab> most built from  / search  d folder"))))

css = open("/tmp/contracts-mock/base.css").read()
css = css[css.index("/* A Neovim screen"):]
css += """
.nv .hweb{color:#9ece6a} .nv .hapi{color:#7dcfff} .nv .hwkr{color:#1abc9c} .nv .hbil{color:#ff9e64} .nv .hcor{color:#7aa2f7}
.nv .hdb{color:#bb9af7} .nv .hnot{color:#e0af68} .nv .hsha{color:#c0caf5} .nv .hui{color:#fca7ea}
.nv .ktype{color:#2ac3de} .nv .kfn{color:#7aa2f7} .nv .kcomp{color:#bb9af7} .nv .kval{color:#ff9e64}
.nv { line-height: 1.45 !important; }
"""
for i, (n, cap, scr) in enumerate(S):
    open(f"/tmp/surface/shots/y{i}.html", "w").write("""<!doctype html><html><head><meta charset="utf-8"><style>:root{--radius:8px}html,body{background:#0f0f14;margin:0;padding:0}""" + css + ".nv{font-size:12.5px !important}</style></head><body>" + scr + "</body></html>")
json.dump([(n, c) for n, c, _ in S], open("/tmp/surface/shots/ycaps.json", "w"))
print("ok")
