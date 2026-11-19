#!/bin/sh
# run.sh – die Beispiele aus examples.pl in PrologEx, SWI, Scryer und
# Trealla: erst die Ergebnisse (main), dann die Laufzeiten (beste von 3, ms
# CPU). SWIPL (swipl), SCRYER (scryer-prolog), TPL (tpl); ein leerer Wert
# lässt das System aus.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SW=${SWIPL-swipl}; SC=${SCRYER-scryer-prolog}; TP=${TPL-tpl}
SIZES=${SIZES:-"sum_loop:100000 sum_gen:100000 sum_findall:100000 state:100000 same_fringe:16384 same_fringe_left:4000 primes:500"}

run() { # System Ziel...
  case $1 in
    prologex) shift; (cd "$ROOT" && mix run --no-compile -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- \
                 "$HERE/prelude_prologex.pl" "$HERE/examples.pl" "$@" -g halt -q) ;;
    swi) shift; $SW -q "$@" -t halt "$HERE/prelude_swi.pl" "$HERE/examples.pl" ;;
    scryer) shift; $SC "$@" -g halt "$HERE/prelude_scryer.pl" "$HERE/examples.pl" ;;
    trealla) shift; $TP -q "$@" -g halt "$HERE/prelude_trealla.pl" "$HERE/examples.pl" ;;
  esac
}

systems="prologex"
[ -n "$SW" ] && systems="$systems swi"
[ -n "$SC" ] && systems="$systems scryer"
[ -n "$TP" ] && systems="$systems trealla"

for s in $systems; do
  echo "== $s"
  run $s -g main 2>&1
done

echo "== Laufzeit (ms, beste von 3)"
for s in $systems; do
  for b in $SIZES; do
    name=${b%%:*}; n=${b##*:}
    g="time($name, $n), time($name, $n), time($name, $n)"
    best=$(run $s -g "$g" 2>/dev/null | awk '{print $3}' | sort -n | head -1)
    echo "$s $name $n ${best:-?}"
  done
done
