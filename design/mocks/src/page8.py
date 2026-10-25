import sys, re, html as H
sys.path.insert(0, "/tmp/surface")
exec(open("page7.py").read().split("# ── 1: by folder ──")[0])
css += """
.nv .kw{color:#bb9af7} .nv .ty{color:#2ac3de} .nv .fn{color:#7aa2f7} .nv .str{color:#9ece6a} .nv .num{color:#ff9e64}
.nv .pr{color:#73daca} .nv .pun{color:#89ddff} .nv .cm{color:#565f89;font-style:italic} .nv .ul{text-decoration:underline;text-underline-offset:3px;font-weight:bold}
.nv .ref{background:#283457} .nv .tab{background:#3b4261;color:#c0caf5;font-weight:bold}
"""
KW = set("export interface type const let function return if await async import from readonly extends default new as typeof".split())
TOK = re.compile(r"(⟦[^⟧]*⟧)|(//.*|/\*\*.*?\*/)|(\"[^\"]*\"|`[^`]*`)|(\b\d+\b)|([A-Za-z_$][\w$]*)|([^\sA-Za-z_$\d\"`⟦]+)|(\s+)")
def ts(src):
    out, toks = [], [m for m in TOK.finditer(src)]
    for i, m in enumerate(toks):
        t = m.group(0); after = src[m.end():]; before = src[:m.start()]
        if m.group(1):
            inner = t[1:-1]; out.append("{pr ul:" + inner + "}"); continue
        if m.group(2): c = "cm"
        elif m.group(3):
            if "⟦" in t:
                for j, part in enumerate(re.split(r"⟦|⟧", t)):
                    if part: out.append("{" + ("pr ul" if j % 2 else "str") + ":" + part.replace("{", "«").replace("}", "»") + "}")
                continue
            c = "str"
        elif m.group(4): c = "num"
        elif m.group(5):
            if t in KW: c = "kw"
            elif before.endswith("."): c = "pr"
            elif re.match(r"\s*\(", after): c = "fn"
            elif re.match(r"\??:", after) and not before.rstrip().endswith("?"): c = "pr"
            elif t[0].isupper(): c = "ty"
            else: c = "fg"
        elif m.group(6): c = "pun"
        else: out.append(t); continue
        out.append("{" + c + ":" + t.replace("{", "«").replace("}", "»") + "}")
    return "".join(out)

def ren2(markup, w, cls=""):
    segs = seg(markup)
    if cls: segs = [((c + " " + cls).strip(), t) for c, t in segs]
    n = sum(len(t) for _, t in segs)
    if n > w: raise SystemExit(f"too wide {n}>{w}: {''.join(t for _, t in segs)!r}")
    segs = segs + [(cls, " " * (w - n))]
    return "".join(f'<span class="{c}">{H.escape(t)}</span>' if c else H.escape(t) for c, t in segs)

def compose(head, cols, st):
    """head: markup rows across the screen. cols: [(rows, width)], a row is markup or (markup, cls)."""
    rows = [ren2(h, W) for h in head]
    n = max(len(r) for r, _ in cols)
    for i in range(n):
        parts = []
        for r, w in cols:
            x = r[i] if i < len(r) else ""
            m, c = x if isinstance(x, tuple) else (x, "")
            parts.append(ren2(m, w, c))
        rows.append(SEP.join(parts))
    rows.append(stat(*st))
    return ('<pre class="nv">' + "\n".join(rows) + "</pre>").replace("«", "{").replace("»", "}")

def tabs(on):
    t = [("Contract", ""), ("Built from", " 4"), ("Used by", " 11 files")]
    out = "  "
    for name, n in t:
        out += ("{tab: " + name + n + " }" if name == on else " {fd:" + name + "}{c:" + n + "} ") + "   "
    return out
HEAD = " {c:Contracts ›} {fg bold:Order}   {c:interface in} {hcor:packages/core}{c:/src/orders/types.ts:8}"
RULE = "{d3:" + "─" * W + "}"
def lines(rows, first, refs=(), pad=" "):
    out = []
    for i, src in enumerate(rows):
        n = first + i
        out.append((pad + "{c:" + str(n).rjust(3) + "}  " + ts(src), "ref" if n in refs else ""))
    return out

# ── 1: the contract ──
ORDER = ["/** An order once placed. Lines keep the price paid. */", "export interface Order {", "  id: OrderId", "  customerId: CustomerId", "  lines: LineItem[]",
         "  total: Money", "  status: OrderStatus", "  placedAt: Date", "  deliverySlot?: Slot", "}"]
