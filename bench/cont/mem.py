#!/usr/bin/env python3
"""mem.py – höchster Speicher (max RSS, MB) je System und Benchmark:
dieselben Systeme und Vorspänne wie run.sh. Aufruf: python3 mem.py N
(Vorgabe 1000000). Umgebung: SWIPL, SCRYER, TPL wie run.sh."""
import os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, "..", ".."))
n = sys.argv[1] if len(sys.argv) > 1 else "1000000"
ex = os.path.join(here, "examples.pl")

def cmd(system, goal):
    pre = os.path.join(here, f"prelude_{system}.pl")
    if system == "prologex":
        return ["mix", "run", "--no-compile", "-e",
                "System.halt(PrologEx.Toplevel.main(System.argv()))", "--",
                pre, ex, "-g", goal, "-g", "halt", "-q"]
    if system == "swi":
        return [os.environ.get("SWIPL", "swipl"), "-q", "-g", goal, "-t", "halt", pre, ex]
    if system == "scryer":
        return [os.environ.get("SCRYER", "scryer-prolog"), "-g", goal, "-g", "halt", pre, ex]
    return [os.environ.get("TPL", "tpl"), "-q", "-g", goal, "-g", "halt", pre, ex]

def maxrss(c):
    p = subprocess.Popen(c, cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _, status, ru = os.wait4(p.pid, 0)
    return ru.ru_maxrss / 1024 if status == 0 else None

systems = ["prologex"] + [s for s, v in (("swi", "SWIPL"), ("scryer", "SCRYER"), ("trealla", "TPL"))
                          if os.environ.get(v, "x")]
for s in systems:
    base = maxrss(cmd(s, "true"))
    row = [s, f"leer {base:.0f}"]
    for b in ["sum_loop", "sum_gen", "sum_findall"]:
        m = maxrss(cmd(s, f"bench({b}, {n})"))
        row.append(f"{b} +{m - base:.0f}" if m is not None else f"{b} ?")
    print("  ".join(row), flush=True)
