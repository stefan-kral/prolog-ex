#!/bin/sh
# night.sh [Start] [Ende] [Anzahl] – run.sh für die Seeds Start..Ende
# (Vorgabe 1000..1999, je 500 Fälle); Zusammenfassung in $OUT/summary.txt,
# Seeds mit Unterschieden in $OUT/found.txt
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
export OUT=${OUT:-$ROOT/tmp/clpz_fuzz}
A=${1:-1000}; E=${2:-1999}; N=${3:-500}
mkdir -p "$OUT"
S=$A
while [ "$S" -le "$E" ]; do
  L=$("$HERE/run.sh" "$S" "$N" 2>&1 | tail -1)
  echo "$S $L" >> "$OUT/summary.txt"
  case "$L" in *"verschieden 0") ;; *) echo "$S" >> "$OUT/found.txt" ;; esac
  rm -f "$OUT/f$S.pl"
  S=$((S + 1))
done
