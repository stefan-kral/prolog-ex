# Python als Orakel: kuerzeste Ziffernfolge je f64 (repr), normiert:
# Wert = 0.DIGITS * 10^EXP. Eingabe: Datendateien, Ausgabe: HEX DIGITS EXP
import sys, struct
seen = set()
for fn in sys.argv[1:]:
    for l in open(fn):
        h = l[14:30]
        if h in seen: continue
        seen.add(h)
        x = struct.unpack('>d', bytes.fromhex(h))[0]
        if x != x or x in (float('inf'), float('-inf')): continue
        if x == 0: print(h, '0', 0); continue
        r = repr(abs(x))
        m, _, e = r.partition('e')
        e = int(e) if e else 0
        i, _, f = m.partition('.')
        ds = (i + f).lstrip('0')
        lead = len(i + f) - len((i + f).lstrip('0'))
        exp = len(i) + e - lead
        print(h, ds.rstrip('0'), exp)
