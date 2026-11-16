#!/bin/sh
# run.sh – dieselben Meta-Interpreter (mi*.pl) über dieselben Programme
# (prog.pl) in SWI-Prolog, Scryer und PrologEx; Prädikate statisch und
# dynamisch (Scryer: clause/2 nur auf dynamischen). Ergebnis je Zeile
# res(Fall, N, ms für N Läufe, µs je Lauf), beste Zeit aus 3.
#   SCRYER (scryer-prolog), SWIPL (swipl), OUT (tmp/mi)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:-$ROOT/tmp/mi}; mkdir -p "$OUT"
SC=${SCRYER:-scryer-prolog}; SW=${SWIPL:-swipl}
cd "$HERE"
$SW -O -q -g "suite([v, soft])" -t halt swi_static.pl > "$OUT/swi_static.txt" 2>&1
$SW -O -q -g "suite([v, dyn, soft])" -t halt swi_dynamic.pl > "$OUT/swi_dynamic.txt" 2>&1
$SC -g "suite([])" -g halt scryer_static.pl 2>&1 | grep -v "^%" > "$OUT/scryer_static.txt"
$SC -g "suite([v, dyn])" -g halt scryer_dynamic.pl 2>&1 | grep -v "^%" > "$OUT/scryer_dynamic.txt"
cd "$ROOT"
MIX_ENV=prod mix run -e 'PrologEx.Toplevel.main(System.argv())' -- bench/mi/prologex_static.pl \
  -g "suite([v, soft, cx])" -g halt 2>&1 | grep -v "^%" > "$OUT/prologex_static.txt"
MIX_ENV=prod mix run -e 'PrologEx.Toplevel.main(System.argv())' -- bench/mi/prologex_dynamic.pl \
  -g "suite([v, dyn, soft, cx])" -g halt 2>&1 | grep -v "^%" > "$OUT/prologex_dynamic.txt"
