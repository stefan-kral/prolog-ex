#!/usr/bin/env python3
# cmp.py scryer.out prologex.out cases.pl – vergleicht zwei Läufe von head.pl
# Zeilen "Id post …", "Id lab …", "Id crash …"; hinter " NORM " steht der
# Zustand ohne Reihenfolge und Modulqualifikation der Restziele
import sys, re

def load(f):
    d = {}
    for line in open(f, errors='replace'):
        m = re.match(r'^(\d+) (post|lab|crash) (.*)$', line.rstrip('\n'))
        if m:
            d[(m.group(1), m.group(2))] = m.group(3)
    return d

def norm(v):
    return v.split(' NORM ')[1] if v and ' NORM ' in v else v

# bekannte Fehler von Scryer: library(clpz) wirft type_error(evaluable, …)
# etwa bei [X] ins 4, 5 #= X (PrologEx rechnet richtig)
def scryer_known(s, p):
    return (s is not None and "'type_error'('evaluable'" in s
            and (p is None or "'err'(" not in p))

a = load(sys.argv[1]); b = load(sys.argv[2])
src = {}
for line in open(sys.argv[3]):
    m = re.match(r'^[po]\((\d+),', line)
    if m:
        src.setdefault(m.group(1), []).append(line.rstrip())
keys = sorted(set(a) | set(b), key=lambda k: (int(k[0]), k[1]))
order = [k for k in keys if a.get(k) != b.get(k) and norm(a.get(k)) == norm(b.get(k))]
known = {k[0] for k in keys if norm(a.get(k)) != norm(b.get(k)) and scryer_known(a.get(k), b.get(k))}
ids = sorted({k[0] for k in keys if norm(a.get(k)) != norm(b.get(k))} - known, key=int)
print('Fälle %d  Scryer %d  PrologEx %d  nur Reihenfolge der Restziele %d  '
      'bekannte Scryer-Fehler %d  verschieden %d'
      % (len({k[0] for k in keys}), len(a), len(b), len(order), len(known), len(ids)))
for i in ids:
    print('\n'.join(src.get(i, [])))
    for t in ('post', 'lab', 'crash'):
        if a.get((i, t)) != b.get((i, t)):
            print('  S %s: %s' % (t, (a.get((i, t)) or '-')[:600]))
            print('  P %s: %s' % (t, (b.get((i, t)) or '-')[:600]))
    print()
