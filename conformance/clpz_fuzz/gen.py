#!/usr/bin/env python3
# Zufällige kleine clpz-Probleme: p(Id, [X1,..]) :- Bedingungen.  dieselben
# Bedingungen als Term g(Id, [X1,..], Bedingungen).  o(Id, [X1,..], Optionen).
import random, sys

def var(st):
    return random.choice(st['vs'])

def num():
    return str(random.choice([-3,-2,-1,0,1,2,3,4,5,7,10]))

def expr(st, d):
    r = random.random()
    if d <= 0 or r < 0.35:
        return var(st) if random.random() < 0.75 else num()
    a = lambda: expr(st, d-1)
    k = random.choice(['+','+','-','*','neg','abs','min','max','//','mod','rem','^','cmul'])
    if k == 'neg': return '-(%s)' % a()
    if k == 'abs': return 'abs(%s)' % a()
    if k in ('min','max'): return '%s(%s,%s)' % (k, a(), a())
    if k == '^': return '(%s)^%d' % (a(), random.randint(0,3))
    if k == 'cmul': return '%d*%s' % (random.choice([-3,-2,2,3,5]), var(st))
    return '(%s %s %s)' % (a(), k, a())

def rel():
    return random.choice(['#=','#=','#\\=','#<','#>','#=<','#>='])

def lin(st):
    # lineare Summe über Variablen (die Abkürzer)
    n = random.randint(1, len(st['vs']))
    vs = random.sample(st['vs'], n)
    terms = []
    for v in vs:
        c = random.choice([1,1,1,-1,2,-2,3,5])
        terms.append(v if c == 1 else '%d*%s' % (c, v))
    s = terms[0]
    for t in terms[1:]:
        s = '%s + %s' % (s, t)
    return s

def reifiable(st, d):
    r = random.random()
    if d <= 0 or r < 0.5:
        return '%s %s %s' % (expr(st, 1), rel(), expr(st, 1))
    k = random.choice(['#/\\','#\\/','#==>','#<==','#<==>','#\\','not'])
    if k == 'not': return '#\\ (%s)' % reifiable(st, d-1)
    return '(%s) %s (%s)' % (reifiable(st, d-1), k, reifiable(st, d-1))

def lst(st, k=None):
    k = k or random.randint(1, len(st['vs']))
    return '[%s]' % ','.join(random.sample(st['vs'], min(k, len(st['vs']))))

def dom():
    r = random.random()
    if r < 0.6:
        lo = random.randint(-3, 3); return '%d .. %d' % (lo, lo + random.randint(0, 5))
    if r < 0.8:
        a = random.randint(-3, 1); b = a + random.randint(0, 2)
        c = b + random.randint(2, 4); e = c + random.randint(0, 2)
        return '%d .. %d \\/ %d .. %d' % (a, b, c, e)
    if r < 0.9: return str(random.randint(-2, 4))
    return random.choice(['0 .. sup', 'inf .. 2', 'inf .. sup'])

def ivar(st):
    # Variable oder kleine Zahl (für Dauern, Größen, Kosten)
    return var(st) if random.random() < 0.3 else str(random.randint(0, 3))

