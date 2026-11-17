#!/bin/sh
# run.sh – JSONTestSuite (test/fixtures/jsontestsuite) mit beiden JSON-
# Bibliotheken: library(http/json) in SWI-Prolog und PrologEx,
# library(serialization/json) in Scryer und PrologEx. Ergebnisse nach
# $OUT (Vorgabe tmp/jsontestsuite), Auswertung auf stdout (cmp.py).
#   SCRYER, SWIPL: Pfade
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRYER=${SCRYER:-scryer-prolog}
SWIPL=${SWIPL:-swipl}
OUT=${OUT:-$ROOT/tmp/jsontestsuite}
DIR=$ROOT/test/fixtures/jsontestsuite/test_parsing
mkdir -p "$OUT"
{ echo "dir('$DIR/')."; for f in $(ls "$DIR"); do echo "file('$f')."; done; } > "$OUT/files.pl"
px() {
  (cd "$ROOT" && mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' \
     -- "$1" -g run -g halt -q < /dev/null 2>/dev/null | grep -v '^Compiling\|^Generated')
}
cat "$HERE/swi_json.pl" "$OUT/files.pl" > "$OUT/http.pl"
cat "$HERE/scryer_json.pl" "$HERE/px_ser.pl" "$OUT/files.pl" > "$OUT/ser.pl"
"$SWIPL" -q -g run -t halt "$OUT/http.pl" > "$OUT/swi.txt" 2>/dev/null < /dev/null
px "$OUT/http.pl" > "$OUT/px_http.txt"
px "$OUT/ser.pl" > "$OUT/px_ser.txt"
# Scryer je Datei (10 s), damit ein Absturz nur eine Datei trifft
: > "$OUT/scryer.txt"
for f in $(ls "$DIR"); do
  r=$(timeout 10 "$SCRYER" -g "assertz(path('$DIR/$f')),run1" -g halt "$HERE/scryer_json.pl" 2>/dev/null < /dev/null | tail -1)
  echo "$f ${r:-timeout}" >> "$OUT/scryer.txt"
done
python3 "$HERE/cmp.py" "$OUT/swi.txt" "$OUT/px_http.txt" "$OUT/scryer.txt" "$OUT/px_ser.txt"
