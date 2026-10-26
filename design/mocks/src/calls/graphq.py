import json, collections, sys, os
g = json.load(open("/tmp/seam-tree/v2/data/core-graph.json"))
D, E = g["decls"], g["edges"]
idx = json.load(open(os.path.expanduser("~/.cache/nvim/seam/home%alex%Work%libs%raf-run-redesign/treesitter.json")))
usefiles = {e["id"]: len({u["path"] for u in e["uses"]}) for e in idx["exports"]}
def find(name, path=""):
    return [k for k, v in D.items() if v["name"] == name and path in v["path"]][0]
def reach(root, cut=()):
    hops = {root: 0}; q = [root]
    while q:
        n = q.pop(0)
        for t, _ in E.get(n, []):
            if t in cut: continue
            if t not in hops: hops[t] = hops[n] + 1; q.append(t)
    return hops
def paths(root, target, cut=()):
    # simple paths count, depth-limited
    c = 0
    def go(n, seen):
        nonlocal c
        if n == target: c += 1; return
        for t in dict.fromkeys(t for t, _ in E.get(n, [])):
            if t in seen or t in cut: continue
            go(t, seen | {t})
    go(root, {root}); return c
def allpaths(root, target):
    out = []
    def go(n, seen, acc):
        if n == target: out.append(acc); return
        for t in dict.fromkeys(t for t, _ in E.get(n, [])):
            if t in seen: continue
            lines = [ln for tt, ln in E[n] if tt == t]
            go(t, seen | {t}, acc + [(t, lines)])
    go(root, {root}, []); return out
if __name__ == "__main__":
    r = find(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
    h = reach(r)
    print(D[r]["id"], "reaches", len(h) - 1)
    for k in sorted(h, key=lambda k: (D[k]["path"], D[k]["line"])):
        sites = [ln for t, ln in E.get(r, []) if t == k]
        print(f'{h[k]}  {paths(r,k)}  {usefiles.get(k,"·")}  {D[k]["path"]}:{D[k]["line"]}  {D[k]["name"]}  {"exp" if D[k]["exported"] else "local"}  sites={sites}')
