#!/bin/sh
# run.sh [Seed] [Anzahl] – Ganzzahlarithmetik (+ - * // div mod rem >> <<
# /\ \/ xor min max gcd ^ abs sign - \ msb) an Zufallszahlen gegen Python
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:-$ROOT/tmp/arith_fuzz}
mkdir -p "$OUT"
(cd "$OUT" && python3 "$HERE/gen.py" "${1:-1}" "${2:-30000}")
(cd "$ROOT" && mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- \
  "$HERE/run.pl" "$OUT/cases.pl" -g go -g halt -q < /dev/null 2>&1 \
  | grep -v '^Compiling\|^Generated') > "$OUT/px.txt"
echo "$(wc -l < "$OUT/expect.txt") Fälle, verschieden $(diff "$OUT/px.txt" "$OUT/expect.txt" | grep -c '^<')"
diff "$OUT/px.txt" "$OUT/expect.txt" | head -20