def global_(st):
    # globale Bedingungen: circuit/1, cumulative/1,2, disjoint2/1,
    # automaton/3, nvalue/2, serialized/2
    vs = st['vs']
    r = random.random()
    if r < 0.2:
        return 'circuit(%s)' % lst(st)
    if r < 0.4:
        k = random.randint(1, 3)
        ts = ['task(%s,%s,_,%s,%d)' % (var(st), ivar(st), ivar(st), i) for i in range(k)]
        if random.random() < 0.3:
            return 'cumulative([%s])' % ','.join(ts)
        return 'cumulative([%s], [limit(%d)])' % (','.join(ts), random.randint(0, 4))
    if r < 0.55:
        k = random.randint(1, 3)
        rs = ['r(%s,%d,%s,%d)' % (var(st), random.randint(0, 2), var(st), random.randint(0, 2)) for _ in range(k)]
        return 'disjoint2([%s])' % ','.join(rs)
    if r < 0.75:
        # Automat über Zuständen a, b, c mit Symbolen aus -1..3
        states = ['a', 'b', 'c'][:random.randint(1, 3)]
        arcs = set()
        for _ in range(random.randint(1, 6)):
            arcs.add('arc(%s,%d,%s)' % (random.choice(states), random.randint(-1, 3), random.choice(states)))
        nodes = ['source(%s)' % random.choice(states)] + ['sink(%s)' % x for x in random.sample(states, random.randint(1, len(states)))]
        return 'automaton(%s, [%s], [%s])' % (lst(st), ','.join(nodes), ','.join(sorted(arcs)))
    if r < 0.88:
        return 'nvalue(%s, %s)' % (random.choice([var(st), str(random.randint(0, 4))]), lst(st))
    k = random.randint(1, len(vs))
    l = random.sample(vs, k)
    return 'serialized([%s], [%s])' % (','.join(l), ','.join(str(random.randint(0, 3)) for _ in l))

def constraint(st):
    r = random.random()
    vs = st['vs']
    if r < 0.18: return global_(st)
    r = (r - 0.18) / 0.82
    if r < 0.22: return '%s %s %s' % (expr(st, 2), rel(), expr(st, 2))
    if r < 0.40: return '%s %s %s' % (lin(st), rel(), random.choice([num(), var(st), lin(st)]))
    if r < 0.48: return 'sum(%s, (%s), %s)' % (lst(st), rel(), random.choice([num(), var(st)]))
    if r < 0.56:
        l = random.sample(vs, random.randint(1, len(vs)))
        cs = [str(random.choice([-2,-1,0,1,2,3])) for _ in l]
        return 'scalar_product([%s], [%s], (%s), %s)' % (','.join(cs), ','.join(l), rel(), random.choice([num(), var(st)]))
    if r < 0.66: return reifiable(st, 2)
    if r < 0.70: return '%s #<==> (%s)' % (st['b'], reifiable(st, 1))
    if r < 0.74: return random.choice(['all_different', 'all_distinct']) + '(%s)' % lst(st)
    if r < 0.77:
        l = lst(st)
        return 'global_cardinality(%s, [%s])' % (l, ','.join('%d-%s' % (k, random.choice(['_', str(random.randint(0, 2))])) for k in random.sample(range(-1, 4), 3)))
    if r < 0.80: return 'element(%s, %s, %s)' % (var(st), lst(st), var(st))
    if r < 0.83:
        k = random.randint(1, min(3, len(vs)))
        l = random.sample(vs, k)
        tups = ['[%s]' % ','.join(str(random.randint(-1, 4)) for _ in l) for _ in range(random.randint(1, 4))]
        return 'tuples_in([[%s]], [%s])' % (','.join(l), ','.join(tups))
    if r < 0.85: return 'lex_chain([%s,%s])' % (lst(st, 2), lst(st, 2))
    if r < 0.87: return 'chain((%s), %s)' % (random.choice(['#<', '#=<', '#>', '#>=', '#=']), lst(st))
    if r < 0.89: return 'zcompare(%s, %s, %s)' % (random.choice(['O', '(<)', '(=)', '(>)']), expr(st, 1), expr(st, 1))
    if r < 0.92: return '%s in %s' % (var(st), dom())
    if r < 0.95: return '%s ins %s' % (lst(st), dom())
    if r < 0.97: return 'X1 #= %s' % expr(st, 2)
    return '%s = %s' % (var(st), random.choice([var(st), num()]))

