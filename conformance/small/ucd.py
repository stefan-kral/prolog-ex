# ucd.py UCD-VERZ : je Codepunkt (ohne Surrogate) "cp gc ws upper lower"
# aus UnicodeData.txt (Kategorie, einfache Abbildung), PropList.txt
# (White_Space) und SpecialCasing.txt (unbedingte volle Abbildungen);
# upper/lower als Codepunkte mit "." getrennt
import sys, os
d = sys.argv[1]
gc, up, lo = {}, {}, {}
lines = open(os.path.join(d, 'UnicodeData.txt')).read().splitlines()
i = 0
while i < len(lines):
    f = lines[i].split(';')
    cp = int(f[0], 16)
    if f[1].endswith('First>'):
        last = int(lines[i + 1].split(';')[0], 16)
        for c in range(cp, last + 1): gc[c] = f[2]
        i += 2; continue
    gc[cp] = f[2]
    if f[12]: up[cp] = [int(f[12], 16)]
    if f[13]: lo[cp] = [int(f[13], 16)]
    i += 1
for l in open(os.path.join(d, 'SpecialCasing.txt')):
    l = l.split('#')[0].strip()
    if not l: continue
    f = [x.strip() for x in l.split(';')]
    if len(f) > 5 and f[4]: continue          # bedingt (Sprache, Kontext)
    cp = int(f[0], 16)
    lo[cp] = [int(x, 16) for x in f[1].split()]
    up[cp] = [int(x, 16) for x in f[3].split()]
ws = set()
for l in open(os.path.join(d, 'PropList.txt')):
    l = l.split('#')[0].strip()
    if not l: continue
    r, p = [x.strip() for x in l.split(';')]
    if p != 'White_Space': continue
    a, _, b = r.partition('..')
    for c in range(int(a, 16), int(b or a, 16) + 1): ws.add(c)
for cp in range(0x110000):
    if 0xD800 <= cp <= 0xDFFF: continue
    g = gc.get(cp, 'Cn')
    u = '.'.join(map(str, up.get(cp, [cp])))
    lw = '.'.join(map(str, lo.get(cp, [cp])))
    print(cp, g, 1 if cp in ws else 0, u, lw)
