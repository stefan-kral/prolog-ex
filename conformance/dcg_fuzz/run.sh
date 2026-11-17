#!/bin/sh
# run.sh Seed [Anzahl] – Anzahl (200) zufällige DCGs in Scryer, PrologEx
# und SWI-Prolog; Vergleich nach $OUT/d<Seed>.txt, erste Zeile auf stdout
#   SCRYER, SWIPL: Pfade; OUT: Verzeichnis (Vorgabe tmp/dcg_fuzz)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRYER=${SCRYER:-scryer-prolog}
SWIPL=${SWIPL:-swipl}
OUT=${OUT:-$ROOT/tmp/dcg_fuzz}
S=$1; N=${2:-200}
mkdir -p "$OUT"
python3 "$HERE/gen.py" "$S" "$N" > "$OUT/c$S.pl"
cat "$HERE/head.pl" "$OUT/c$S.pl" "$HERE/tail.pl" > "$OUT/f$S.pl"
cat "$HERE/head_swi.pl" "$OUT/c$S.pl" "$HERE/tail.pl" > "$OUT/s$S.pl"
# Scryer stürzt bei manchen Fällen ab (panic): ab dem nächsten Fall neu
# starten; der abgestürzte Fall bekommt die Zeile "Id crash"
: > "$OUT/o$S.scr"; K=0
while [ "$K" -lt "$N" ]; do
  (cd "$OUT" && timeout 900 "$SCRYER" -g "go_from($K)" -g halt "f$S.pl" >> "o$S.scr" 2>&1 < /dev/null)
  L=$(grep -oE '^[0-9]+ \[' "$OUT/o$S.scr" | tail -1 | cut -d' ' -f1)
  [ -z "$L" ] && L=$((K - 1))
  [ "$L" -ge $((N - 1)) ] && break
  [ "$L" -lt "$K" ] && L=$((K - 1))
  echo "$((L + 1)) crash" >> "$OUT/o$S.scr"; K=$((L + 2))
done
(cd "$OUT" && timeout 900 "$SWIPL" -q -g go -t halt "s$S.pl" > "o$S.swi" 2>&1 < /dev/null)
(cd "$ROOT" && timeout 900 mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' \
   -- "$OUT/f$S.pl" -g go -g halt -q < /dev/null 2>&1 | grep -v '^Compiling\|^Generated' > "$OUT/o$S.px")
python3 "$HERE/cmp.py" "$OUT/o$S.scr" "$OUT/o$S.swi" "$OUT/o$S.px" "$OUT/c$S.pl" > "$OUT/d$S.txt"
rm -f "$OUT/f$S.pl" "$OUT/s$S.pl"
head -1 "$OUT/d$S.txt"
