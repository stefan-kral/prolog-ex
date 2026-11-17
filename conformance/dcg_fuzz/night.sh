#!/bin/sh
# night.sh Start Ende [Anzahl] – run.sh (DCGs) für die Seeds Start..Ende (je 200
# Fälle); Zusammenfassung in $OUT/summary.txt, Seeds mit verdächtigen
# Fällen (PrologEx allein, alle verschieden, fehlt) in $OUT/found.txt
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
export OUT=${OUT:-$ROOT/tmp/dcg_fuzz}
A=$1; E=$2; N=${3:-200}
mkdir -p "$OUT"
S=$A
while [ "$S" -le "$E" ]; do
  L=$("$HERE/run.sh" "$S" "$N" 2>&1 | tail -1)
  echo "$S $L" >> "$OUT/summary.txt"
  case "$L" in *"verdächtig 0") rm -f "$OUT/c$S.pl" "$OUT/o$S.scr" "$OUT/o$S.swi" "$OUT/o$S.px" ;;
               *) echo "$S" >> "$OUT/found.txt" ;; esac
  S=$((S + 1))
done
