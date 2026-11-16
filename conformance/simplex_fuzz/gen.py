#!/usr/bin/env python3
# gen.py Seed N – N zufällige lineare Programme für library(simplex): 2–4
# Variablen, je 0..obere Schranke, 1–4 Bedingungen (=<, >=, selten =),
# manchmal integral/1; maximieren oder minimieren. Ausgabe je Fall
# "Nr Zielwert" oder "Nr fail" (siehe run.sh, cmp.py)
import random, sys
random.seed(int(sys.argv[1])); n = int(sys.argv[2])
out = [":- use_module(library(simplex)).",
       "run(I, G) :- catch((G -> true ; (write(I), write(' fail'), nl)), E, (write(I), write(' err '), write(E), nl)).",
       "val(I, S) :- objective(S, O), write(I), write(' '), write(O), nl."]
goals = []
for i in range(n):
    nv = random.randint(2, 4); vs = [f"x{j}" for j in range(nv)]
    cs = []
    for _ in range(random.randint(1, 4)):
        terms = [f"{random.randint(-5, 6)}*{v}" for v in vs if random.random() < 0.8] or [f"1*{vs[0]}"]
        rel = random.choice(["=<", "=<", ">=", "="] if random.random() < 0.2 else ["=<", ">="])
        cs.append(f"constraint([{', '.join(terms)}] {rel} {random.randint(0, 20)})")
    for v in vs:
        cs.append(f"constraint([{v}] >= 0)"); cs.append(f"constraint([{v}] =< {random.randint(1, 10)})")
        if random.random() < 0.3: cs.append(f"constraint(integral({v}))")
    obj = ", ".join(f"{random.randint(-4, 7)}*{v}" for v in vs)
    opt = random.choice(["maximize", "minimize"])
    body = "gen_state(S0)"
    k = 0
    for c in cs:
        body += f", {c[:-1]}, S{k}, S{k+1})"; k += 1
    body += f", {opt}([{obj}], S{k}, S), val({i}, S)"
    out.append(f"c{i} :- {body}.")
    goals.append(f"run({i}, c{i})")
out.append("go :- " + ", ".join(goals) + ".")
print("\n".join(out))