def focused(st):
    # eine globale Bedingung mit passenden Domänen, damit es auch Lösungen
    # gibt (sonst scheitern fast alle Fälle mit globalen Bedingungen)
    vs = st['vs']; n = len(vs); L = '[%s]' % ','.join(vs)
    k = random.choice(['circuit', 'cumulative', 'disjoint2', 'automaton', 'nvalue', 'serialized', 'element', 'gcc'])
    if k == 'circuit':
        return ['%s ins 1 .. %d' % (L, n), 'circuit(%s)' % L]
    if k == 'cumulative':
        ts = ['task(%s,%d,_,%d,%d)' % (v, random.randint(1, 3), random.randint(1, 2), j) for j, v in enumerate(vs)]
        return ['%s ins 0 .. %d' % (L, random.randint(2, 5)), 'cumulative([%s], [limit(%d)])' % (','.join(ts), random.randint(1, 3))]
    if k == 'disjoint2':
        h = n // 2 or 1
        xs, ys = vs[:h], vs[h:] or vs[:h]
        rs = ['r(%s,%d,%s,%d)' % (x, random.randint(1, 2), y, random.randint(1, 2)) for x, y in zip(xs, ys)]
        return ['%s ins 0 .. %d' % (L, random.randint(1, 3)), 'disjoint2([%s])' % ','.join(rs)]
    if k == 'automaton':
        arcs = set('arc(%s,%d,%s)' % (random.choice('ab'), random.randint(0, 2), random.choice('ab')) for _ in range(random.randint(2, 6)))
        return ['%s ins 0 .. 2' % L, 'automaton(%s, [source(a),sink(%s)], [%s])' % (L, random.choice('ab'), ','.join(sorted(arcs)))]
    if k == 'nvalue':
        return ['%s ins 0 .. %d' % (L, random.randint(1, 3)), 'nvalue(%s, %s)' % (random.choice(['B', str(random.randint(1, 3))]), L)]
    if k == 'serialized':
        return ['%s ins 0 .. %d' % (L, random.randint(2, 6)), 'serialized(%s, [%s])' % (L, ','.join(str(random.randint(1, 2)) for _ in vs))]
    if k == 'element':
        return ['%s ins 0 .. 3' % L, 'element(%s, %s, %s)' % (var(st), L, var(st))]
    return ['%s ins 0 .. 2' % L, 'global_cardinality(%s, [0-%s,1-_,2-_])' % (L, random.choice(['_', '1', 'B']))]

def case(i):
    n = random.randint(1, 4)
    vs = ['X%d' % k for k in range(1, n + 1)]
    st = {'vs': vs, 'b': 'B'}
    if random.random() < 0.3:
        goals = focused(st) + ['B in 0 .. 1']
        if random.random() < 0.5: goals.insert(random.randint(0, len(goals)), constraint(st))
        finish(i, vs, st, goals)
        return
    goals = []
    if random.random() < 0.85:
        goals.append('%s ins %s' % ('[%s]' % ','.join(vs), dom()))
    else:
        for v in vs: goals.append('%s in %s' % (v, dom()))
    goals.append('B in 0 .. 1')
    for _ in range(random.randint(1, 4)):
        c = constraint(st)
        goals.insert(random.randint(1 if random.random() < 0.8 else 0, len(goals)), c)
    finish(i, vs, st, goals)

def finish(i, vs, st, goals):
    sel = random.choice(['leftmost', 'ff', 'ffc', 'min', 'max'])
    opts = [sel]
    if random.random() < 0.4: opts.append(random.choice(['up', 'down']))
    if random.random() < 0.2: opts.append(random.choice(['step', 'enum', 'bisect']))
    # Optimierung: Lösungen nach einem Ausdruck geordnet
    if random.random() < 0.15:
        opts.append('%s(%s)' % (random.choice(['min', 'max']), random.choice([lin(st), expr(st, 1)])))
    PS.append('p(%d, [%s]) :- %s.' % (i, ','.join(vs + ['B']), ', '.join(goals)))
    GS.append('g(%d, [%s], (%s)).' % (i, ','.join(vs + ['B']), ', '.join(goals)))
    OS.append('o(%d, [%s], [%s]).' % (i, ','.join(vs + ['B']), ','.join(opts)))

PS = []; GS = []; OS = []
seed = int(sys.argv[1]); n = int(sys.argv[2])
random.seed(seed)
for i in range(n): case(seed * 100000 + i)
print('\n'.join(PS)); print('\n'.join(GS)); print('\n'.join(OS))
