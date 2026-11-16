#!/usr/bin/env python3
# cmp3.py A.scr A.swi A.px – Zeilen "Name Ergebnis" der drei Systeme
import sys
def rd(f):
    d = {}
    for l in open(f):
        k, _, v = l.rstrip('\n').partition(' ')
        d[k] = v
    return d
s, w, p = rd(sys.argv[1]), rd(sys.argv[2]), rd(sys.argv[3])
for k in s:
    if s[k] != p.get(k) or (k in w and w[k] != p.get(k)):
        print(f"{k}\n  SCR {s[k]}\n  SWI {w.get(k)}\n  PX  {p.get(k)}")
for k in p:
    if k not in s: print('nur PX', k, p[k])
