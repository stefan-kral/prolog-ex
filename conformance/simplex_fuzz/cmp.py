#!/usr/bin/env python3
# cmp.py scryer.out prologex.out swi.out – Zielwerte vergleichen (Brüche
# als 15 rdiv 2 bzw. 15r2)
import sys, re
from fractions import Fraction
def load(f):
    d = {}
    for l in open(f):
        m = re.match(r'^(\d+) (.*)$', l.strip())
        if not m: continue
        v = m.group(2).strip()
        m2 = re.match(r'^(-?\d+)\s*(?:rdiv|r)\s*(\d+)$', v)
        if m2: v = Fraction(int(m2.group(1)), int(m2.group(2)))
        elif re.match(r'^-?\d+$', v): v = Fraction(int(v))
        d[m.group(1)] = v
    return d
a, b, c = (load(f) for f in sys.argv[1:4])
diff = [k for k in sorted(set(a)|set(b)|set(c), key=int) if not (a.get(k) == b.get(k) == c.get(k))]
kinds = {}
for k in (set(a)|set(b)|set(c)):
    v = b.get(k); t = 'fail' if v == 'fail' else 'err' if isinstance(v, str) else 'wert'
    kinds[t] = kinds.get(t, 0) + 1
print('Fälle', len(set(a)|set(b)|set(c)), 'PrologEx-Ergebnisse', kinds, 'verschieden', len(diff))
for k in diff[:10]:
    print(k, 'Scryer:', a.get(k), '| PrologEx:', b.get(k), '| SWI:', c.get(k))
