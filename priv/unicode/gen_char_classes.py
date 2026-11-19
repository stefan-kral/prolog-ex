# gen_char_classes.py UnicodeData.txt > char_classes.txt
# Bereiche der Unicode-Klassen aus der allgemeinen Kategorie, für
# char_type/2: alphabetic (L, Nl), lower (Ll), upper (Lu), numeric (N),
# control (Cc); für Leser und Schreiber (Namen und Variablen): var_start
# (Lu, Lt), letter (L), symbol (Sm, So), ident (L, N, M); für writeq:
# invisible (Cc, Cf, Zs außer dem Leerzeichen, Zl, Zp, Cs, nicht
# vergeben – als \x..\ geschrieben). Je Zeile
# "Klasse von bis" (hexadezimal, einschließlich).
import sys
src = sys.argv[1]
gc = {}
lines = open(src).read().splitlines()
version = None
i = 0
while i < len(lines):
    f = lines[i].split(';')
    cp = int(f[0], 16)
    if f[1].endswith('First>'):
        last = int(lines[i + 1].split(';')[0], 16)
        for c in range(cp, last + 1): gc[c] = f[2]
        i += 2; continue
    gc[cp] = f[2]
    i += 1
classes = [
    ('alphabetic', lambda g: g[0] == 'L' or g == 'Nl'),
    ('lower', lambda g: g == 'Ll'),
    ('upper', lambda g: g == 'Lu'),
    ('numeric', lambda g: g[0] == 'N'),
    ('control', lambda g: g == 'Cc'),
    ('var_start', lambda g: g in ('Lu', 'Lt')),
    ('letter', lambda g: g[0] == 'L'),
    ('symbol', lambda g: g in ('Sm', 'So')),
    ('ident', lambda g: g[0] in 'LNM'),
    ('invisible', None),
]
print('# Unicode 17.0.0 (UnicodeData.txt), (c) Unicode, Inc., Unicode License v3')
print('# (https://www.unicode.org/license.txt). Klassen für char_type/2, Leser und')
print('# Schreiber als Bereiche; erzeugt von gen_char_classes.py')
for name, p in classes:
    start = None
    for c in range(0x110001):
        if p is None:  # invisible: auch nicht vergebene Codepunkte
            hit = c <= 0x10FFFF and c != 0x20 and gc.get(c, 'Cn') in ('Cc', 'Cf', 'Zs', 'Zl', 'Zp', 'Cs', 'Cn')
        else:
            hit = c <= 0x10FFFF and c in gc and p(gc[c])
        if hit and start is None: start = c
        if not hit and start is not None:
            print('%s %X %X' % (name, start, c - 1)); start = None