READ = {9: 8, 10: 3, 11: 6, 12: 7, 13: 5, 14: 0, 15: 3}
LW1 = 92
left = ["", "  " + " " * 44 + "{c:read in}"]
for i, src in enumerate(ORDER):
    n = 7 + i
    m = "  {c:" + str(n).rjust(3) + "}  " + ts(src)
    if n in READ:
        k = READ[n]
        used = sum(len(t) for _, t in seg(m.replace("«", "{").replace("»", "}")))
        m += " " * (46 - used) + ("{fd:" + "━" * k + "}" + " " * (9 - k) + "{fd:" + str(k) + "}{c: files}" if k else "{r:unread}")
    left.append((m, "sel" if n == 15 else ""))
left += ["", "", "  {c:changed 4 times · last} {fd:4be21d0}{c: yesterday ·} {fd:orders without a slot for click & collect}"]
RW1 = W - LW1 - 1
def access(bar, pad, name, ls, hue, dim):
    out = [bar + pad + "{fg:" + name + "}"]
    for n, src in ls:
        out.append(bar + pad + "  {c:" + str(n).rjust(3) + "}  " + ts(src))
    return out
right = ["", " {pr bold:deliverySlot?}{pun::} {ty:Slot}   {c:read in 3 files, set in 1}", "", " {fd:read in}", ""] + paint(walk(build({
 "apps/web/src/components/OrderSummary.tsx": [(15, "const slot = order.⟦deliverySlot⟧")],
 "apps/worker/src/jobs/sendReceipt.ts": [(22, "slot: order.⟦deliverySlot⟧?.start,")],
 "packages/notify/src/email.ts": [(40, "`Arrives ${fmt(order.⟦deliverySlot⟧.start)}`")]})), own="packages/core", leaf=access) + [
 "", " {fd:set in}", "",
 "{hcor:" + BAR + "}  {hcor bold:core}{c:/src/orders/}", "{hcor:" + BAR + "}    {fg:OrderService.ts}", "{hcor:" + BAR + "}      {c: 58}  " + ts("⟦deliverySlot⟧: cart.slot ?? undefined,")]
S = [("Contract", compose([HEAD, tabs("Contract"), RULE], [(left, LW1), (right, RW1)], (" Order  contract", "<Tab> built from  <CR> on a field: its readers  <BS> contracts")))]

# ── 2: built from ──
NW = 40
CW = (W - NW - 2) // 2
CW2 = W - NW - 2 - CW
def card(hue, title, loc, as_, code, first, w, on=False):
    loc_w = len(loc) + 1
    t = "{" + hue + ":" + BAR + "} " + title
    tw = sum(len(x) for _, x in seg(t))
    rows = [(t + " " * max(1, w - tw - loc_w) + "{c:" + loc + "}", "sel" if on else "")]
    if as_: rows.append("{" + hue + ":" + BAR + "} " + as_)
    rows.append("{" + hue + ":" + BAR + "}")
    rows += [("{" + hue + ":" + BAR + "}" + m[1:], c) for m, c in lines(code, first, ())]
    return rows + ["", ""]
c1 = card("hcor", "{fg bold:LineItem}  {c:interface}", "core/src/orders/types.ts:21", "{c:as}   " + ts("lines: LineItem[]"),
          ["export interface LineItem {", "  sku: Sku", "  name: string", "  quantity: number", "  unitPrice: Money", "}"], 21, CW, True) + \
     card("hcor", "{fg bold:OrderStatus}  {c:type}", "core/src/orders/types.ts:29", "{c:as}   " + ts("status: OrderStatus"),
          ['export type OrderStatus =', '  | "pending"', '  | "paid"', '  | "packed"', '  | "delivered"', '  | "cancelled"'], 29, CW)
c2 = card("hcor", "{fg bold:Slot}  {c:interface}", "core/src/delivery/slot.ts:4", "{c:as}   " + ts("deliverySlot?: Slot"),
          ["export interface Slot {", "  start: Date", "  end: Date", "  depot: DepotId", "}"], 4, CW2) + \
     card("hsha", "{fg bold:Money}  {c:type}", "shared/src/money.ts:3", "{c:as}   " + ts("total: Money"),
          ["export type Money = {", "  /** minor units: pence, cents */", "  amount: number", "  currency: Currency", "}"], 3, CW2)
def names_leaf(bar, pad, name, ns, hue, dim):
    return [bar + pad + "{fg:" + name + "}"] + [(bar + pad + "  {fd:" + nm(*x)[0] + "}", "sel" if x[0] == "LineItem" else "") for x in ns]
nav = ["", " {m bold:built from}  {c:3 files · 4 names}", ""] + paint(walk(build({
 "packages/core/src/orders/types.ts": [("LineItem", "type"), ("OrderStatus", "type")],
 "packages/core/src/delivery/slot.ts": [("Slot", "type")],
 "packages/shared/src/money.ts": [("Money", "type")]})), own="packages/core", leaf=names_leaf)
