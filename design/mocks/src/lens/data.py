import json, os, re, fnmatch
from collections import defaultdict, deque, Counter
F = os.path.expanduser("~/.cache/nvim/seam/home%alex%Work%libs%raf-run-redesign/treesitter.json")
RAF = "/home/alex/Work/libs/raf-run-redesign/"
D = json.load(open(F))
EX = D["exports"]
N = {n["id"]: n for n in D["nodes"]}
CALLERS = defaultdict(dict)   # callee -> {caller: [lines]}
for a, n in N.items():
    for t, l, c in n["calls"]:
        if t in N: CALLERS[t].setdefault(a, []).append(l)
FILES = sorted({e["path"] for e in EX} | {u["path"] for e in EX for u in e["uses"]})
def is_test(p): return fnmatch.fnmatch(p.rsplit("/",1)[-1].lower(), "*.test.*")
def src(path, a, b):
    ls = open(RAF + path).read().split("\n")
    return [(n, ls[n - 1]) for n in range(a, b + 1)]
