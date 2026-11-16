#!/bin/sh
# run.sh – dieselben Probleme für library(simplex) (bench.pl: LP, ganzzahlig,
# Transport, Zuordnung; Zufallszahlen aus einem LCG in Prolog) in SWI-Prolog,
# Scryer und PrologEx. Je Fall res(Name, ms, Prüfsumme), beste Zeit aus 3;
# die Prüfsummen müssen überall gleich sein.
#   SCRYER (scryer-prolog), SWIPL (swipl)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
cd "$HERE"
echo "== SWI";    ${SWIPL:-swipl} -O -q -g suite -t halt swi.pl
echo "== Scryer"; ${SCRYER:-scryer-prolog} -g suite -g halt scryer.pl 2>&1 | grep '^res'
cd "$ROOT"
echo "== PrologEx"
MIX_ENV=prod mix run -e 'PrologEx.Toplevel.main(System.argv())' -- bench/simplex/prologex.pl \
  -g suite -g halt 2>&1 | grep '^res'
