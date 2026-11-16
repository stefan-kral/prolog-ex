#!/usr/bin/env python3
# cmp.py o.scr o.swi o.px [o.bf] – je Fall die Lösungslisten vergleichen.
# Klassen: gleich; nur Reihenfolge (gleiche Menge); SWI allein / Scryer
# allein verschieden (die anderen beiden gleich); PrologEx allein
# verschieden (verdächtig); alle verschieden. Mit o.bf (Durchprobieren,
# nur monotone Fälle) entscheidet die Lösungsmenge von dort: PrologEx
# bestätigt, oder PrologEx ≠ Durchprobieren (verdächtig, auch wenn die
# anderen übereinstimmen). Erste Zeile: Zusammenfassung.
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
bf = rd(sys.argv[4])[0] if len(sys.argv) > 4 else {}

def bf_verdict(i, p):
    # True: PrologEx hat die Lösungsmenge des Durchprobierens; False: nicht;
    # None: kein Urteil (nicht monoton oder Durchprobieren mit Fehler)
    b = bf.get(i)
    if b is None: return None
    nb = norm(b)
    np = norm(p or '')
    # Fehler hängen von der Reihenfolge ab (clpb an einer Variablen, die
    # clpz auf -1 setzt): darüber urteilt das Durchprobieren nicht
    if nb[0] != 'L' or np[0] != 'L': return None
    return np[0] == 'L' and sorted(set(map(str, np[1]))) == sorted(set(map(str, nb[1])))
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
    v = bf_verdict(i, p)
    # nicht monoton (kein Durchprobieren), Scryer an when(?=(V, V)) mit
    # domain_error gescheitert, PrologEx und SWI verschieden: die Reihenfolge
    # der Weckziele an einer Variablen (PrologEx: Reihenfolge des Anhängens;
    # SWI: Modul für Modul) entscheidet über \== und Co. – kein Urteil
    if (c in ('alle verschieden', 'PrologEx allein') and bf and i not in bf and
            a == 'ex(domain_error/2)'):
        c = 'nicht monoton, Scryer ?=, SWI anders'
    if v is False: c = 'PrologEx ≠ Durchprobieren'
    elif v is True and c in ('PrologEx allein', 'alle verschieden'): c = 'PrologEx bestätigt (Durchprobieren)'
    if c != 'gleich':
        lines.append('%d %s\n  SCR %s\n  SWI %s\n  PX  %s\n  BF  %s' % (i, c, a, w, p, bf.get(i)))
    cls[c] = cls.get(c, 0) + 1
bad = (cls.get('PrologEx allein', 0) + cls.get('alle verschieden', 0) + cls.get('fehlt', 0) +
       cls.get('PrologEx ≠ Durchprobieren', 0))
print('Fälle %d  ' % len(ids) + '  '.join('%s %d' % kv for kv in sorted(cls.items())) +
      '  verdächtig %d' % bad)
for x in (e1, e2, e3):
    for l in x[:5]: print('  extra:', l)
print('\n'.join(lines))
