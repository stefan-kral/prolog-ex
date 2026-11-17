# kuhn.py UTF-8-test.txt : je Zeile line(Nr, Bytes, Streng, Ersetzt):
# Streng: Codes nach Pythons strenger UTF-8-Dekodierung oder invalid;
# Ersetzt: mit U+FFFD je größtem ungültigem Teilstück (errors='replace',
# die Empfehlung des Unicode-Standards, Kap. 3.9)
import sys
data = open(sys.argv[1], 'rb').read()
print('% Markus Kuhn, UTF-8 decoder capability and stress test (2015-08-24,')
print('% CC BY 4.0): je Zeile die Bytes, die Codes nach Pythons strenger')
print('% UTF-8-Dekodierung (invalid: ungültig) und mit U+FFFD für jedes größte')
print('% ungültige Teilstück. Erzeugt von conformance/small/kuhn.py')
codes = lambda s: '[' + ','.join(str(ord(c)) for c in s) + ']'
for i, l in enumerate(data.split(b'\n'), 1):
    try:
        strict = codes(l.decode('utf-8'))
    except UnicodeDecodeError:
        strict = 'invalid'
    print('line(%d, [%s], %s, %s).' % (i, ','.join(map(str, l)), strict, codes(l.decode('utf-8', 'replace'))))
