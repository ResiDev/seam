# Pantry: the codebase every mock shows

A made-up TypeScript monorepo (pnpm workspaces) for a grocery delivery
service. Every design uses exactly this data, so the designs can be
compared. Invent extra detail only where a screen needs it, and keep it
consistent with what is here.

## What the tool knows

Two layers, the core of the idea:

- **Structure, computed by an indexer** (TypeScript compiler): every
  module's exports, every cross-module use of each, signature hashes,
  body hashes, git churn. Always complete, never stale.
- **Explanations, written by an LLM, gradually**: for a contract, its
  *promise* in plain words (often several clauses); for each dependent,
  what it *assumes*. Each explanation stores the hashes it was written
  against. When the structure's hash no longer matches, it is **stale**:
  signature changed = definitely stale; body changed only = maybe stale;
  a dependent's use site changed = that assumption is stale; a new
  reference = an unexplained dependent.

A **contract** is an export used from another module, or something no one
export holds (an HTTP endpoint, a table, an event, an env var) — a
*written* contract, anchored to the code that reads/writes it.
**Regions** are systems: declared (packages) and inferred (clusters of
modules that use each other), named by the LLM. A region's *surface* is
the contracts that cross its border.

Totals: 214 exports, 52 contracts (used across modules), 6 written
contracts, 19 explained, 3 stale, 30 blank.

## Layout

```
apps/web        Next.js storefront   src/app/checkout/page.tsx, src/hooks/useCart.ts,
                                     src/hooks/useCheckout.ts, src/components/OrderSummary.tsx
apps/api        Fastify              src/routes/orders.ts, src/routes/admin/replayOrder.ts,
                                     src/routes/webhooks/stripe.ts, src/server.ts
apps/worker     jobs                 src/jobs/sendReceipt.ts, src/jobs/reconcilePayments.ts
packages/core   domain               src/orders/OrderService.ts, src/orders/types.ts,
                                     src/cart/pricing.ts, src/events.ts
packages/billing payments            src/PaymentProvider.ts, src/stripe/StripeProvider.ts,
                                     src/refunds.ts
packages/db     postgres             src/client.ts, src/repos/orderRepo.ts,
                                     src/internal/session.ts, migrations/
packages/notify messages             src/NotifyChannel.ts, src/email.ts
packages/shared                      src/money.ts, src/result.ts, src/logger.ts
packages/ui     React components (web only)
```

## Regions (inferred, LLM-named) — note they cut across packages

| Region | Holds | Promise of the region, one line |
|---|---|---|
| **Storefront** | apps/web, packages/ui | Shows prices and takes an order; owns no state but the cart. |
| **Ordering** | core/orders, core/cart, db/repos/orderRepo, api/routes/orders | An order is priced, charged once and written whole, or not at all. |
| **Payments** | billing, api/routes/webhooks/stripe, worker/reconcilePayments | Money moves at most once per key, and every charge is reconciled. |
| **Messaging** | notify, worker/sendReceipt | Customers hear about each order once. |
| **Platform** | db/client, shared | Transactions and money arithmetic everyone else stands on. |

Intended layering, top to bottom: Storefront → (Ordering, Payments,
Messaging) → Platform. Rules: Storefront never touches db; Ordering knows
Payments only through `PaymentProvider`; packages never import apps.

Ordering spans three packages; the inferred regions disagree with the
folders there, which is worth showing.

## Contracts (ranked by the tool's score: breadth × churn × centrality)

