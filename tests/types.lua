-- Types as data: hovers as the server writes them to what a function takes
-- and gives, and a model written by hand to the flows of its types.
--   nvim -l tests/types.lua
-- Exits 0 when nothing failed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
local types = require 'seam.types'
local index = require 'seam.index'

local failures, checks = {}, 0
local function eq(got, want, what)
  checks = checks + 1
  if not vim.deep_equal(got, want) then
    failures[#failures + 1] = what .. ': want ' .. vim.inspect(want):gsub('%s+', ' ') .. '  (got ' .. vim.inspect(got):gsub('%s+', ' ') .. ')'
    io.stdout:write('FAIL ' .. failures[#failures] .. '\n')
  end
end

local function shape(text)
  local s = types.parse(text)
  local ps = s.params and vim.tbl_map(function(p)
    return p.name .. (p.optional and '?' or '') .. ': ' .. p.type
  end, s.params)
  return { ps, s.ret, s.value }
end

eq(shape 'function apply<TStep extends Step>(state: State<TStep>, message: Message): Outcome<TStep>', {
  { 'state: State<TStep>', 'message: Message' },
  'Outcome<TStep>',
}, 'a function declaration with generics')
eq(shape 'const pointAtParam: (a: GlobalPoint, b: GlobalPoint, t: number) => GlobalPoint', {
  { 'a: GlobalPoint', 'b: GlobalPoint', 't: number' },
  'GlobalPoint',
}, 'an arrow in a const')
eq(shape 'const f: <T extends ExcalidrawElement>(elements: readonly T[]) => Array<T>', { { 'elements: readonly T[]' }, 'Array<T>' }, 'arrow with generics')
eq(
  shape 'const pick: (map: Map<string, (x: A) => B>, cb?: (e: E) => void) => B[]',
  { { 'map: Map<string, (x: A) => B>', 'cb?: (e: E) => void' }, 'B[]' },
  'arrows inside parameters do not close their brackets'
)
eq(
  shape 'const d: ({ x, y }: {\n    x: number;\n    y: number;\n}) => number',
  { { '{ x, y }: { x: number; y: number; }' }, 'number' },
  'a destructured parameter'
)
eq(shape 'const m: (s: "a, b" | "c)") => void', { { 's: "a, b" | "c)"' }, 'void' }, 'strings hold their commas and brackets')
eq(shape 'function load(id: string): Promise<Doc> (+1 overload)', { { 'id: string' }, 'Promise<Doc>' }, 'overloads dropped')
eq(shape '(alias) function load(id: string): Doc', { { 'id: string' }, 'Doc' }, 'an alias')
eq(shape 'const C: { ({ a }: { a: A; }): any; displayName: string; }', { { '{ a }: { a: A; }' }, 'any' }, 'a component with properties')
eq(shape 'const C: React.FC<Props>', { nil, nil, 'React.FC<Props>' }, 'a callable written as a value')
eq(shape 'class Scene', { nil, nil, nil }, 'a class has no call')

eq(types.names 'Map<Order["id"], NonDeleted<Line>> | "Order"', { 'Map', 'Order', 'NonDeleted', 'Line' }, 'names: indexed, nested, strings left out')
eq(types.names '{ order: Order; cart?: Cart }', { 'Order', 'Cart' }, 'names: keys are not types')
eq(types.names 'React.Component<any, AppState>', { 'React', 'any', 'AppState' }, 'names: a member after a dot is not one')

local flows = { Order = {}, Cart = {}, AppState = {} }
eq(types.short('{ order: Order; n: number } & ({ cart: Cart } | { x: 1 })', flows), '{ Order } & ({ Cart } | {…})', 'short: each object as its repo types')
eq(types.short('readonly import("./x").Order[]', flows), 'Order[]', 'short: readonly and import paths dropped')
local function line(text)
  return table.concat(vim.tbl_map(function(p)
    return p.flow and '[' .. p.text .. ']' or p.text
  end, types.pieces(types.parse(text), flows)))
end
eq(line 'function f(a: Order, b: Cart[]): Promise<Order>', '([Order], [Cart][]) → Promise<[Order]>', 'pieces: before and after, repo types marked')
eq(line 'const C: React.FC<Props>', 'React.FC<Props>', 'pieces: a value as it is')
local function fitted(text, room)
  return table.concat(vim.tbl_map(function(p)
    return p.text
  end, types.fit(types.pieces(types.parse(text), flows), room)))
end
eq(fitted('function f(a: Order, b: Cart, c: number): Promise<Order>', 30), '(Order, Car…) → Promise<Order>', 'fit: the parameters cut, the return kept')
eq(fitted('function f(a: Order): Order', 30), '(Order) → Order', 'fit: what fits is left alone')

-- a model: Order is made by placeOrder and by new in seed, taken by ship
local m = {
  exports = {
    { id = 'src/types.ts:1:Order', name = 'Order', kind = 'class', path = 'src/types.ts' },
    { id = 'src/types.ts:9:Cart', name = 'Cart', kind = 'interface', path = 'src/types.ts' },
    { id = 'src/run.ts:1:placeOrder', name = 'placeOrder', kind = 'function', path = 'src/run.ts' },
  },
  graph = index.graph {
    { id = 'src/run.ts:1:placeOrder', name = 'placeOrder', kind = 'function', path = 'src/run.ts', line = 1 },
    { id = 'src/run.ts:20:ship', name = 'ship', kind = 'function', path = 'src/run.ts', line = 20 },
    { id = 'src/seed.ts:1:seed', name = 'seed', kind = 'function', path = 'src/seed.ts', line = 1, calls = { { 'src/types.ts:1:Order', 2, 13 } } },
    { id = 'src/types.ts:1:Order', name = 'Order', kind = 'class', path = 'src/types.ts', line = 1 },
  },
}
types.attach(m, {
  ['src/run.ts:1:placeOrder'] = 'function placeOrder(cart: Cart, n: number): Promise<Order>',
  ['src/run.ts:20:ship'] = 'const ship: (order: Order, cart: Cart) => void',
  ['src/seed.ts:1:seed'] = 'function seed(): void',
  ['src/nowhere.ts:1:gone'] = 'function gone(o: Order): Order',
}, { ['src/types.ts:1:Order'] = { 'src/seed.ts:1:seed' } })
eq(m.flows.Order.gives, { 'src/run.ts:1:placeOrder', 'src/seed.ts:1:seed' }, 'Order made by what returns it and what news it')
eq(m.flows.Order.new, { ['src/seed.ts:1:seed'] = true }, 'the new one is marked')
eq(m.flows.Order.takes, { { id = 'src/run.ts:20:ship', param = 'order' } }, 'Order taken by ship')
eq(m.flows.Cart.takes, { { id = 'src/run.ts:1:placeOrder', param = 'cart' }, { id = 'src/run.ts:20:ship', param = 'cart' } }, 'Cart taken by both')
eq(
  vim.tbl_map(function(f)
    return f.name .. ' ' .. f.n
  end, m.flowlist),
  { 'Order 3', 'Cart 2' },
  'the flows, most travelled first; a hover off the graph left out'
)
types.attach(m, {
  ['src/run.ts:20:ship'] = 'const ship: (order: Order, again: Order, cart: Cart) => Cart',
}, {})
eq(m.flows.Order.takes, { { id = 'src/run.ts:20:ship', param = 'again' }, { id = 'src/run.ts:20:ship', param = 'order' } }, 'a parameter each')
eq(types.takers(m.flows.Order), { 'src/run.ts:20:ship' }, 'takers: a function once, whatever its parameters')
eq(types.named(m.sigs['src/run.ts:20:ship'], m.flows), { 'Order', 'Cart' }, 'named: the repo types of a signature, each once')

io.stdout:write(('%d checks, %d failed\n'):format(checks, #failures))
os.exit(#failures == 0 and 0 or 1)
