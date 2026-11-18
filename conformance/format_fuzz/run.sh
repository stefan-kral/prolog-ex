#!/bin/sh
# run.sh [Seed] [Anzahl] – format/2 mit ~Ne, ~Nf, ~Ng an zufälligen Floats
# gegen Python (exakt gerundet wie printf) und mit ~d, ~D, ~r, ~R, ~e, ~f,
# ~g, ~w an Ganzzahlen bis 10^40 gegen SWI-Prolog (SWIPL=- lässt es aus).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:-$ROOT/tmp/format_fuzz}
SWIPL=${SWIPL:-swipl}
mkdir -p "$OUT"
python3 "$HERE/gen.py" "${1:-1}" "${2:-20000}" "$OUT"
px() { (cd "$ROOT" && mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- \
  "$HERE/run.pl" "$1" -g go -g halt -q < /dev/null 2>&1 | grep -v '^Compiling\|^Generated'); }
px "$OUT/floats.pl" > "$OUT/floats.px"
echo "Floats: $(wc -l < "$OUT/floats.expect") Fälle, verschieden" \
  "$(paste -d'|' "$OUT/floats.px" "$OUT/floats.expect" | awk -F'|' '$1 != $2' | wc -l)"
paste -d'|' "$OUT/floats.pl" "$OUT/floats.px" "$OUT/floats.expect" | awk -F'|' '$2 != $3' | head
if [ "$SWIPL" != "-" ]; then
  px "$OUT/ints.pl" > "$OUT/ints.px"
  "$SWIPL" -g go -t halt "$HERE/run.pl" "$OUT/ints.pl" < /dev/null > "$OUT/ints.swi" 2>&1
  echo "Ganzzahlen: $(wc -l < "$OUT/ints.pl") Fälle, verschieden" \
    "$(paste -d'|' "$OUT/ints.px" "$OUT/ints.swi" | awk -F'|' '$1 != $2' | wc -l)"
  paste -d'|' "$OUT/ints.pl" "$OUT/ints.px" "$OUT/ints.swi" | awk -F'|' '$2 != $3' | head
fi
