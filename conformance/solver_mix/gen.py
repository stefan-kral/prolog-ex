#!/usr/bin/env python3
# gen.py Seed Anzahl – zufällige Fälle mit mehreren Solvern an denselben
# Variablen: clpz, clpb, dif, freeze, when und zwei eigene Attributmodule
# (dom: endliche Bereiche, par: Parität), dazu Unifikationen, die mehrere
# attributierte Variablen auf einmal binden. Variablen vom Typ b (0..1) und
# i (0..3); clpb nur an b-Variablen, Unifikationen nur innerhalb eines
# Typs.
import random, sys

def lit(t):
    return str(random.randint(0, 1 if t == 'b' else 3))

class Case:
    def __init__(self):
        n = random.randint(2, 5)
        self.vs = ['V%d' % i for i in range(n)]
        self.ts = [random.choice('bi') for _ in self.vs]
        # wenigstens zwei Solver je Fall
        self.solvers = random.sample(['clpz', 'clpb', 'dif', 'freeze', 'when', 'dom', 'par'],
                                     random.randint(2, 3))
        if 'clpb' in self.solvers and 'b' not in self.ts:
            self.ts[0] = 'b'

    def v(self, t=None):
        c = [v for v, tt in zip(self.vs, self.ts) if t is None or tt == t]
        return random.choice(c) if c else None

    def typ(self, v):
        return self.ts[self.vs.index(v)]

    def same_type_pair(self):
        v = self.v(); t = self.typ(v)
        w = self.v(t)
        return v, w, t

    # --- Bedingungen der einzelnen Solver --------------------------------
    def clpz(self):
        v, w, t = self.same_type_pair()
        r = random.random()
        if r < 0.25:
            lo = random.randint(0, 2); return '%s in %d..%d' % (v, lo, lo + random.randint(0, 2))
        if r < 0.45: return '%s #= %s + %d' % (v, w, random.randint(-1, 2))
        if r < 0.6: return '%s #\\= %s' % (v, w)
        if r < 0.75: return '%s #< %s' % (v, w)
        if r < 0.85: return '%s + %s #= %s' % (v, w, lit('i'))
        b = self.v('b')
        if b: return '%s #<==> (%s #= %s)' % (b, v, w)
        return '%s #>= %s' % (v, w)

    def clpb(self):
        bs = [v for v, t in zip(self.vs, self.ts) if t == 'b']
        a = random.choice(bs); b = random.choice(bs); c = random.choice(bs)
        return random.choice([
            'sat(%s =:= %s)' % (a, b), 'sat(%s + %s)' % (a, b), 'sat(%s * %s =:= %s)' % (a, b, c),
            'sat(~%s)' % a, 'sat(%s # %s)' % (a, b), 'sat(%s =< %s)' % (a, b),
            'sat(card([1], [%s, %s, %s]))' % (a, b, c)])

    def dif(self):
        v, w, t = self.same_type_pair()
        r = random.random()
        if r < 0.4: return 'dif(%s, %s)' % (v, w)
        if r < 0.7: return 'dif(%s, %s)' % (v, lit(t))
        x, y, t2 = self.same_type_pair()
        return 'dif(f(%s, %s), f(%s, %s))' % (v, x, w, y)

    def goal(self, depth=1):
        # was ein freeze/when-Ziel tut (an anderen Variablen)
        v, w, t = self.same_type_pair()
        r = random.random()
        if r < 0.2: return '%s = %s' % (v, w)
        if r < 0.35: return '%s = %s' % (v, lit(t))
        if r < 0.5: return 'dif(%s, %s)' % (v, w)
        if r < 0.6: return '%s \\== %s' % (v, lit(t))
        if r < 0.7: return 'member(%s, [%s, %s])' % (v, lit(t), lit(t))
        if r < 0.8 and 'clpz' in self.solvers: return '%s #>= %s' % (v, w)
        if r < 0.9 and 'clpb' in self.solvers and t == 'b': return 'sat(%s =< %s)' % (v, w)
        if depth > 0: return 'freeze(%s, (%s))' % (w, self.goal(depth - 1))
        return 'true'

    def freeze(self):
        return 'freeze(%s, (%s))' % (self.v(), self.goal())

    def when(self):
        v, w, t = self.same_type_pair()
        # ?=(V, V): Scryer meldet domain_error(when_condition) (SWI und
        # PrologEx rufen das Ziel gleich) – nur mit zwei Variablen
        eq = '?=(%s, %s)' % (v, w) if v != w else 'nonvar(%s)' % v
        c = random.choice(['nonvar(%s)' % v, 'ground(f(%s, %s))' % (v, w), eq,
                           '(nonvar(%s) ; nonvar(%s))' % (v, w), '(nonvar(%s), nonvar(%s))' % (v, w)])
        return 'when(%s, (%s))' % (c, self.goal())

    def dom(self):
        v = self.v(); t = self.typ(v)
        k = random.randint(1, 3)
        return 'domain(%s, [%s])' % (v, ', '.join(lit(t) for _ in range(k)))

    def par(self):
        v = self.v('i') or self.v()
        return 'parity(%s, %d)' % (v, random.randint(0, 1))

    # --- Unifikationen und Proben -----------------------------------------
    def unify(self):
        r = random.random()
        if r < 0.35:
            v, w, t = self.same_type_pair(); return '%s = %s' % (v, w)
        if r < 0.55:
            v = self.v(); return '%s = %s' % (v, lit(self.typ(v)))
        if r < 0.8:
            # mehrere Bindungen in einer Unifikation
            a, b, t1 = self.same_type_pair(); c, d, t2 = self.same_type_pair()
            return 'f(%s, %s) = f(%s, %s)' % (a, c, b, d)
        if r < 0.9:
            a = self.v(); b = self.v()
            return '[%s, %s] = [%s, %s]' % (a, b, lit(self.typ(a)), lit(self.typ(b)))
        v = self.v(); t = self.typ(v)
        return random.choice(['%s \\= %s' % (v, lit(t)), '\\+ %s = %s' % (v, lit(t)),
                              'memberchk(%s, [%s, %s])' % (v, lit(t), lit(t))])

    def build(self):
        acts = []
        for s in self.solvers:
            for _ in range(random.randint(1, 3)):
                acts.append(getattr(self, s)())
        for _ in range(random.randint(1, 3)):
            acts.append(self.unify())
        random.shuffle(acts)
        return acts

def main():
    seed, n = int(sys.argv[1]), int(sys.argv[2])
    random.seed(seed)
    for i in range(n):
        c = Case()
        acts = c.build()
        print('c(%d, [%s], [%s], (%s)).' % (i, ', '.join(c.vs), ', '.join(c.ts),
                                            ',\n    '.join(acts + ['vars([%s])' % ', '.join(c.vs)])))

main()
