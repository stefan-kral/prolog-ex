#!/usr/bin/env python3
# cmp.py scryer.out prologex.out cases.pl [swi.out] – vergleicht die Läufe
# von head.pl (und head_swi.pl): Zeilen "Id post|lab|postc|labc|crash …";
# hinter " NORM " steht der Zustand ohne Reihenfolge und
# Modulqualifikation der Restziele, hinter " DOMS " die Domänen
import sys, re

KINDS = ('post', 'lab', 'postc', 'labc', 'crash')

def load(f):
    d = {}
    for line in open(f, errors='replace'):
        m = re.match(r'^(\d+) (%s) (.*)$' % '|'.join(KINDS), line.rstrip('\n'))
        if m:
            d[(m.group(1), m.group(2))] = m.group(3)
    return d

# ohne Reihenfolge und Qualifikation der Restziele, mit den Domänen
def norm(v):
    return v.split(' NORM ')[1] if v and ' NORM ' in v else v

def doms(v):
    return v.split(' DOMS ')[1] if v and ' DOMS ' in v else v

# gewollte Abweichung von PrologEx: cumulative/1,2 mit fester Dauer legt
# je Zeitscheibe ein reifiziertes in/2 an statt zweier Vergleiche (siehe
# clpz.pl task_running_d/4, README) – domänenkonsistent, also stärker:
# andere Restziele, kleinere Domänen, Aufstellen kann schon scheitern, ff
# und ffc beschriften in anderer Reihenfolge. Gleich bleiben müssen die
# Lösungen (als Menge)
DEVIATE = re.compile(r'cumulative\(')

def split_top(t):
    # Elemente der obersten Ebene einer Liste "[a,b(c,d),[e]]"
    out, d, cur = [], 0, ''
    for ch in t[1:-1]:
        if ch in '([': d += 1
        if ch in ')]': d -= 1
        if ch == ',' and d == 0: out.append(cur); cur = ''
        else: cur += ch
    if cur: out.append(cur)
    return out

def sols(v):
    m = re.match(r"^'-'\((\d+),(\[.*\])\)$", v or '')
    if not m: return v
    n, l = int(m.group(1)), m.group(2)
    return (n, sorted(split_top(l)) if n <= 40 else None)

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

def count(v):
    m = re.match(r"^'-'\((\d+),", v or '')
    return m.group(1) if m else v

