# cmp_rw.py shortest.txt AUSGABE: vergleicht "HEX Ausgabe" mit der
# kuerzesten Darstellung (Python); unendlich muss ein Fehler sein
import sys, collections
sh = {}
for l in open(sys.argv[1]):
    h, d, e = l.split(); sh[h] = (d, int(e))
def norm(w):
    w = w.lstrip('-')
    m, _, e = w.partition('e'); e = int(e) if e else 0
    i, _, f = m.partition('.')
    a = i + f; ds = a.lstrip('0'); lead = len(a) - len(ds); ds = ds.rstrip('0')
    return ('0', 0) if ds == '' else (ds, len(i) + e - lead)
bad = collections.Counter(); ex = {}
n = 0
for l in open(sys.argv[2]):
    n += 1
    h, _, w = l.rstrip('\n').partition(' ')
    if h == '7FF0000000000000':
        k = None if w.startswith('error') else 'unendlich angenommen: ' + w[:30]
    elif w.startswith('error') or w == 'fail':
        k = 'Fehler: ' + w[:60]
    else:
        try: k = None if norm(w) == sh[h] else 'falsch/nicht kuerzest'
        except Exception: k = 'unlesbar: ' + w[:40]
    if k: bad[k] += 1; ex.setdefault(k, l.strip())
print(n, 'Zeilen,', sum(bad.values()), 'Abweichungen')
for k, c in bad.most_common(20): print('  %7d  %s   z.B. %s' % (c, k, ex[k]))