1. **`OrderService.placeOrder`** — core/orders/OrderService.ts:42 · Ordering
   `placeOrder(cart: Cart, customer: CustomerId): Promise<Result<Order, PlaceOrderError>>`
   Promise: (a) charges once, using the cart id as idempotency key;
   (b) writes the order and its lines in one transaction; (c) emits
   `order.placed` after commit; (d) on failure nothing is written and a
   charge that succeeded is refunded; (e) never throws, errors come back
   as `Err` with a `kind`.
   **MAYBE STALE**: body changed 2 days ago, signature same — commit
   `a91f3c2` "retry payment on 402 with a fresh key". A fresh key breaks
   (a).
   Dependents: api/routes/orders.ts:31 (assumes (e): maps `error.kind` to
   402/409); api/routes/admin/replayOrder.ts:18 (assumes (a): replaying a
   failed order can't double-charge — **AT RISK** after a91f3c2);
   core tests. Fan-in 3 modules / 2 regions. Churn 9 changes in 90 days.

2. **`Order`** (interface) — core/orders/types.ts:8 · Ordering
   ```ts
   interface Order { id: OrderId; customerId: CustomerId; lines: LineItem[];
     total: Money; status: OrderStatus; placedAt: Date; deliverySlot?: Slot }
   ```
   Promise: (a) `total` = sum of lines + delivery, in the order's
   currency; (b) `status` only moves forward: pending → paid → packed →
   delivered, or → cancelled from pending/paid; (c) `lines` is never
   empty.
   **STALE (signature)**: `deliverySlot` became optional in `4be21d0`
   "orders without a slot for click & collect", yesterday.
   Dependents (11 modules, 4 regions): web/components/OrderSummary.tsx:22
   renders `order.deliverySlot.start` — assumes slot present —
   **BROKEN by 4be21d0, not updated (missed)**; notify/email.ts:40
   (assumes (a)); worker/reconcilePayments.ts:15 (assumes (b));
   billing/refunds.ts:9; db/repos/orderRepo.ts; api/routes/orders.ts; …
   Churn 4.

3. **`PaymentProvider`** (interface) — billing/src/PaymentProvider.ts:5 · Payments
   `charge(amount: Money, source: PaymentSource, idempotencyKey: string): Promise<Result<Charge, PaymentError>>`
   `refund(chargeId: ChargeId, amount?: Money): Promise<Result<Refund, PaymentError>>`
   Promise: (a) the same `idempotencyKey` returns the first result and
   never charges twice; (b) `refund` without an amount refunds what
   remains. Implemented by StripeProvider, FakeProvider (tests). Used by
   OrderService (the one allowed seam Ordering → Payments), refunds.ts.
   Fresh. Churn 2.

4. **`POST /orders`** (written: HTTP) — anchored at api/routes/orders.ts:12 · Ordering
   Request `{ cartId, paymentSourceId }` → 201 `{ orderId }`; 402 card
   declined; 409 cart already ordered.
   Dependents: web/hooks/useCheckout.ts:25 (assumes 409 means "already
   ordered, go to confirmation"). Fresh.

5. **`priceCart`** — core/cart/pricing.ts:14 · Ordering
   `priceCart(cart: Cart, rules: PricingRules): PricedCart`
   Promise: (a) pure; (b) rounds each line half-even to the minor unit,
   then sums, so the total equals the sum of the displayed lines.
   Dependents: web/hooks/useCart.ts:40 (assumes the price shown before
   checkout is what placeOrder charges); OrderService.placeOrder
   (reprices server-side). Fresh. Churn 5.

6. **`DomainEvent` / `events.emit`** — core/events.ts:3 · Ordering
   `type DomainEvent = { type: "order.placed"; order: Order } | { type: "order.cancelled"; orderId: OrderId; reason: string } | { type: "payment.failed"; orderId: OrderId; error: PaymentError }`
   Promise: delivered at least once, after commit; consumers must
   tolerate duplicates. Dependents: worker/sendReceipt.ts:12 (dedupes by
   orderId ✓), worker/reconcilePayments.ts:30, notify. Fresh.

7. **`db.transaction`** — db/client.ts:12 · Platform
   `transaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T>`
   Promise: one Postgres transaction; rolls back if `fn` throws; nested
   calls join the outer one. Note: does *not* roll back on a returned
   `Err` — OrderService assumes it does (**assumption contradicts
   promise**, an LLM finding). Fresh.

8. **`OrderRepo`** — db/repos/orderRepo.ts:6 · Ordering
   `insert(order, tx)`, `byId(id)`, `setStatus(id, from, to, tx)`
   Promise: `setStatus` is compare-and-set: fails if the status is not
   `from`. Fresh.

9. **`orders` table** (written: SQL) — migrations 0001, 0007, 0012 · Platform
   Columns id, customer_id, total_minor, currency, status text,
   placed_at, delivery_slot (nullable since 0012). Dependents: orderRepo;
   worker/reconcilePayments.ts:44 with **raw SQL** `WHERE status = 'paid'`
   (a hidden dependent no import shows). Fresh.

10. **`NotifyChannel`** — notify/NotifyChannel.ts:3 · Messaging
    `send(to: Recipient, msg: Message): Promise<void>` — **BLANK** (never explained). Fan-in 2.

11. **`POST /webhooks/stripe`** (written: HTTP, external caller Stripe) · Payments
    Verifies the signature; idempotent per Stripe event id. Fresh.

12. **`STRIPE_SECRET_KEY`, `DATABASE_URL`** (written: env) · Payments / Platform. Fresh.

… and further down the ranking, despite the highest fan-in:
**`formatMoney`** (shared/money.ts:30, 23 files, 0 changes in 90 days,
depends on nothing — a leaf utility) ranked 31st; **`Result<T, E>`**
(shared/result.ts, 31 files, 0 changes) ranked 38th, **BLANK**, not worth
explaining.

## Boundary problems the tool found

- **Breach (deep import)**: apps/web/src/app/checkout/page.tsx:7 imports
  `getSession` from `@pantry/db/internal/session` — past db's entry, and
  Storefront → Platform/db is forbidden.
- **Wrong-way edge**: packages/notify/src/email.ts:3 imports
  `OrderSummary` (a React component) from apps/web to render the receipt
  email — a package importing an app.
- **Cycle between regions**: Ordering → Payments through
  `PaymentProvider` (allowed), but billing/refunds.ts:22 calls
  `OrderService.cancel` — Payments → Ordering.

## Edge counts between regions (imports crossing borders)

| from \ to | Storefront | Ordering | Payments | Messaging | Platform |
|---|---|---|---|---|---|
| Storefront | — | 9 | 0 | 0 | 1 (breach) |
| Ordering | 0 | — | 3 | 0 | 14 |
| Payments | 0 | 2 (cycle) | — | 0 | 6 |
| Messaging | 1 (wrong way) | 4 | 0 | — | 5 |
| Platform | 0 | 0 | 0 | 0 | — |

## You (the reader)

You have read the explanations of `Order`, `priceCart` and
`POST /orders`. You have never opened anything in Payments or Messaging.
Last time you looked at the map was 6 days ago; since then 4be21d0 and
a91f3c2 landed.