S.append(("Built from", compose([HEAD, tabs("Built from"), RULE], [(nav, NW), ([""] + c1, CW), ([""] + c2, CW2)], (" Order  built from", "<Tab> used by  <CR> enter LineItem  <BS> contracts"))))

# ── 3: used by ──
def count_leaf(bar, pad, name, n, hue, dim):
    test = ".test." in name
    m = bar + pad + "{" + ("c it" if test else "fg") + ":" + name + "}"
    used = sum(len(x) for _, x in seg(m))
    return [(m + " " * (NW - 3 - used) + "{fd:" + str(n).rjust(2) + "}", "sel" if name == "OrderSummary.tsx" else "")]
nav = ["", " {b bold:used by}  {c:11 files · 26}", ""] + paint(walk(build({
 "apps/web/src/components/OrderSummary.tsx": 4, "apps/web/src/app/checkout/page.tsx": 2, "apps/web/src/hooks/useCheckout.ts": 1,
 "apps/api/src/routes/orders.ts": 2, "apps/api/src/routes/admin/replayOrder.ts": 1,
 "apps/worker/src/jobs/sendReceipt.ts": 3, "apps/worker/src/jobs/reconcilePayments.ts": 2,
 "packages/billing/src/refunds.ts": 2,
 "packages/core/src/orders/OrderService.ts": 5, "packages/core/src/orders/OrderService.test.ts": 3,
 "packages/db/src/repos/orderRepo.ts": 3, "packages/notify/src/email.ts": 1})), own="packages/core", leaf=count_leaf)
def ucard(hue, file, fn, reads, code, first, refs, w, on=False):
    rows = card(hue, "{fg bold:" + file + "}  {c:in} {fn:" + fn + "}", ":" + str(first), "{c:reads}  " + reads, [], 0, w, on)[:-2]
    rows += [("{" + hue + ":" + BAR + "}" + m[1:], c) for m, c in lines(code, first, refs)]
    return rows + ["", ""]
P = lambda *f: "  ".join("{pr:" + x + "}" for x in f)
u1 = ucard("hweb", "OrderSummary.tsx", "OrderSummary()", P("id", "lines", "total", "deliverySlot"),
 ["export function OrderSummary({ order }: { order: Order }) {", "  const slot = order.⟦deliverySlot⟧", "  return (", "    <Card title={`Order ${order.⟦id⟧}`}>",
  "      {order.⟦lines⟧.map((line) => (", "        <LineRow key={line.sku} line={line} />", "      ))}", "      <Price value={order.⟦total⟧} />",
  "      {slot && <p>Arrives {formatSlot(slot)}</p>}", "    </Card>", "  )", "}"], 14, {14}, CW, True) + \
     ucard("hweb", "useCheckout.ts", "useCheckout()", "{c:nothing, passes it on}",
 ["export function useCheckout() {", "  const cart = useCart()", "  async function submit(c: Cart): Promise<Order> {", '    const res = await fetch("/orders", post(c))',
  "    return res.json()", "  }", "  return { cart, submit }", "}"], 5, {7}, CW)
u2 = ucard("hwkr", "reconcilePayments.ts", "reconcile()", P("id", "status", "total"),
 ["async function reconcile(order: Order, charge: Charge) {", '  if (order.⟦status⟧ !== "paid") return', "  if (!sameMoney(order.⟦total⟧, charge.amount)) {",
  '    await flag(order.⟦id⟧, "amount mismatch")', "  }", "}"], 15, {15}, CW2) + \
     ucard("hwkr", "sendReceipt.ts", "receipt()", P("total", "lines", "deliverySlot"),
 ["function receipt(order: Order): Receipt {", "  return {", "    total: formatMoney(order.⟦total⟧),", "    lines: order.⟦lines⟧.length,",
  "    slot: order.⟦deliverySlot⟧?.start,", "  }", "}"], 18, {18}, CW2)
S.append(("Used by", compose([HEAD, tabs("Used by"), RULE], [(nav, NW), ([""] + u1, CW), ([""] + u2, CW2)], (" Order  used by", "<Tab> contract  ]] next use  <CR> open  <BS> contracts"))))

for i, (n, scr) in enumerate(S):
    open(f"/tmp/surface/shots/c{i}.html", "w").write("""<!doctype html><html><head><meta charset="utf-8"><style>:root{--radius:8px}html,body{background:#0f0f14;margin:0;padding:0}""" + css + ".nv{font-size:12.5px !important}</style></head><body>" + scr + "</body></html>")
print("ok")
