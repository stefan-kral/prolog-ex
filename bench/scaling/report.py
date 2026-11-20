#!/usr/bin/env python3
"""report.py – wertet die Ausgabe von run.sh aus.

Je Fall und System der Exponent k in Zeit ~ N^k, geschätzt aus den
Messpunkten ab MIN_MS (Ausgleichsgerade in doppelt-logarithmischer
Darstellung): 1 linear, etwas darüber N log N, 2 quadratisch. Markiert
wird ein Fall, dessen k in PrologEx über 1,3 liegt und um mehr als 0,25
über dem von SWI (oder SWI fehlt): dort wächst PrologEx schneller als die
Aufgabe es verlangt.

Aufruf: python3 report.py < ausgabe.txt
"""
import math
import sys
from collections import defaultdict

MIN_MS = 20

points = defaultdict(list)  # (system, fall) -> [(n, ms)]
order = []
for line in sys.stdin:
    parts = line.split()
    if len(parts) != 4:
        continue
    system, case, n, ms = parts
    try:
        n, ms = int(n), float(ms)
    except ValueError:
        continue
    if case not in order:
        order.append(case)
    points[(system, case)].append((n, ms))


def exponent(pts):
    """Steigung der Ausgleichsgeraden durch (log n, log ms), ms >= MIN_MS."""
    use = [(math.log(n), math.log(ms)) for n, ms in pts if ms >= MIN_MS]
    if len(use) < 2:
        return None
    mx = sum(x for x, _ in use) / len(use)
    my = sum(y for _, y in use) / len(use)
    sxx = sum((x - mx) ** 2 for x, _ in use)
    sxy = sum((x - mx) * (y - my) for x, y in use)
    return sxy / sxx if sxx else None


def last(pts):
    n, ms = pts[-1]
    return f"{ms:.0f} ms bei {n:,}".replace(",", " ")


def fmt(k):
    return "  –  " if k is None else f"{k:5.2f}"


rows = []
for case in order:
    kp = exponent(points[("prologex", case)])
    ks = exponent(points[("swi", case)])
    flag = kp is not None and kp > 1.3 and (ks is None or kp - ks > 0.25)
    rows.append((case, kp, ks, flag))

print(f"{'Fall':18} {'k PrologEx':>10} {'k SWI':>6}  {'PrologEx zuletzt':>24}  {'SWI zuletzt':>22}")
for case, kp, ks, flag in sorted(rows, key=lambda r: -(r[1] or 0)):
    pp = points[("prologex", case)]
    ps = points[("swi", case)]
    print(
        f"{case:18} {fmt(kp):>10} {fmt(ks):>6}  {last(pp) if pp else '–':>24}  "
        f"{last(ps) if ps else '–':>22}{'  <<' if flag else ''}"
    )
print(f"\n<<: k in PrologEx über 1,3 und mehr als 0,25 über SWI (Punkte ab {MIN_MS} ms)")
