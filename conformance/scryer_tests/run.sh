#!/bin/sh
# run.sh – Scryers eigene Tests (src/tests/*.pl) in PrologEx und in Scryer:
#   mit test/2 (Rahmen test_framework.pl): je Test "Name ok", "Name fail"
#     oder "Name error(E)" (drive.pl), am Ende die Tests, die nur in
#     PrologEx nicht "ok" sind;
#   sonst laden (die Tests laufen als initialization oder über main/0) und
#     die Ausgaben beider Systeme vergleichen.
# SCRYER_SRC: Scryers Quellverzeichnis, SCRYER: das Programm,
# OUT: Ausgabeverzeichnis.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SRC=${SCRYER_SRC:-$HOME/mthom/scryer-prolog}
SCRYER=${SCRYER:-$SRC/target/release/scryer-prolog}
OUT=${OUT:-$ROOT/tmp/scryer_tests}
mkdir -p "$OUT"
for f in "$SRC"/src/tests/*.pl; do
  b=$(basename "$f" .pl)
  [ "$b" = test_framework ] && continue
  m=$(sed -n 's/^:- module(\([a-z_]*\),.*/\1/p' "$f" | head -1)
  m=${m:-user}
  if grep -q '^test(' "$f"; then g="run_module($m)"
  elif grep -q '^main :-' "$f"; then g=main
  else g=true; fi
  (cd "$ROOT" && mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- \
     "$HERE/drive.pl" "$f" -g "$g" -g halt -q < /dev/null 2>&1 \
     | grep -v '^Compiling\|^Generated\|: Warnung (Zeile') > "$OUT/$b.px.txt"
  (cd "$SRC/src/tests" && "$SCRYER" -f "$HERE/drive.pl" "$f" -g "$g" -g halt < /dev/null 2>&1 \
     | grep -v '^% Warning') > "$OUT/$b.scryer.txt"
  if [ "$g" = "run_module($m)" ]; then
    echo "$b: PrologEx $(grep -c ' ok$' "$OUT/$b.px.txt")/$(wc -l < "$OUT/$b.px.txt") ok," \
         "Scryer $(grep -c ' ok$' "$OUT/$b.scryer.txt")/$(wc -l < "$OUT/$b.scryer.txt") ok"
    grep -v ' ok$' "$OUT/$b.px.txt" | while IFS= read -r l; do
      n=${l%% *}
      grep -q "^$n ok$" "$OUT/$b.scryer.txt" && echo "    $l"
    done
  elif cmp -s "$OUT/$b.px.txt" "$OUT/$b.scryer.txt"; then
    echo "$b: Ausgabe gleich"
  else
    echo "$b: Ausgabe verschieden"
    diff "$OUT/$b.px.txt" "$OUT/$b.scryer.txt" | head -8 | sed 's/^/    /'
  fi
done
