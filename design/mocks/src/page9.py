import sys
sys.path.insert(0, "/tmp/surface")
src8 = open("page8.py").read()
exec(src8.split("# ── 1: the contract ──")[0])
NW, OW = 40, 46
RW = W - NW - OW - 2

def dim(src):
    return "{d3:" + src.replace("⟦", "").replace("⟧", "").replace("{", "«").replace("}", "»") + "}"

ORDER = ["/** An order once placed. */", "export interface Order {", "  id: OrderId", "  customerId: CustomerId", "  lines: LineItem[]",
         "  total: Money", "  status: OrderStatus", "  placedAt: Date", "  deliverySlot?: Slot", "}"]
FIELD = {"id": 9, "customerId": 10, "lines": 11, "total": 12, "status": 13, "placedAt": 14, "deliverySlot": 15}
def order_pane(lit, note, under=False):
    out = ["", " {fg bold:Order}  {c:types.ts:8}", ""]
    for i, s in enumerate(ORDER):
        n = 7 + i
        frame = n in (8, 16)
        if under and n in lit: s = re.sub(r"^(\s*)(\w+)", r"\1⟦\2⟧", s)
        body = ts(s) if n in lit or frame else dim(s)
        out.append((" {c:" + str(n).rjust(3) + "}  " + body, "ref" if n in lit and not under else ""))
    return out + ["", ""] + note

def tree_nav(title, entries, leaf):
    return ["", title, ""] + paint(walk(build(entries)), own="packages/core", leaf=leaf)

DEPS = {"packages/core/src/orders/types.ts": [("LineItem", "type"), ("OrderStatus", "type")],
        "packages/core/src/delivery/slot.ts": [("Slot", "type")], "packages/shared/src/money.ts": [("Money", "type")]}
USERS = {"apps/web/src/components/OrderSummary.tsx": 4, "apps/web/src/app/checkout/page.tsx": 2, "apps/web/src/hooks/useCheckout.ts": 1,
 "apps/api/src/routes/orders.ts": 2, "apps/api/src/routes/admin/replayOrder.ts": 1,
 "apps/worker/src/jobs/sendReceipt.ts": 3, "apps/worker/src/jobs/reconcilePayments.ts": 2, "packages/billing/src/refunds.ts": 2,
 "packages/core/src/orders/OrderService.ts": 5, "packages/core/src/orders/OrderService.test.ts": 3,
 "packages/db/src/repos/orderRepo.ts": 3, "packages/notify/src/email.ts": 1}

def dep_leaf_for(on):
    def leaf(bar, pad, name, ns, hue, d):
        return [bar + pad + "{fg:" + name + "}"] + [(bar + pad + "  {fd:" + x[0] + "}", "sel" if x[0] == on else "") for x in ns]
    return leaf
def user_leaf_for(on):
    def leaf(bar, pad, name, n, hue, d):
        test = ".test." in name
        m = bar + pad + "{" + ("c it" if test else "fg") + ":" + name + "}"
        used = sum(len(x) for _, x in seg(m))
        return [(m + " " * (NW - 3 - used) + "{fd:" + str(n).rjust(2) + "}", "sel" if name == on else "")]
    return leaf

def code(rows, first, refs=(), gap_before=None):
    out = []
    for i, s in enumerate(rows):
        n = first + i
        if s is None: out.append("  {c:   ⋯}"); continue
        out.append(("  {c:" + str(n).rjust(3) + "}  " + ts(s), "ref" if n in refs else ""))
    return out

# ── built from, on LineItem ──
right = ["", " {fg bold:LineItem}   {c:interface in} {hcor:packages/core}{c:/src/orders/types.ts:21}", ""] + code(
 ["export interface LineItem {", "  sku: Sku", "  name: string", "  quantity: number", "  unitPrice: Money", "}"], 21) + [
 "", "", " {c:used by} {fd:6 files}{c:   built from} {fd:Sku}{c:,} {fd:Money}"]
S = [("Built from: LineItem", compose([HEAD, tabs("Built from"), RULE], [
    (tree_nav(" {m bold:built from}  {c:3 files · 4 names}", DEPS, dep_leaf_for("LineItem")), NW),
    (order_pane({11}, []), OW), (right, RW)], (" Order  built from  1 of 4", "j/k next  <CR> enter LineItem  <Tab> used by")))]

# ── used by, on OrderSummary.tsx ──
SUMMARY = ['import { Order } from "@pantry/core"', None, None, None] + ["export function OrderSummary({ order }: { order: Order }) {", "  const slot = order.⟦deliverySlot⟧", "  return (", "    <Card title={`Order ${order.⟦id⟧}`}>",
  "      {order.⟦lines⟧.map((line) => (", "        <LineRow key={line.sku} line={line} />", "      ))}", "      <Price value={order.⟦total⟧} />",
  "      {slot && <p>Arrives {formatSlot(slot)}</p>}", "    </Card>", "  )", "}"]
right = ["", " {fg bold:OrderSummary.tsx}   {hweb:apps/web}{c:/src/components/}", ""] + [r for r in code(SUMMARY, 1, {14}) if r != "  {c:   ⋯}"][:1] + ["  {c:   ⋯}"] + code(SUMMARY[4:], 14, {14})
reads = lambda *f: [" {c:reads}  " + "  ".join("{pr:" + x + "}" for x in f)]
S.append(("Used by: OrderSummary.tsx", compose([HEAD, tabs("Used by"), RULE], [
    (tree_nav(" {b bold:used by}  {c:11 files · 26}", USERS, user_leaf_for("OrderSummary.tsx")), NW),
    (order_pane({9, 11, 12, 15}, reads("id", "lines", "total", "deliverySlot"), True), OW), (right, RW)],
    (" Order  used by  4 of 11", "j/k next file  <CR> open  <Tab> contract"))))

# ── used by, on reconcilePayments.ts ──
REC = ['import type { Order } from "@pantry/core"', None, "async function reconcile(order: Order, charge: Charge) {", '  if (order.⟦status⟧ !== "paid") return', "  if (!sameMoney(order.⟦total⟧, charge.amount)) {",
  '    await flag(order.⟦id⟧, "amount mismatch")', "  }", "}", None, "export async function reconcileAll(day: Date) {", "  const orders: Order[] = await orderRepo.paidOn(day)",
  "  for (const order of orders) {", "    const charge = await provider.chargeFor(order.⟦id⟧)", "    await reconcile(order, charge)", "  }", "}"]
right = ["", " {fg bold:reconcilePayments.ts}   {hwkr:apps/worker}{c:/src/jobs/}", ""] + code(REC[:1], 3) + ["  {c:   ⋯}"] + code(REC[2:8], 15, {15}) + ["  {c:   ⋯}"] + code(REC[9:], 31, {32})
S.append(("Used by: reconcilePayments.ts", compose([HEAD, tabs("Used by"), RULE], [
    (tree_nav(" {b bold:used by}  {c:11 files · 26}", USERS, user_leaf_for("reconcilePayments.ts")), NW),
    (order_pane({9, 12, 13}, reads("id", "status", "total"), True), OW), (right, RW)],
    (" Order  used by  6 of 11", "j/k next file  <CR> open  <Tab> contract"))))

for i, (n, scr) in enumerate(S):
    open(f"/tmp/surface/shots/d{i}.html", "w").write("""<!doctype html><html><head><meta charset="utf-8"><style>:root{--radius:8px}html,body{background:#0f0f14;margin:0;padding:0}""" + css + ".nv{font-size:12.5px !important}</style></head><body>" + scr + "</body></html>")
print("ok")
