#!/bin/sh
# run.sh – library(clpb) an SATLIB-Formeln mit bekanntem Ergebnis, in
# PrologEx, SWI-Prolog und Scryer (je Formel TLIMIT s, Vorgabe 20). Holt
# die Formeln nach $OUT/src (Spiegel auf GitHub: Randy1005/QSat, nckelemu/uf20-91):
#   uf20-91 (1000, erfüllbar; Modelle durch Durchprobieren, count.py),
#   aim (erfüllbar laut Name), dubois, pret, hole7-9 (unerfüllbar), dazu
#   je 5 aus uf50-218/uuf50-218 (für BDDs zu groß: Zeitgrenze erwartet).
# Ausgabe je System: "Name ok" oder "Name Ergebnis-Modelle" / Ausnahme.
#   SCRYER, SWIPL: Pfade; SCRYER=- oder SWIPL=- lässt das System aus
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRYER=${SCRYER:-scryer-prolog}
SWIPL=${SWIPL:-swipl}
OUT=${OUT:-$ROOT/tmp/satlib}
TLIMIT=${TLIMIT:-20}
FIX=$ROOT/test/fixtures/satlib
mkdir -p "$OUT/src"
if [ ! -d "$OUT/src/qsat" ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/Randy1005/QSat "$OUT/src/qsat"
  (cd "$OUT/src/qsat" && git sparse-checkout set benchmarks/aim benchmarks/dubois benchmarks/pret \
     benchmarks/uf50-218 benchmarks/uuf50-218 && git checkout -q)
fi
[ -d "$OUT/src/uf20" ] || git clone -q --depth 1 https://github.com/nckelemu/uf20-91 "$OUT/src/uf20"
B=$OUT/src/qsat/benchmarks
python3 -I "$HERE/count.py" "$OUT"/src/uf20/*.cnf > "$OUT/uf20_counts.txt"
python3 -I "$HERE/fixture.py" "$OUT/all.pl" "$OUT/uf20_counts.txt" "$OUT"/src/uf20/*.cnf \
  "$B"/aim/*.cnf "$B"/dubois/*.cnf "$B"/pret/*.cnf "$B"/hole[789].cnf \
  $(ls "$B"/uf50-218/*.cnf | sort -t- -k2 -n | head -5) $(ls "$B"/uuf50-218/*.cnf | sort -t- -k2 -n | head -5)
{ cat "$FIX/sat.pl" "$OUT/all.pl" "$HERE/drive.pl"; echo "tlimit($TLIMIT)."; } > "$OUT/run.pl"
summary() { echo "$1: $(wc -l < "$2") Formeln, $(grep -c ' ok$' "$2") ok"; grep -v ' ok$' "$2" | sed 's/^/    /' | head -40; }
(cd "$ROOT" && mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- "$OUT/run.pl" -g run -g halt -q \
   < /dev/null 2>/dev/null | grep -v '^Compiling\|^Generated') > "$OUT/px.txt"
summary PrologEx "$OUT/px.txt"
if [ "$SWIPL" != "-" ]; then
  "$SWIPL" --stack_limit=4g -q -g run -t halt "$OUT/run.pl" < /dev/null 2>/dev/null > "$OUT/swi.txt"
  summary SWI "$OUT/swi.txt"
fi
if [ "$SCRYER" != "-" ]; then
  cat "$FIX/sat.pl" "$OUT/all.pl" > "$OUT/scryer.pl"
  : > "$OUT/scryer.txt"
  for f in $(grep -o "^expected('[^']*'" "$OUT/all.pl" | cut -d"'" -f2); do
    r=$(timeout "$TLIMIT" "$SCRYER" -g "verdict('$f', V), write(V), nl, halt" "$OUT/scryer.pl" 2>&1 < /dev/null | tail -1)
    echo "$f ${r:-time_limit_exceeded}" >> "$OUT/scryer.txt"
  done
  summary Scryer "$OUT/scryer.txt"
fi
