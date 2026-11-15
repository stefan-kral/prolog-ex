#!/usr/bin/env python3
# stacks.py perf.data [top] – aus `perf script`: Zeit je BEAM-Funktion
# (eigene Zeit samt nativer Arbeit darunter: BIFs, GC, Map-Zugriffe),
# Enum & Co/Closures nach erstem PrologEx-Aufrufer
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
top = int(sys.argv[2]) if len(sys.argv) > 2 else 30
samples = []
cur = []
for line in out.split('\n'):
    if not line.strip():
        if cur: samples.append(cur)
        cur = []
        continue
    parts = line.strip().split(None, 1)
    cur.append(parts[1] if len(parts) > 1 else '?')
if cur: samples.append(cur)
LIB = re.compile(r"^\$'?(Elixir\.(Enum|List|Stream|Keyword|MapSet|Enumerable[.A-Za-z]*|Range)|lists)'?:")
MAP = re.compile(r"^\$'?(Elixir\.Map|maps|queue)'?:")
def beam(f): return f.startswith('$') and ':' in f and not f.startswith('$global')
def mine(f): return f.startswith("$'Elixir.PrologEx")
def fun(f): return '-fun-' in f
idle = 0
own = collections.Counter(); attr = collections.Counter(); libc = collections.Counter(); kinds = collections.Counter()
n = 0
for st in samples:
    if any('scheduler_wait' in f or 'erts_schedule' == f for f in st[:3]):
        idle += 1; continue
    n += 1
    own[st[0]] += 1
    b = next((f for f in st if beam(f)), None)
    attr[b or '(nativ: ' + st[0] + ')'] += 1
    if b and (LIB.match(b) or fun(b)):
        kind = 'Closure' if fun(b) and not LIB.match(b) else 'Enum&Co'
        caller = b if kind == 'Closure' else next((f for f in st[st.index(b):] if mine(f) and not fun(f)), '?')
        libc[(caller, kind)] += 1; kinds[kind] += 1
    elif b and MAP.match(b):
        kinds['Map'] += 1
pct = lambda k: 100.0 * k / max(n, 1)
print('%d Stichproben (ohne Leerlauf %d): Enum&Co %.1f %%, Closures %.1f %%, Map/:maps/:queue %.1f %%' % (n, idle, pct(kinds['Enum&Co']), pct(kinds['Closure']), pct(kinds['Map'])))
print('  BEAM-Funktion samt nativer Arbeit darunter:')
for f, k in attr.most_common(top): print('    %5.1f %%  %s' % (pct(k), f))
print('  eigene Zeit (Blatt):')
for f, k in own.most_common(12): print('    %5.1f %%  %s' % (pct(k), f))
print('  Enum & Co/Closures nach Aufrufer:')
for (c, kd), k in libc.most_common(12): print('    %5.1f %%  %s (%s)' % (pct(k), c, kd))
