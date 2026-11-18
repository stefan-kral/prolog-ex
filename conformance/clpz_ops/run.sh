#!/bin/sh
# run.sh [MaxOps] [MaxOrder] – clpz gegen sich selbst und is/2 (nach
# Scryers src/tests/clpz): ops.pl für mod rem // div * + - min max ^ bis
# N = MaxOps (Vorgabe 2), order.pl bis N = MaxOrder (Vorgabe 2). Ausgabe:
# der Fortschritt; Abweichungen als errorK(...), "Not a factorial",
# "Bound issue" oder failed.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
px() { (cd "$ROOT" && mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- \
  "$HERE/$1" -g "$2" -g halt -q < /dev/null 2>&1 | grep -v '^Compiling\|^Generated\|Warnung'); }
px ops.pl "go([mod, rem, //, div, *, +, -, min, max, ^], ${1:-2})"
px order.pl "assertz(nmax(${2:-2})), \\+ run"
