import sys, json
sys.path.insert(0, "/tmp/surface")
exec(open("page6.py").read().split("# ── 1: by folder")[0])

def build(entries):
    """entries: {full path: payload}. Every package in TOPS is present; an untouched one is an empty dir."""
    root = {"dirs": {}, "files": {}}
    def node(parts):
        n = root
        for p in parts: n = n["dirs"].setdefault(p, {"dirs": {}, "files": {}})
        return n
    for t in TOPS: node(t.split("/"))
    for path, v in entries.items():
        parts = path.split("/"); node(parts[:-1])["files"][parts[-1]] = v
    return root

def count(n): return len(n["files"]) + sum(count(c) for c in n["dirs"].values())

def walk(n, depth=0, at=""):
    """rows: (depth, 'dir'|'fold'|'file', label, payload, pkg)"""
    out = []
    for name in sorted(n["dirs"]):
        child, label, full = n["dirs"][name], name, (at + "/" + name).strip("/")
        pkg = full if full in HUE else None
        if count(child) == 0:
            out.append((depth, "fold", label, None, pkg)); continue
        while not child["files"] and len(child["dirs"]) == 1:
            only = next(iter(child["dirs"])); label += "/" + only; child = child["dirs"][only]; full += "/" + only
        out.append((depth, "dir", label, None, pkg))
        out += walk(child, depth + 1, full)
    for name in sorted(n["files"]):
        out.append((depth, "file", name, n["files"][name], None))
    return out

def paint(rows, own=None, leaf=None):
    """leaf(depth, name, payload, hue, dimmed) -> markup after the bar and indent."""
    out, hue, pdepth, dim = [], None, 0, False
    for depth, kind, label, v, pkg in rows:
        if pkg: hue, pdepth, dim = HUE[pkg], depth, pkg == own
        elif depth <= pdepth: hue = None
        bar = "{" + hue + ":" + BAR + "}" if hue and kind != "fold" else " "
        pad = "  " * depth
        if kind == "fold":
            out.append(" " + pad + "{d3:▸ " + label + "/}")
        elif kind == "dir" and pkg:
            out.append(bar + pad + "{" + hue + " bold:" + label.split("/")[0] + "}" + "{c:" + label[len(label.split("/")[0]):] + "/}" + ("  {c:its own folder}" if dim else ""))
        elif kind == "dir":
            out.append(bar + pad + "{c:" + label + "/}")
        else:
            out.extend(leaf(bar, pad, label, v, hue, dim))
    return out

def used_leaf(bar, pad, name, n, hue, dim):
    test = ".test." in name
    pc = "c it" if test else ("fd" if dim else "fg")
    gap = " " * max(2, 42 - len(pad) - len(name))
    return [bar + pad + "{" + pc + ":" + name + "}" + gap + "{" + ("d3" if dim or test else hue) + ":" + "━" * n + "} {fd:" + str(n) + "}"]

def from_leaf(bar, pad, name, names, hue, dim):
    gap = " " * max(2, 32 - len(pad) - len(name))
    return [bar + pad + "{fg:" + name + "}" + gap + "  ".join("{fd:" + nm(*x)[0] + "}" for x in names)]

def list_leaf(bar, pad, name, items, hue, dim):
    out = [bar + pad + "{c:" + name + "}"]
    for n, k, u, b in items:
        shown = nm(n, k)[0]
        out.append(bar + pad + "  {fg:" + shown + "}" + " " * (27 - len(pad) - 3 - len(shown)) + "{fd:" + str(u).rjust(8) + "}{fd:" + str(b).rjust(11) + "}")
    return out

CONTRACTS = {
 "apps/web/src/components/OrderSummary.tsx": [("OrderSummary", "comp", 1, 2)],
 "packages/billing/src/PaymentProvider.ts": [("PaymentProvider", "type", 3, 3)],
 "packages/billing/src/stripe.ts": [("StripeProvider", "class", 1, 2)],
 "packages/billing/src/refunds.ts": [("refundPayment", "fn", 1, 3)],
 "packages/core/src/orders/types.ts": [("Order", "type", 11, 4), ("Cart", "type", 5, 1), ("PlaceOrderError", "type", 2, 1)],
 "packages/core/src/orders/OrderService.ts": [("placeOrder", "fn", 3, 7)],
 "packages/core/src/cart/pricing.ts": [("priceCart", "fn", 2, 2)],
 "packages/core/src/events.ts": [("DomainEvent", "type", 3, 1)],
 "packages/db/src/client.ts": [("transaction", "fn", 2, 1), ("getSession", "fn", 1, 1)],
 "packages/db/src/repos/orderRepo.ts": [("OrderRepo", "class", 1, 2)],
 "packages/notify/src/channel.ts": [("NotifyChannel", "type", 1, 1)],
 "packages/shared/src/result.ts": [("Result", "type", 31, 0)],
 "packages/shared/src/money.ts": [("formatMoney", "fn", 23, 1), ("Money", "type", 14, 0)],
 "packages/ui/src/Button.tsx": [("Button", "comp", 9, 1)],
 "packages/ui/src/Price.tsx": [("Price", "comp", 3, 2)],
 "packages/ui/src/Card.tsx": [("Card", "comp", 4, 0)],
}

