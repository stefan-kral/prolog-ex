#!/bin/sh
# run.sh – jeder Fall aus cases.pl bei N, 2N, 4N, ... in PrologEx und SWI
# (je Fall ein Lauf, Schluss nach der ersten Messung über LIMIT ms).
# Ausgabe: "System Fall N ms" je Zeile; report.py wertet sie aus.
#   N (10000), K (8 Größen), LIMIT (1500), CASES (alle), SWIPL (swipl;
#   leer: nur PrologEx), TIMEOUT je Fall und System (600 s)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SW=${SWIPL-swipl}
N=${N:-10000}; K=${K:-8}; LIMIT=${LIMIT:-1500}; TO=${TIMEOUT:-600}
CASES=${CASES:-$(grep -o '^case([a-z_0-9]*' "$HERE/cases.pl" | sed 's/case(//' | uniq)}

run() { # System Ziel
  case $1 in
    prologex) (cd "$ROOT" && timeout -k 5 "$TO" mix run --no-compile \
                -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- \
                "$HERE/prelude_prologex.pl" "$HERE/cases.pl" -g "$2" -g halt -q) ;;
    swi) timeout -k 5 "$TO" "$SW" -q -g "$2" -t halt "$HERE/prelude_swi.pl" "$HERE/cases.pl" ;;
  esac
}

systems="prologex"
[ -n "$SW" ] && systems="$systems swi"
for c in $CASES; do
  for s in $systems; do
    run $s "sweep($c, $N, $K, $LIMIT)" 2>/dev/null | sed "s/^/$s /"
  done
done
