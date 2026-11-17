# count.py DATEI... : Modelle jeder DIMACS-Formel durch Durchprobieren
# (je Variable ein Bitvektor über alle 2^n Belegungen); "Name Anzahl"
import sys, os
def clauses(fn):
    n = None; cls = []; cur = []
    for l in open(fn):
        l = l.strip()
        if l.startswith('%'): break
        if not l or l[0] == 'c': continue
        if l[0] == 'p': n = int(l.split()[2]); continue
        for t in l.split():
            v = int(t)
            if v == 0:
                if cur: cls.append(cur); cur = []
            else: cur.append(v)
    if cur: cls.append(cur)
    return n, cls
cols = {}
for fn in sys.argv[1:]:
    n, cls = clauses(fn)
    N = 1 << n
    full = N and (1 << N) - 1
    if n not in cols:
        cs = []
        for i in range(n):
            blk = '0' * (1 << i) + '1' * (1 << i)
            cs.append(int((blk * (N >> (i + 1)))[::-1], 2))
        cols[n] = cs
    cs = cols[n]
    f = full
    for c in cls:
        g = 0
        for l in c:
            g |= cs[l - 1] if l > 0 else full ^ cs[-l - 1]
        f &= g
    print(os.path.basename(fn)[:-4], bin(f).count('1'))