def screen2(left, head, mid, right, sel, st):
    return screen(left, head, [" {m bold:built from}" + mid[0], ""] + mid[1:], [" {b bold:used by}" + right[0], ""] + right[1:], sel, st)

css = open("/tmp/contracts-mock/base.css").read()
css = css[css.index("/* A Neovim screen"):]
css += """
.nv .hweb{color:#9ece6a} .nv .hapi{color:#7dcfff} .nv .hwkr{color:#1abc9c} .nv .hbil{color:#ff9e64} .nv .hcor{color:#7aa2f7}
.nv .hdb{color:#bb9af7} .nv .hnot{color:#e0af68} .nv .hsha{color:#c0caf5} .nv .hui{color:#fca7ea}
.nv .ktype{color:#2ac3de} .nv .kfn{color:#7aa2f7} .nv .kcomp{color:#bb9af7} .nv .kval{color:#ff9e64}
.nv { line-height: 1.45 !important; }
"""

# ── 1: by folder ──
tree_rows = paint(walk(build(CONTRACTS)), leaf=list_leaf)
left = [" {b bold:Contracts}  {fd:by folder}", " {c:/ search}", COLS] + tree_rows
sel = next(i for i, r in enumerate(left) if "{fg:Order}" in r)
head = [" {fg bold:Order}   {c:interface in} {hcor:packages/core}{c:/src/orders/types.ts:8}", ""]
mid = paint(walk(build({
 "packages/core/src/orders/types.ts": [("LineItem", "type"), ("OrderStatus", "type")],
 "packages/core/src/delivery/slot.ts": [("Slot", "type")],
 "packages/shared/src/money.ts": [("Money", "type")]})), own="packages/core", leaf=from_leaf)
right = paint(walk(build({
 "apps/web/src/components/OrderSummary.tsx": 4, "apps/web/src/app/checkout/page.tsx": 2, "apps/web/src/hooks/useCheckout.ts": 1,
 "apps/api/src/routes/orders.ts": 2, "apps/api/src/routes/admin/replayOrder.ts": 1,
 "apps/worker/src/jobs/sendReceipt.ts": 3, "apps/worker/src/jobs/reconcilePayments.ts": 2,
 "packages/billing/src/refunds.ts": 2,
 "packages/core/src/orders/OrderService.ts": 5, "packages/core/src/orders/OrderService.test.ts": 3,
 "packages/db/src/repos/orderRepo.ts": 3, "packages/notify/src/email.ts": 1})), own="packages/core", leaf=used_leaf)
S = [("By folder", "", screen2(left, head, ["   {c:3 files · 4 names}"] + mid, ["   {c:11 files · 26 references}"] + right, sel, (" contracts  by folder", "<Tab> most used  / search  d folder")))]

# ── 2: most used ──
flat = sorted(((p, n, k, u, b) for p, items in CONTRACTS.items() for n, k, u, b in items), key=lambda r: -r[3])
def pkg_of(p): return "/".join(p.split("/")[:2])
left = [" {b bold:Contracts}  {fd:most used first}", " {c:/ search}", "{c:" + " " * 28 + "}{b bold:used by}{c: built from}"] + [lrow(pkg_of(p), n, k, u, b, 2) for p, n, k, u, b in flat]
sel = next(i for i, r in enumerate(left) if "placeOrder()" in r)
head = [" {fg bold:placeOrder()}   {c:method of} {fg:OrderService}{c: in} {hcor:packages/core}{c:/src/orders/OrderService.ts:42}",
        " {fd:placeOrder(cart: Cart, customer: CustomerId): Promise<Result<Order, PlaceOrderError>>}"]
mid = paint(walk(build({
 "packages/billing/src/PaymentProvider.ts": [("PaymentProvider", "type")],
 "packages/core/src/orders/types.ts": [("Order", "type"), ("Cart", "type")], "packages/core/src/cart/pricing.ts": [("priceCart", "fn")], "packages/core/src/events.ts": [("emit", "fn")],
 "packages/db/src/client.ts": [("transaction", "fn")], "packages/db/src/repos/orderRepo.ts": [("OrderRepo", "class")],
 "packages/shared/src/result.ts": [("Result", "type")]})), own="packages/core", leaf=from_leaf)
right = paint(walk(build({"apps/api/src/routes/orders.ts": 1, "apps/api/src/routes/admin/replayOrder.ts": 1,
 "packages/billing/src/refunds.ts": 1, "packages/core/src/orders/OrderService.test.ts": 1})), own="packages/core", leaf=used_leaf)
S.append(("Most used", "", screen2(left, head, ["   {c:7 files · 8 names}"] + mid, ["   {c:3 files · 4 calls}"] + right, sel, (" contracts  most used", "<Tab> most built from  / search  d folder"))))

for i, (n, cap, scr) in enumerate(S):
    open(f"/tmp/surface/shots/z{i}.html", "w").write("""<!doctype html><html><head><meta charset="utf-8"><style>:root{--radius:8px}html,body{background:#0f0f14;margin:0;padding:0}""" + css + ".nv{font-size:12.5px !important}</style></head><body>" + scr + "</body></html>")
print("ok")