def scryer_known(i, t, a, b):
    s, p = a.get((i, t)), b.get((i, t))
    S = lambda k: a.get((i, k)); P = lambda k: b.get((i, k))
    if (t in ('post', 'lab')
            and (count(S('lab')) != count(S('labc')) or kind(S('post')) != kind(S('postc')))
            and count(P('lab')) == count(S('labc')) and P('labc') == S('labc')
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

def deviation(k):
    i = k[0]
    if not any(DEVIATE.search(l) for l in src.get(i, [])):
        return False
    if k[1] in ('post', 'postc'):
        # Aufstellen darf sich unterscheiden, solange die Lösungen gleich sind
        return sols(a.get((i, 'lab'))) == sols(b.get((i, 'lab')))
    if k[1] in ('lab', 'labc'):
        return sols(a.get(k)) == sols(b.get(k))
    return False

differ = [k for k in keys if norm(a.get(k)) != norm(b.get(k)) and counts(k) and not deviation(k)]
known = {k[0] for k in differ if scryer_known(k[0], k[1], a, b)}
ids = sorted({k[0] for k in differ if not scryer_known(k[0], k[1], a, b)}, key=int)
known -= set(ids)

# --- SWI-Prolog (library(clpfd)) als dritte Stimme ------------------------
# Verglichen werden Domänen nach dem Aufstellen (SWI schreibt die
# Restziele anders), die Lösungen in Reihenfolge und über call/1 sortiert.
# Mehrheit: weicht PrologEx allein ab (Scryer und SWI gleich), ist das ein
# starkes Zeichen; weicht Scryer allein ab, eher Scryer (oder clpz gegen
# clpfd); SWI allein: clpfd gegen clpz, nur gezählt.
# nvalue/2 gibt es in SWI nicht.
w = load(sys.argv[4]) if len(sys.argv) > 4 else None
NOSWI = re.compile(r'nvalue\(')

def view(v, t, i):
    dev = any(DEVIATE.search(l) for l in src.get(i, []))
    if t == 'post':
        if dev: return None
        return doms(v) if v and ' DOMS ' in v else v
    if t == 'postc':
        return None if dev else v
    if t in ('lab', 'labc'):
        return sols(v) if dev else v
    return v

classes = {}
known_any = {k[0] for k in keys if scryer_known(k[0], k[1], a, b)}
if w is not None:
    for i in sorted({k[0] for k in keys}, key=int):
        if any(NOSWI.search(l) for l in src.get(i, [])):
            continue
        cl = None
        for t in ('post', 'lab', 'postc', 'labc'):
            vs, vp, vw = (view(x.get((i, t)), t, i) for x in (a, b, w))
            if vs == vp == vw:
                continue
            # über call/1: wie oben nur verschiedene Lösungen
            if t in ('postc', 'labc') and not all(x is not None and str(x).startswith("'-'(") for x in (vs, vp, vw)):
                continue
            c = ('PrologEx allein' if vs == vw else 'Scryer allein' if vp == vw
                 else 'SWI allein' if vs == vp else 'alle verschieden')
            rank = ['SWI allein', 'Scryer allein', 'alle verschieden', 'PrologEx allein']
            if cl is None or rank.index(c) > rank.index(cl):
                cl = c
        # mit bekanntem Scryer-Fehler (übersetzt anders als mit call/1,
        # PrologEx wie Scryer mit call/1) zählt Scryer nicht als eigene
        # Stimme: weicht dann auch SWI ab, ist das SWI allein (etwa: PrologEx
        # und Scryer mit call/1 scheitern schon vor einem Ziel, an dem SWI
        # mit schwächerer Propagation einen Fehler wirft)
        if cl == 'alle verschieden' and i in known_any:
            cl = 'SWI allein'
        if cl:
            classes[i] = cl
    # gegen Scryer verschieden, aber SWI wie PrologEx: eher Scryer
    ids = [i for i in ids if classes.get(i) not in ('Scryer allein', 'SWI allein')]
    ids = sorted(set(ids) | {i for i, c in classes.items() if c in ('PrologEx allein', 'alle verschieden')}, key=int)

swi = ''
if w is not None:
    cc = {c: sum(1 for x in classes.values() if x == c) for c in ('PrologEx allein', 'Scryer allein', 'SWI allein', 'alle verschieden')}
    swi = 'SWI: PrologEx allein %d, Scryer allein %d, SWI allein %d, alle verschieden %d  ' % tuple(cc.values())
print('Fälle %d  Scryer %d  PrologEx %d  nur Reihenfolge der Restziele %d  '
      'bekannte Scryer-Fehler %d  %sverschieden %d'
      % (len({k[0] for k in keys}), len(a), len(b), len(order), len(known), swi, len(ids)))

def show(i, with_w):
    print('\n'.join(l for l in src.get(i, []) if not l.startswith('g(')))
    for t in KINDS:
        vals = [a.get((i, t)), b.get((i, t))] + ([w.get((i, t))] if with_w else [])
        if len(set(vals)) > 1:
            print('  S %s: %s' % (t, (a.get((i, t)) or '-')[:600]))
            print('  P %s: %s' % (t, (b.get((i, t)) or '-')[:600]))
            if with_w: print('  W %s: %s' % (t, (w.get((i, t)) or '-')[:600]))
    print()

for i in ids:
    if w is not None and i in classes: print('[%s]' % classes[i])
    show(i, w is not None)

# Beispiele für die übrigen Klassen (höchstens je 3)
if w is not None:
    for c in ('Scryer allein', 'SWI allein'):
        ex = [i for i, x in sorted(classes.items(), key=lambda kv: int(kv[0])) if x == c][:3]
        if ex:
            print('--- Beispiele %s' % c)
            for i in ex: show(i, True)
