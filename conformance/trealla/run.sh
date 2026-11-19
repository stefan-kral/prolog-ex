#!/bin/sh
# run.sh [MUSTER…] – PrologEx gegen die Tests von Trealla Prolog (MIT):
# jedes Programm tests/{tests,issues,issues-OLD,sundry,misc}/*.pl wie in
# Trealla geladen (im Wurzelordner von Trealla, initialization(main)), die
# Ausgabe auf stdout mit NAME.expected verglichen. Vorher lädt
# prelude.pl die Bibliotheken, die Trealla (wie SWI) von selbst kennt.
# MUSTER: nur diese Dateien (etwa 'tests/tests/test00*'). Ausgabe: je
# Datei "ok", "diff" (Ausgabe anders) oder "rcN" (Ausgabe gleich, aber
# Exit-Code N), dazu die Zählung und welche Prädikate fehlten
# (existence_error); Einzelheiten in $W/out/. Mit TPL=…/tpl läuft
# daneben Trealla selbst: dann zählen nur Tests, die Trealla besteht
# ("tplfail" sonst). Mit SWIPL=swipl bzw. SCRYER=scryer-prolog heißt eine
# Abweichung "swi" bzw. "scryer", wenn PrologEx genau so ausgibt wie
# dieses System – dann ist sie eine Eigenheit von Trealla.
# Wie viele parallel: JOBS (Vorgabe 6).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
REV=9ac861d0833abc73c23424da03de0cbcf1fe9cb5
W=${TREALLA_DIR:-${TMPDIR:-/tmp}/trealla}

if [ "$1" = "--one" ]; then
  # eine Datei: $2 relativ zum Wurzelordner von Trealla
  src=$2; n=$(echo "$src" | tr / _)
  out="$W/out/$n"
  set +e
  (cd "$ROOT" && LC_ALL=C.UTF-8 timeout -k 5 60 mix run --no-compile \
     -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- \
     "$W/prelude.pl" "$W/$src" -g halt -q < /dev/null > "$out.px" 2> "$out.err")
  rc=$?
  if [ -n "$TPL" ]; then
    (cd "$W" && LC_ALL=C.UTF-8 timeout -k 5 60 "$TPL" -q -f -g halt "$src" < /dev/null > "$out.tpl" 2>&1)
    diff -a --strip-trailing-cr "$W/${src%.*}.expected" "$out.tpl" > /dev/null 2>&1 ||
      { echo "tplfail $src"; exit 0; }
  fi
  if diff -a --strip-trailing-cr "$W/${src%.*}.expected" "$out.px" > /dev/null 2>&1; then
    [ $rc -eq 0 ] && echo "ok $src" || echo "rc$rc $src"
  else
    # wie SWI oder Scryer (beide auf dieselbe Datei, SWI mit seinen
    # Autoload-Bibliotheken, Scryer mit prelude_scryer.pl)?
    if [ -n "$SWIPL" ]; then
      (cd "$W" && LC_ALL=C.UTF-8 timeout -k 5 60 "$SWIPL" -q -g halt "$src" < /dev/null > "$out.swi" 2> /dev/null)
      cmp -s "$out.px" "$out.swi" && { echo "swi $src"; exit 0; }
    fi
    if [ -n "$SCRYER" ]; then
      (cd "$W" && LC_ALL=C.UTF-8 timeout -k 5 60 "$SCRYER" -g halt "$HERE/prelude_scryer.pl" "$src" < /dev/null > "$out.scr" 2> /dev/null)
      cmp -s "$out.px" "$out.scr" && { echo "scryer $src"; exit 0; }
    fi
    echo "diff $src"
  fi
  exit 0
fi

if [ ! -d "$W/.git" ]; then
  git clone -q https://github.com/trealla-prolog/trealla "$W"
fi
(cd "$W" && git checkout -q "$REV")
mkdir -p "$W/out"
# der Vorspann: Bibliotheken, dann (für relative Pfade der Tests) in den
# Wurzelordner von Trealla
{ cat "$HERE/prelude.pl"; printf ':- working_directory(_, "%s/").\n' "$W"; } > "$W/prelude.pl"
(cd "$ROOT" && . "${ENV28:-/dev/null}" 2>/dev/null; mix compile > /dev/null)

pats=${*:-'tests/tests/* tests/issues/* tests/issues-OLD/* tests/sundry/* tests/misc/*'}
(cd "$W" && for p in $pats; do ls $p 2>/dev/null; done) | grep '\.pl$' |
  grep -v '^tests/janus' |
  xargs -P "${JOBS:-6}" -n1 "$0" --one | sort -k2 > "$W/results.txt"

echo "Ergebnis ($W/results.txt):"
awk '{print $1}' "$W/results.txt" | sort | uniq -c
echo "Fehlende Prädikate (Zahl der Meldungen):"
cat "$W"/out/*.err 2>/dev/null |
  grep -o 'existence_error(procedure,[^)]*)' | sort | uniq -c | sort -rn | head -40
