#!/bin/sh
# Demos zu library(concurrent) und library(clpz_concurrent).
#
#   examples/parallel/run.sh [-k Kerne] [klein|mittel|gross] [Demo ...]
#
# Demos: grundlagen eine alle optimieren (Vorgabe: alle vier). -k begrenzt
# die Kerne, die die BEAM nutzt (+S Kerne:Kerne): das Flag cpu_count und
# damit die Zahl der Arbeiter folgen ihm. Braucht einen Build (mix compile
# im Projekt). Jede Zeile: nacheinander, parallel, Faktor, Ergebnis –
# VERSCHIEDEN! hieße, die parallele Fassung gäbe etwas anderes.

DIR=$(cd "$(dirname "$0")" && pwd)
PX="$DIR/../../start_ex"

while getopts k: opt; do
  case $opt in
    k) export ERL_FLAGS="+S $OPTARG:$OPTARG${ERL_FLAGS:+ $ERL_FLAGS}" ;;
    *) sed -n '2,12p' "$0" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

SIZE=klein
case "$1" in klein|mittel|gross) SIZE=$1; shift ;; esac
DEMOS=${*:-grundlagen eine alle optimieren}

cd "$DIR" || exit 1
for d in $DEMOS; do
  case $d in
    grundlagen) f=concurrent_grundlagen.pl ;;
    eine) f=clpz_eine.pl ;;
    alle) f=clpz_alle.pl ;;
    optimieren) f=clpz_optimieren.pl ;;
    *) echo "unbekannte Demo: $d" >&2; exit 2 ;;
  esac
  "$PX" -q "$f" -g "main($SIZE)" -g halt </dev/null
done
