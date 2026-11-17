# fixture.py ZIEL ZAEHLUNGEN|- DIMACS... : Prolog-Fakten (Tests, run.sh)
#   cnf(Name, Variablen, Klauseln).   expected(Name, sat|unsat, Modelle|none).
# sat/unsat: aim aus dem Namen (yes/no), dubois/hole/pret/uuf unerfüllbar,
# uf erfüllbar; Modelle aus count.py (Durchprobieren), sonst none
import sys, os, re
out, counts, files = sys.argv[1], sys.argv[2], sys.argv[3:]
cnt = dict(l.split() for l in open(counts)) if counts != '-' else {}
def clauses(fn):
    n = None; cls = []; cur = []
    for l in open(fn):
        l = l.strip()
        if l.startswith('%'): break
        if not l or l[0] == 'c': continue
        if l[0] == 'p': n = int(l.split()[2]); continue
        for t in l.split():
            v = int(t)
            if v == 0:
                if cur: cls.append(cur); cur = []
            else: cur.append(v)
    if cur: cls.append(cur)
    return n, cls
def expect(name):
    if name.startswith('aim'): return 'sat' if '-yes' in name else 'unsat'
    if re.match(r'(dubois|hole|pret|uuf)', name): return 'unsat'
    if name.startswith('uf'): return 'sat'
    raise SystemExit('unbekannt: ' + name)
with open(out, 'w') as o:
    o.write('% aus SATLIB (www.cs.ubc.ca/~hoos/SATLIB), erzeugt von\n% conformance/satlib/fixture.py\n')
    o.write(':- discontiguous(cnf/3).\n:- discontiguous(expected/3).\n')
    for fn in files:
        name = os.path.basename(fn)[:-4]
        n, cls = clauses(fn)
        o.write("cnf('%s', %d, %s).\n" % (name, n, str(cls).replace(' ', '')))
        o.write("expected('%s', %s, %s).\n" % (name, expect(name), cnt.get(name, 'none')))
