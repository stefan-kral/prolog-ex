# Datendateien -> "HEX Prolog-Text" (Ziffern unveraendert, nur 1.0e5-Form)
import sys, re
rx = re.compile(r'^(\d*)(?:\.(\d*))?(?:[eE]([-+]?\d+))?$')
for fn in sys.argv[1:]:
    for l in open(fn):
        h, s = l[14:30], l[31:].strip()
        i, f, e = rx.match(s).groups()
        print(h, (i or '0') + '.' + (f or '0') + ('e' + e if e else ''))
