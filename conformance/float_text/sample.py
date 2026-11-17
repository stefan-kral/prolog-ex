# sample.py DATA... : Stichprobe für test/fixtures/float_text/sample.txt
# je Datei jede k-te Zeile (rund 400), dazu more-test-cases.txt ganz und
# alle subnormalen Werte; Spalten: f64-Bits Text Ziffern Exponent (die
# kuerzeste Darstellung nach Python: Wert = 0.Ziffern * 10^Exponent)
import sys, struct, os
def short(h):
    x = struct.unpack('>d', bytes.fromhex(h))[0]
    if x in (float('inf'),): return None
    if x == 0: return ('0', 0)
    r = repr(x); m, _, e = r.partition('e'); e = int(e) if e else 0
    i, _, f = m.partition('.'); a = i + f; ds = a.lstrip('0'); lead = len(a) - len(ds)
    return (ds.rstrip('0'), len(i) + e - lead)
out = {}
for fn in sys.argv[1:]:
    ls = open(fn).read().splitlines()
    base = os.path.basename(fn)
    k = 1 if base == 'more-test-cases.txt' else max(1, len(ls) // 400)
    for j, l in enumerate(ls):
        h, s = l[14:30], l[31:]
        sub = h[:3] == '000' and h != '0000000000000000'
        if j % k == 0 or sub:
            if len(s) > 120: continue
            out.setdefault((h, s), None)
for (h, s) in out:
    sh = short(h)
    print(h, s, *(sh if sh else ('inf', 0)))
