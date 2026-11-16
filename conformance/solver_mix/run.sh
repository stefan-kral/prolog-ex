#!/bin/sh
# run.sh Seed [Anzahl] – Anzahl (200) zufällige Fälle in Scryer, PrologEx
# und SWI-Prolog; Vergleich nach $OUT/d<Seed>.txt, erste Zeile auf stdout
#   SCRYER, SWIPL: Pfade; OUT: Verzeichnis (Vorgabe tmp/solver_mix)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRYER=${SCRYER:-scryer-prolog}
SWIPL=${SWIPL:-swipl}
OUT=${OUT:-$ROOT/tmp/solver_mix}
S=$1; N=${2:-200}
mkdir -p "$OUT"
cp "$HERE/dom.pl" "$HERE/par.pl" "$HERE/dom_swi.pl" "$HERE/par_swi.pl" "$OUT/"
python3 "$HERE/gen.py" "$S" "$N" > "$OUT/c$S.pl"
cat "$HERE/head.pl" "$OUT/c$S.pl" > "$OUT/f$S.pl"
cat "$HERE/head_swi.pl" "$OUT/c$S.pl" > "$OUT/s$S.pl"
(cd "$OUT" && timeout 900 "$SCRYER" -g go -g halt "f$S.pl" > "o$S.scr" 2>&1 < /dev/null)
(cd "$OUT" && timeout 900 "$SWIPL" -q -g go -t halt "s$S.pl" > "o$S.swi" 2>&1 < /dev/null)
(cd "$ROOT" && timeout 900 mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' \
   -- "$OUT/f$S.pl" -g go -g halt -q < /dev/null 2>&1 | grep -v '^Compiling\|^Generated' > "$OUT/o$S.px")
python3 "$HERE/cmp.py" "$OUT/o$S.scr" "$OUT/o$S.swi" "$OUT/o$S.px" > "$OUT/d$S.txt"
rm -f "$OUT/f$S.pl" "$OUT/s$S.pl"
head -1 "$OUT/d$S.txt"
