# gen.py Seed Anzahl – zufällige Ganzzahl-Ausdrücke (klein, um 2^31..2^128, bis
# 10^60) für is/2 nach cases.pl, die Ergebnisse nach Python (ISO: // und rem
# runden zur 0, div und mod nach unten; Division durch 0: err) nach
# expect.txt
import random, sys, math
random.seed(int(sys.argv[1])); n = int(sys.argv[2])
def num():
    k = random.random()
    if k < 0.3: return random.randint(-20, 20)
    if k < 0.6:
        b = random.choice([31, 32, 59, 60, 61, 62, 63, 64, 65, 127, 128])
        return random.choice([-1, 1]) * (2**b + random.randint(-3, 3))
    return random.randint(-10**random.randint(1, 60), 10**random.randint(1, 60))
def trunc_div(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q
ops = {
 '+': lambda a, b: a + b, '-': lambda a, b: a - b, '*': lambda a, b: a * b,
 '//': lambda a, b: trunc_div(a, b) if b else 'err',
 'div': lambda a, b: a // b if b else 'err',
 'mod': lambda a, b: a % b if b else 'err',
 'rem': lambda a, b: a - b * trunc_div(a, b) if b else 'err',
 '>>': lambda a, b: a >> b if 0 <= b < 10000 else None,
 '<<': lambda a, b: a << b if 0 <= b < 10000 else None,
 '/\\': lambda a, b: a & b, '\\/': lambda a, b: a | b, 'xor': lambda a, b: a ^ b,
 'min': lambda a, b: min(a, b), 'max': lambda a, b: max(a, b),
 'gcd': lambda a, b: math.gcd(a, b),
 '^': lambda a, b: a ** b if b >= 0 and b < 300 else (None),
}
un = {'abs': abs, 'sign': lambda a: (a > 0) - (a < 0), '-': lambda a: -a, '\\': lambda a: ~a,
      'msb': lambda a: a.bit_length() - 1 if a > 0 else None}
with open('cases.pl', 'w') as f, open('expect.txt', 'w') as e:
    i = 0
    while i < n:
        if random.random() < 0.8:
            op = random.choice(list(ops)); a = num(); b = num()
            if op in ('>>', '<<'): b = random.randint(0, 200)
            if op == '^': b = random.randint(0, 40)
            r = ops[op](a, b)
            if r is None: continue
            f.write("c(%d, (%d) %s (%d)).\n" % (i, a, op if op not in ('div','mod','rem','xor','min','max','gcd') else op, b) if op not in ('min','max','gcd') else "c(%d, %s(%d, %d)).\n" % (i, op, a, b))
        else:
            op = random.choice(list(un)); a = num()
            r = un[op](a)
            if r is None: continue
            f.write("c(%d, %s(%d)).\n" % (i, op, a))
        e.write("%d %s\n" % (i, r)); i += 1
