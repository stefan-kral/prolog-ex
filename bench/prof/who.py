#!/usr/bin/env python3
# who.py perf.data Muster [n] – für Stichproben, deren nächste BEAM-Funktion auf
# Muster passt: erste PrologEx-Funktion darüber
import sys, os, glob, shutil, subprocess, re, collections
def perf():
    # wie perf.sh: das erste perf, das läuft (Ubuntus Wrapper scheitert
    # bei fremdem Kernel)
    if os.environ.get('PERF'): return os.environ['PERF']
    for p in [shutil.which('perf')] + sorted(glob.glob('/usr/lib/linux-tools*/perf')):
        if p and subprocess.run([p, '--version'], capture_output=True).returncode == 0: return p
    sys.exit('perf nicht gefunden (PERF=…)')
P = perf()
out = subprocess.run([P, 'script', '-i', sys.argv[1], '-F', 'ip,sym'], capture_output=True, text=True).stdout
pat = re.compile(sys.argv[2])
c = collections.Counter(); n = 0
for blk in out.split('\n\n'):
    st = [l.strip().split(None, 1)[1] if len(l.strip().split(None, 1)) > 1 else '?' for l in blk.strip().split('\n') if l.strip()]
    if not st: continue
    n += 1
    b = next((i for i, f in enumerate(st) if f.startswith('$') and ':' in f and not f.startswith('$global')), None)
    if b is None or not pat.search(st[b]): continue
    caller = next((f for f in st[b+1:] if f.startswith("$'Elixir.PrologEx") and '-fun-' not in f), '?')
    c[(st[b], caller)] += 1
for (f, cl), k in c.most_common(int(sys.argv[3]) if len(sys.argv) > 3 else 15):
    print('%5.1f %%  %-45s <- %s' % (100.0 * k / n, f[:45], cl))
