#!/bin/sh
# run.sh Seed [Anzahl] – erzeugt Anzahl (500) zufällige Fälle, lässt sie in
# Scryer und PrologEx laufen und schreibt den Vergleich nach $OUT/d<Seed>.txt
#   SCRYER  Pfad zu scryer-prolog (Vorgabe: scryer-prolog)
#   OUT     Verzeichnis für Fälle und Ausgaben (Vorgabe: tmp/clpz_fuzz)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRYER=${SCRYER:-scryer-prolog}
OUT=${OUT:-$ROOT/tmp/clpz_fuzz}
S=$1; N=${2:-500}
mkdir -p "$OUT"
python3 "$HERE/gen.py" "$S" "$N" > "$OUT/c$S.pl"
cat "$HERE/head.pl" "$OUT/c$S.pl" > "$OUT/f$S.pl"
timeout 900 "$SCRYER" -g go -g halt "$OUT/f$S.pl" > "$OUT/o$S.scr" 2>&1 || true
(cd "$ROOT" && timeout 900 mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' \
   -- "$OUT/f$S.pl" -g go -g halt -q 2>&1 | grep -v '^Compiling\|^Generated' > "$OUT/o$S.px") || true
python3 "$HERE/cmp.py" "$OUT/o$S.scr" "$OUT/o$S.px" "$OUT/c$S.pl" > "$OUT/d$S.txt"
head -1 "$OUT/d$S.txt"
