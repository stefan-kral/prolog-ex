#!/usr/bin/env python3
# cmp.py o.scr o.swi o.px – je Fall die Lösungslisten vergleichen.
# Klassen: gleich; nur Reihenfolge (gleiche Menge); SWI allein / Scryer
# allein verschieden (die anderen beiden gleich); PrologEx allein
# verschieden (verdächtig); alle verschieden. Erste Zeile: Zusammenfassung.
import sys, ast

def rd(f):
    d = {}; extra = []
    for l in open(f, errors='replace'):
        l = l.rstrip('\n')
        k, _, v = l.partition(' ')
        if k.isdigit(): d[int(k)] = v
        elif l.strip(): extra.append(l)
    return d, extra

def norm(v):
    # Lösungsliste als Liste von Tupeln; sonst der Text
    try:
        return ('L', ast.literal_eval(v))
    except Exception:
        return ('X', v)

def same_set(a, b):
    return a[0] == b[0] == 'L' and sorted(map(str, a[1])) == sorted(map(str, b[1]))

scr, e1 = rd(sys.argv[1]); swi, e2 = rd(sys.argv[2]); px, e3 = rd(sys.argv[3])
cls = {}; lines = []
ids = sorted(set(scr) | set(swi) | set(px))
for i in ids:
    a, w, p = scr.get(i), swi.get(i), px.get(i)
    if a == w == p: c = 'gleich'
    elif a is None or p is None: c = 'fehlt'
    else:
        na, nw, np = norm(a or ''), norm(w or ''), norm(p or '')
        if p == a or (p is not None and a is not None and same_set(np, na)):
            if p == a: c = 'SWI allein' if w is not None else 'ohne SWI'
            elif w == p or (w is not None and same_set(nw, np)): c = 'nur Reihenfolge'
            else: c = 'SWI allein (Reihenfolge)'
        elif p == w or (w is not None and same_set(np, nw)):
            c = 'Scryer allein'
        else:
            c = 'alle verschieden' if a != w else 'PrologEx allein'
        lines.append('%d %s\n  SCR %s\n  SWI %s\n  PX  %s' % (i, c, a, w, p))
    cls[c] = cls.get(c, 0) + 1
bad = cls.get('PrologEx allein', 0) + cls.get('alle verschieden', 0) + cls.get('fehlt', 0)
print('Fälle %d  ' % len(ids) + '  '.join('%s %d' % kv for kv in sorted(cls.items())) +
      '  verdächtig %d' % bad)
for x in (e1, e2, e3):
    for l in x[:5]: print('  extra:', l)
print('\n'.join(lines))
