#!/bin/sh
# run.sh [Seed] [N] – N zufällige lineare Programme (gen.py) in Scryer,
# PrologEx und SWI-Prolog lösen und die Zielwerte vergleichen (cmp.py).
#   SCRYER (scryer-prolog), SWIPL (swipl), OUT (tmp/simplex_fuzz)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
S=${1:-1}; N=${2:-300}
OUT=${OUT:-$ROOT/tmp/simplex_fuzz}; mkdir -p "$OUT"
python3 "$HERE/gen.py" "$S" "$N" > "$OUT/p$S.pl"
timeout 900 "${SCRYER:-scryer-prolog}" -g go -g halt "$OUT/p$S.pl" > "$OUT/s$S.out" 2>&1
timeout 900 "${SWIPL:-swipl}" -q -g go -t halt "$OUT/p$S.pl" > "$OUT/w$S.out" 2>&1
cd "$ROOT" && timeout 900 mix run -e 'PrologEx.Toplevel.main(System.argv())' -- \
  "$OUT/p$S.pl" -g go -g halt 2>&1 | grep -v '^%' > "$OUT/x$S.out"
python3 "$HERE/cmp.py" "$OUT/s$S.out" "$OUT/x$S.out" "$OUT/w$S.out"
