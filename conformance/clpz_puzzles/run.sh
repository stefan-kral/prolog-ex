#!/bin/sh
# run.sh – library(clpz) an Rätseln mit bekanntem Ergebnis, in PrologEx,
# SWI-Prolog (mit bench/swi/clpz.pl) und Scryer:
#   alle 49151 Sudokus mit 17 Vorgaben von Gordon Royle (eindeutig lösbar;
#   Spiegel auf GitHub: coryf/sudoku), Golomb-Lineale mit 1..GMAX Marken
#   (Vorgabe 10; je 600 s, kürzeste Länge aus OEIS A003022).
# Ausgabe je System: "Name ok" oder die Abweichung.
#   SCRYER, SWIPL: Pfade; SCRYER=- oder SWIPL=- lässt das System aus;
#   LIMIT=n nur die ersten n Sudokus
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRYER=${SCRYER:-scryer-prolog}
SWIPL=${SWIPL:-swipl}
OUT=${OUT:-$ROOT/tmp/clpz_puzzles}
GMAX=${GMAX:-10}
FIX=$ROOT/test/fixtures/clpz_puzzles
mkdir -p "$OUT/src"
if [ ! -d "$OUT/src/sudoku" ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/coryf/sudoku "$OUT/src/sudoku"
  (cd "$OUT/src/sudoku" && git sparse-checkout set data && git checkout -q)
fi
awk -v lim="${LIMIT:-0}" 'lim == 0 || NR <= lim {printf "puzzle(%c%d%c, %c%s%c).\n", 39, NR, 39, 39, $1, 39}' \
  "$OUT/src/sudoku/data/sudoku17" > "$OUT/puzzles.pl"
{ cat "$FIX/sudoku.pl" "$FIX/golomb.pl" "$OUT/puzzles.pl" "$HERE/drive.pl"; echo "gmax($GMAX)."; } > "$OUT/run.pl"
summary() { echo "$1: $(wc -l < "$2") Aufgaben, $(grep -c ' ok$' "$2") ok"; grep -v ' ok$' "$2" | sed 's/^/    /' | head -40; }
(cd "$ROOT" && mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- "$OUT/run.pl" \
   -g "use_module(library(time))" -g run -g grun -g halt -q < /dev/null 2>/dev/null \
   | grep -v '^Compiling\|^Generated') > "$OUT/px.txt"
summary PrologEx "$OUT/px.txt"
if [ "$SWIPL" != "-" ]; then
  LANG=C.UTF-8 "$SWIPL" -p library="$ROOT/bench/swi" -q -g run -g grun -t halt "$OUT/run.pl" \
    < /dev/null 2>/dev/null > "$OUT/swi.txt"
  summary SWI "$OUT/swi.txt"
fi
if [ "$SCRYER" != "-" ]; then
  # ohne call_with_time_limit/2: Golomb je Markenzahl ein Lauf mit timeout
  "$SCRYER" -g run -g halt "$OUT/run.pl" < /dev/null 2>/dev/null > "$OUT/scryer.txt"
  for n in $(seq 1 "$GMAX"); do
    r=$(timeout 600 "$SCRYER" -g "g_verdict($n, V), write(V), nl, halt" "$OUT/run.pl" 2>/dev/null < /dev/null | tail -1)
    echo "golomb$n ${r:-time_limit_exceeded}" >> "$OUT/scryer.txt"
  done
  summary Scryer "$OUT/scryer.txt"
fi
