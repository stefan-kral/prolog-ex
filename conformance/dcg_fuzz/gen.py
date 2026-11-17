#!/usr/bin/env python3
# gen.py Seed Anzahl – zufällige DCGs für den Vergleich PrologEx – Scryer –
# SWI. Je Fall 1–4 Nichtterminale gS_n0..gS_n3 (je ein Argument) mit 1–3
# Regeln. Rümpfe aus Terminal-Listen (auch mit Variablen), Strings, {}//1,
# !, \+, ( ; ), ( -> ; ), ( -> ), call//N und Aufrufen; Köpfe mit
# Pushback (g, [..] --> ..). Garantiert endlich: ein Aufruf von n_j mit
# j =< i (in einer Regel von n_i) nur, nachdem in derselben Folge schon
# ein nicht leeres Terminal verbraucht wurde; Pushback nur in Regeln ohne
# Aufrufe, die mindestens so viele Terminale lesen, wie sie zurücklegen.
import random, sys

TOK = ['a', 'b']
# \+//1 und (->)//2 ohne Else sind im Entwurf für DCGs (WG17, 2022)
# implementierungsabhängig (7.14.11, 7.14.12); Scryer lehnt sie ab. Fälle
# damit vergleicht cmp.py nur mit SWI.
NONSTD = [False]

class Rule:
    def __init__(self, case, i, k):
        self.case, self.i, self.k = case, i, k
        self.vars = random.sample(['A', 'B', 'C', 'D', 'E'], random.randint(1, 3))

    def v(self):
        return random.choice(self.vars)

    def tok(self):
        return random.choice(TOK + [self.v()]) if random.random() < 0.7 else self.v()

    def term(self, nonempty=False):
        n = random.randint(1 if nonempty else 0, 2)
        if random.random() < 0.15 and n > 0:
            # String-Terminal (double_quotes = chars)
            return '"%s"' % ''.join(random.choice(TOK) for _ in range(n))
        return '[%s]' % ', '.join(self.tok() for _ in range(n))

    def arg(self):
        r = random.random()
        if r < 0.45: return self.v()
        if r < 0.6: return random.choice(['x', 'y'])
        if r < 0.75: return 'f(%s, %s)' % (self.v(), self.v())
        if r < 0.85: return '[%s|%s]' % (self.v(), self.v())
        return '[]'

    def call(self, guarded):
        cands = [j for j in range(self.k) if j > self.i or guarded]
        if not cands: return None
        j = random.choice(cands)
        nt = 'g%d_n%d' % (self.case, j)
        r = random.random()
        if r < 0.12:
            return 'call(%s, %s)' % (nt, self.arg())
        if r < 0.2:
            return 'phrase(%s(%s))' % (nt, self.arg())
        if r < 0.27:
            # call//1 mit fertigem Ziel
            return 'call(%s(%s))' % (nt, self.arg())
        if r < 0.32:
            # Variable als Rumpf, zur Laufzeit gebunden (call//1)
            g = self.v()
            return '{%s = %s(%s)}, %s' % (g, nt, self.arg(), g)
        return '%s(%s)' % (nt, self.arg())

    def goal(self):
        return random.choice(['{%s = %s}' % (self.v(), random.choice(TOK + ['x'])),
                              '{true}', '{%s \\== %s}' % (self.v(), random.choice(TOK)),
                              '{fail}' if random.random() < 0.2 else '{true}',
                              # Cut in {}: nur dort
                              '{!}', '{( %s = a, ! ; true )}' % self.v()])

    def item(self, guarded, depth):
        r = random.random()
        if r < 0.35: return self.term(), False
        if r < 0.55:
            c = self.call(guarded)
            if c: return c, False
            return self.term(), False
        if r < 0.63: return self.goal(), False
        if r < 0.68: return '!', False
        if depth > 0:
            if r < 0.71:
                NONSTD[0] = True
                return '\\+ %s' % self.simple(guarded, depth - 1), False
            if r < 0.85:
                op = '|' if random.random() < 0.25 else ';'
                return '( %s %s %s )' % (self.seq(guarded, depth - 1), op, self.seq(guarded, depth - 1)), False
            if r < 0.97:
                return '( %s -> %s ; %s )' % (self.seq(guarded, depth - 1), self.seq(guarded, depth - 1),
                                              self.seq(guarded, depth - 1)), False
            NONSTD[0] = True
            return '( %s -> %s )' % (self.seq(guarded, depth - 1), self.seq(guarded, depth - 1)), False
        return self.term(), False

    def simple(self, guarded, depth):
        x, _ = self.item(guarded, depth)
        return x if x[0] in '[{"!(' or not x.startswith('\\+') else '( %s )' % x

    def seq(self, guarded, depth):
        items = []
        for _ in range(random.randint(1, 3)):
            if random.random() < 0.3:
                # ein verbrauchendes Terminal macht spätere Aufrufe sicher
                items.append(self.term(nonempty=True)); guarded = True
            else:
                x, _ = self.item(guarded, depth); items.append(x)
        return ', '.join(items)

    def text(self):
        head = 'g%d_n%d(%s)' % (self.case, self.i, self.arg())
        if random.random() < 0.12:
            # Pushback: liest mindestens so viel, wie es zurücklegt
            p = random.randint(1, 2); t = random.randint(p, 3)
            pb = '[%s]' % ', '.join(self.tok() for _ in range(p))
            body = '[%s]' % ', '.join(self.tok() for _ in range(t))
            if random.random() < 0.4: body += ', ' + self.goal()
            return '%s, %s --> %s.' % (head, pb, body)
        return '%s --> %s.' % (head, self.seq(False, 2))

def main():
    seed, n = int(sys.argv[1]), int(sys.argv[2])
    random.seed(seed)
    for c in range(n):
        k = random.randint(1, 4)
        NONSTD[0] = False
        for i in range(k):
            for _ in range(random.randint(1, 3)):
                print(Rule(c, i, k).text())
        if NONSTD[0]: print('%% nonstd %d' % c)
        print('case(%d).' % c)
        print('c(%d, A, I, R) :- phrase(g%d_n0(A), I, R).' % (c, c))
        print('g(%d, A, I) :- phrase(g%d_n0(A), I).' % (c, c))

main()
