# csvspec.py VERZ : csv-spectrum (max-mapper, BSD-2-Clause) als Prolog-
# Fakten spectrum(Name, Zeilen): Kopfzeile und Datenzeilen als Listen von
# Atomen, aus den erwarteten JSON-Dateien (location_coordinates fehlt: Das
# JSON passt nicht zur CSV-Datei)
import sys, os, json
d = sys.argv[1]
def q(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r') + "'"
print('% csv-spectrum (github.com/max-mapper/csv-spectrum, BSD-2-Clause):')
print('% erwartete Zeilen je Datei, aus deren JSON. Erzeugt von')
print('% conformance/small/csvspec.py')
for f in sorted(os.listdir(os.path.join(d, 'csvs'))):
    name = f[:-4]
    if name == 'location_coordinates':
        continue
    rows = json.load(open(os.path.join(d, 'json', name + '.json'), encoding='utf-8'))
    head = open(os.path.join(d, 'csvs', f), encoding='utf-8').read().split('\n')[0].rstrip('\r').split(',')
    out = [head] + [[r[k] for k in head] for r in rows]
    print('spectrum(%s, [%s]).' % (q(name), ', '.join('[' + ', '.join(map(q, r)) + ']' for r in out)))
