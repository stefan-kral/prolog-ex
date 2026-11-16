#!/usr/bin/env python3
# cmp.py A.scr B.px – je Fall die Ausgaben vergleichen; Zeilen
# verify(_,none) (Hooks von Modulen ohne Attribute an der Variablen)
# getrennt zählen, Variablennamen _123 vereinheitlichen
import re, sys
def parse(f):
    d = {}; cur = None; order = []
    for l in open(f):
        l = re.sub(r'_[0-9]+|_[A-Z][0-9]*', '_', l.rstrip('\n'))
        if l.startswith('== '): cur = l[3:]; d[cur] = []; order.append(cur)
        elif cur: d[cur].append(l)
        else: print(f, 'VORSPANN', l)
    return d, order
s, o = parse(sys.argv[1]); p, _ = parse(sys.argv[2])
strip = '--strict' not in sys.argv
for k in o:
    a, b = s.get(k), p.get(k, ['<fehlt>'])
    if strip:
        b = [x for x in b if not x.startswith('verify(') or 'none)' not in x]
    if a != b:
        print('=====', k); print('  SCR:', ' | '.join(a)); print('  PX :', ' | '.join(b))
for k in p:
    if k not in s: print('nur PX:', k)
