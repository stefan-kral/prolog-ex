#!/bin/sh
# cross.sh [NAME…] – die Erwartungen der Programm-Batterie in SWI-Prolog
# und Scryer gegenprüfen (ohne NAME: alle). Je Programm und System "ok"
# oder die verletzten Erwartungen. SWIPL (swipl), SCRYER (scryer-prolog).
HERE=$(cd "$(dirname "$0")" && pwd)
SW=${SWIPL:-swipl}; SC=${SCRYER:-scryer-prolog}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
names=${*:-$(cd "$HERE" && ls *.checks.pl | sed 's/\.checks\.pl$//')}
for n in $names; do
  printf ':- include(%s).\n:- include(%s).\n:- include(%s).\n' \
    "'$HERE/runner.pl'" "'$HERE/$n.pl'" "'$HERE/$n.checks.pl'" > "$TMP/swi.pl"
  printf ':- use_module(library(lists)).\n:- include("%s").\n:- include("%s").\n:- include("%s").\n' \
    "$HERE/runner.pl" "$HERE/$n.pl" "$HERE/$n.checks.pl" > "$TMP/scryer.pl"
  echo "$n: SWI $($SW -q -g report -t halt "$TMP/swi.pl" 2>&1 | tail -1)," \
       "Scryer $($SC -g report -g halt "$TMP/scryer.pl" 2>&1 | tail -1)"
done
