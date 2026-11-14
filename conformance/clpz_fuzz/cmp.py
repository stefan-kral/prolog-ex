#!/usr/bin/env python3
# cmp.py scryer.out prologex.out cases.pl – vergleicht zwei Läufe von head.pl
# Zeilen "Id post|lab|postc|labc|crash …"; hinter " NORM " steht der
# Zustand ohne Reihenfolge und Modulqualifikation der Restziele
import sys, re

KINDS = ('post', 'lab', 'postc', 'labc', 'crash')

def load(f):
    d = {}
    for line in open(f, errors='replace'):
        m = re.match(r'^(\d+) (%s) (.*)$' % '|'.join(KINDS), line.rstrip('\n'))
        if m:
            d[(m.group(1), m.group(2))] = m.group(3)
    return d

def norm(v):
    return v.split(' NORM ')[1] if v and ' NORM ' in v else v

# Fehler von Scryer: in übersetzten Klauseln liest ein Vergleich wie
# 0 >= X gleich nach dem Binden einer attributierten Variablen X falsch –
# type_error(evaluable, …), instantiation_error, aber auch ein falsches
# Gelingen oder Scheitern (X in 0, X #=< 0 oder ohne clpz:
# put_atts(X, a(1)), X = 2, 5 >= X). Bekannt ist ein Unterschied bei
# post/lab daher, wenn sich Scryer selbst widerspricht (übersetzt anders
# als mit call/1) und PrologEx Scryer mit call/1 folgt, oder wenn Scryer
# aus is/2 mit type_error(evaluable, …) scheitert
def kind(v):
    return 'fail' if v in (None, "'fail'") else v if v.startswith("'err'") else 'ok'

def scryer_known(i, t, a, b):
    s, p = a.get((i, t)), b.get((i, t))
    S = lambda k: a.get((i, k)); P = lambda k: b.get((i, k))
    if (t in ('post', 'lab')
            and (norm(S('lab')) != norm(S('labc')) or kind(S('post')) != kind(S('postc')))
            and norm(P('lab')) == norm(S('labc')) and norm(P('labc')) == norm(S('labc'))
            and kind(P('post')) == kind(S('postc'))):
        return True
    return (s is not None and ("'type_error'('evaluable'" in s or "'is')" in s)
            and s != p)

a = load(sys.argv[1]); b = load(sys.argv[2])
src = {}
for line in open(sys.argv[3]):
    m = re.match(r'^[pgo]\((\d+),', line)
    if m:
        src.setdefault(m.group(1), []).append(line.rstrip())
keys = sorted(set(a) | set(b), key=lambda k: (int(k[0]), KINDS.index(k[1])))
order = [k for k in keys if a.get(k) != b.get(k) and norm(a.get(k)) == norm(b.get(k))]
# über call/1 läuft Scryer mal mit, mal ohne Expansion, PrologEx ohne; die
# Propagation ist daher verschieden stark (etwa X//X #= max(2,-2): ohne
# Expansion scheitert es, mit nicht; Scryers clpz_equal/2 direkt wie
# PrologEx). Zählen: nur verschiedene Lösungen von labc
def counts(k):
    if k[1] == 'postc':
        return False
    if k[1] == 'labc':
        return all(v is not None and v.startswith("'-'(") for v in (a.get(k), b.get(k)))
    return True

differ = [k for k in keys if norm(a.get(k)) != norm(b.get(k)) and counts(k)]
known = {k[0] for k in differ if scryer_known(k[0], k[1], a, b)}
ids = sorted({k[0] for k in differ if not scryer_known(k[0], k[1], a, b)}, key=int)
known -= set(ids)
print('Fälle %d  Scryer %d  PrologEx %d  nur Reihenfolge der Restziele %d  '
      'bekannte Scryer-Fehler %d  verschieden %d'
      % (len({k[0] for k in keys}), len(a), len(b), len(order), len(known), len(ids)))
for i in ids:
    print('\n'.join(l for l in src.get(i, []) if not l.startswith('g(')))
    for t in KINDS:
        if a.get((i, t)) != b.get((i, t)):
            print('  S %s: %s' % (t, (a.get((i, t)) or '-')[:600]))
            print('  P %s: %s' % (t, (b.get((i, t)) or '-')[:600]))
    print()
