#!/usr/bin/env python3
# cmp.py swi.txt px_http.txt scryer.txt px_ser.txt (von run.sh) – Auswertung der
# JSONTestSuite: je Parser die Verstoesse (y_ abgelehnt, n_ angenommen,
# Zeitueberschreitung/Absturz), dazu die Unterschiede PrologEx – Vorbild
# (http/json gegen SWI, serialization/json gegen Scryer).
import sys
def rd(f):
    d = {}
    for l in open(f, errors='replace'):
        k, _, v = l.strip().partition(' ')
        if k[:2] in ('y_', 'n_', 'i_') and k.endswith('.json'): d[k] = v
    return d
names = ['SWI http/json', 'PrologEx http/json', 'Scryer serialization/json', 'PrologEx serialization/json']
res = [rd(f) for f in sys.argv[1:5]]
files = sorted(set().union(*res))
def ok(f, v):
    if v is None or v.startswith('timeout'): return False
    if f.startswith('y_'): return v == 'accept'
    if f.startswith('n_'): return v != 'accept'
    return True
for n, r in zip(names, res):
    bad = [f for f in files if not ok(f, r.get(f))]
    to = lambda f: (r.get(f) or 'timeout').startswith('timeout')
    y = sum(1 for f in bad if f.startswith('y_') and not to(f))
    nn = sum(1 for f in bad if f.startswith('n_') and not to(f))
    t = sum(1 for f in files if to(f))
    acc_i = sum(1 for f in files if f.startswith('i_') and r.get(f) == 'accept')
    print('%-30s y_ abgelehnt %3d  n_ angenommen %3d  Zeit/Absturz %d  i_ angenommen %d/35' % (n, y, nn, t, acc_i))
print()
for (a, b) in ((0, 1), (2, 3)):
    diff = [f for f in files if (res[a].get(f) == 'accept') != (res[b].get(f) == 'accept')]
    print('%s gegen %s: %d Unterschiede' % (names[b], names[a], len(diff)))
    for f in diff: print('   %-55s %-20s %s' % (f, res[a].get(f), res[b].get(f)))
for i in (1, 3):
    print('\n%s – Verstösse:' % names[i])
    for f in files:
        if not ok(f, res[i].get(f)): print('   %-55s %s' % (f, res[i].get(f)))
