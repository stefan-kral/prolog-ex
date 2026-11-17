#!/usr/bin/env python3
# cmp.py o.scr o.swi o.px [c.pl] – je Fall die Ausgaben (Text) vergleichen.
# Fälle mit \+//1 oder (->)//2 ohne Else (in c.pl als "% nonstd Id"
# markiert; im Entwurf implementierungsabhängig, Scryer lehnt sie ab):
# nur PrologEx gegen SWI.
# Klassen: gleich; SWI allein / Scryer allein anders (die anderen beiden
# gleich); PrologEx allein anders (verdächtig); alle verschieden; fehlt
# (ein System ohne Zeile, etwa abgebrochen). Erste Zeile: Zusammenfassung.
import sys

def rd(f):
    d = {}; extra = []
    for l in open(f, errors='replace'):
        l = l.rstrip('\n')
        k, _, v = l.partition(' ')
        if k.isdigit() and (v.startswith('[') or v == 'crash'): d[int(k)] = v
        elif l.strip(): extra.append(l)
    return d, extra

scr, e1 = rd(sys.argv[1]); swi, e2 = rd(sys.argv[2]); px, e3 = rd(sys.argv[3])
nonstd = set()
if len(sys.argv) > 4:
    for l in open(sys.argv[4]):
        if l.startswith('% nonstd '): nonstd.add(int(l.split()[2]))
for i in nonstd: scr.pop(i, None)
cls = {}; lines = []
for i in sorted(set(scr) | set(swi) | set(px)):
    a, w, p = scr.get(i), swi.get(i), px.get(i)
    if a == w == p and i not in nonstd: c = 'gleich'
    elif a == 'crash' and w is not None:
        c = 'Scryer abgestürzt' if p == w else 'PrologEx ≠ SWI (Scryer abgestürzt)'
    elif i in nonstd: c = 'nonstd gleich' if p == w else 'nonstd: PrologEx ≠ SWI'
    elif p is None or (a is None and w is None): c = 'fehlt'
    elif p == a: c = 'SWI allein'
    elif p == w: c = 'Scryer allein'
    elif a == w: c = 'PrologEx allein'
    else: c = 'alle verschieden'
    if c not in ('gleich', 'nonstd gleich', 'Scryer abgestürzt'):
        lines.append('%d %s\n  SCR %s\n  SWI %s\n  PX  %s' % (i, c, a, w, p))
    cls[c] = cls.get(c, 0) + 1
bad = (cls.get('PrologEx allein', 0) + cls.get('alle verschieden', 0) + cls.get('fehlt', 0) +
       cls.get('nonstd: PrologEx ≠ SWI', 0) + cls.get('PrologEx ≠ SWI (Scryer abgestürzt)', 0))
print('Fälle %d  ' % sum(cls.values()) + '  '.join('%s %d' % kv for kv in sorted(cls.items())) +
      '  verdächtig %d' % bad)
for x, nm in ((e1, 'SCR'), (e2, 'SWI'), (e3, 'PX')):
    for l in x[:3]: print('  %s extra: %s' % (nm, l[:200]))
print('\n'.join(lines))
