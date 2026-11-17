#!/bin/sh
# run.sh – Gleitkommazahlen lesen, schreiben und umwandeln gegen Nigel Taos
# parse-number-fxx-test-data (5,3 Mio. Zeilen "Text -> IEEE-Bits"; wird
# nach $OUT/src geholt). Orakel für die kürzeste Darstellung: Python repr.
#   PrologEx: Lesen (number_codes, Leser), Schreiben (kürzest, liest sich
#   zurück), Ganzzahl/Bruch -> Float; SWI und Scryer: Lesen + Schreiben
#   (number_codes/number_chars, write). Ergebnisse nach $OUT (Vorgabe
#   tmp/float_text), Zusammenfassung auf stdout.
#   SCRYER, SWIPL: Pfade; SCRYER=- lässt Scryer aus (dauert am längsten)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRYER=${SCRYER:-scryer-prolog}
SWIPL=${SWIPL:-swipl}
OUT=${OUT:-$ROOT/tmp/float_text}
mkdir -p "$OUT"
[ -d "$OUT/src" ] || git clone -q --depth 1 https://github.com/nigeltao/parse-number-fxx-test-data "$OUT/src"
DATA=$(ls "$OUT"/src/data/*.txt)
python3 -I "$HERE/shortest.py" $DATA > "$OUT/shortest.txt"
python3 -I "$HERE/prolog_text.py" $DATA > "$OUT/ptext.txt"
px() { (cd "$ROOT" && mix run "$@" 2>&1 | grep -v '^Compiling\|^Generated'); }
echo "PrologEx lesen/schreiben: $(px "$HERE/check.exs" "$OUT/px_bad.txt" "$OUT/shortest.txt" $DATA), $(wc -l < "$OUT/px_bad.txt") falsch"
echo "PrologEx Ganzzahl/Bruch -> Float: $(px "$HERE/check_conv.exs" "$OUT/conv_bad.txt" $DATA)"
"$SWIPL" "$HERE/swi_rw.pl" "$OUT/ptext.txt" > "$OUT/swi.txt" 2>&1 < /dev/null
echo "SWI: $(python3 -I "$HERE/cmp_rw.py" "$OUT/shortest.txt" "$OUT/swi.txt")"
if [ "$SCRYER" != "-" ]; then
  # Scryer in Stücken (sonst geht ihm der Speicher aus)
  rm -rf "$OUT/parts" && mkdir "$OUT/parts" && split -l 250000 -d -a 2 "$OUT/ptext.txt" "$OUT/parts/p"
  : > "$OUT/scryer.txt"
  for f in "$OUT"/parts/p*; do
    timeout 1200 "$SCRYER" -g "run('$f')" -g halt "$HERE/scryer_rw.pl" >> "$OUT/scryer.txt" 2>&1 < /dev/null
  done
  echo "Scryer: $(python3 -I "$HERE/cmp_rw.py" "$OUT/shortest.txt" "$OUT/scryer.txt")"
fi
