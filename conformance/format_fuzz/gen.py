# gen.py Seed Anzahl Ausgabeverzeichnis – zufällige Fälle für format/2:
#   floats.pl: c(X, N, C) mit C in e/f/g, dazu floats.expect – Pythons
#     "%.Ne" usw. (exakter Wert des Floats, korrekt gerundet wie printf)
#   ints.pl:   c(X, N, C) mit Ganzzahlen und d/D/r/R/e/f/g/w (Vergleich
#     mit SWI-Prolog)
import math, os, random, struct, sys

seed, n, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
random.seed(seed)


def rnd():
    k = random.random()
    if k < 0.4:  # beliebige Bits
        while True:
            x = struct.unpack('<d', struct.pack('<Q', random.getrandbits(64)))[0]
            if math.isfinite(x):
                return x
    if k < 0.6:  # kurze Dezimalzahlen
        return round(random.uniform(-1000, 1000), random.randint(0, 6))
    if k < 0.8:  # Halbwerte
        return random.randint(-10**6, 10**6) / 2**random.randint(1, 12)
    return random.choice([0.0, -0.0, 5e-324, 2.2250738585072014e-308, 1.7976931348623157e308,
                          0.5, 1.5, 2.5, 9.5, 99.5, 0.05, 0.15, 1e15, 1e16, 1e21, 1e22])


def iso(x):  # ISO verlangt Nachkommastellen vor dem Exponenten
    r = repr(x)
    if 'e' in r and '.' not in r.split('e')[0]:
        m, e = r.split('e')
        r = m + '.0e' + e
    return r


with open(os.path.join(out, 'floats.pl'), 'w') as f, \
        open(os.path.join(out, 'floats.expect'), 'w') as e:
    for _ in range(n):
        x, p, c = rnd(), random.randint(0, 25), random.choice('efg')
        f.write("c(%s, %d, '%s').\n" % (iso(x), p, c))
        e.write(("%%.%d%s" % (p, c)) % x + "\n")

with open(os.path.join(out, 'ints.pl'), 'w') as f:
    for _ in range(n // 4):
        if random.random() < 0.8:
            x = random.randint(-10**random.randint(1, 40), 10**random.randint(1, 40))
        else:
            x = random.choice([0, -1, 1, 5, -5, 10, -10, 999, -1000])
        c = random.choice('dDrRefgw')
        p = random.randint(2, 36) if c in 'rR' else random.randint(0, 12)
        f.write("c(%d, %d, '%s').\n" % (x, p, c))
