#!/bin/sh
# cross.sh [NAME…] – die Erwartungen der Programm-Batterie in SWI-Prolog
# und Scryer gegenprüfen (ohne NAME: alle). Je Programm und System "ok"
# oder die verletzten Erwartungen. SWIPL (swipl), SCRYER (scryer-prolog).
# library(clpz) ist in SWI library(clpfd) (bench/swi/clpz.pl).
HERE=$(cd "$(dirname "$0")" && pwd)
SW=${SWIPL:-swipl}; SC=${SCRYER:-scryer-prolog}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
names=${*:-$(cd "$HERE" && ls *.checks.pl | sed 's/\.checks\.pl$//')}
for n in $names; do
  printf ':- include(%s).\n:- include(%s).\n:- include(%s).\n' \
    "'$HERE/runner.pl'" "'$HERE/$n.pl'" "'$HERE/$n.checks.pl'" > "$TMP/swi.pl"
  # Scryer liest eine eingebundene Datei ganz, bevor ihre Direktiven
  # laufen: die Bibliotheken des Programms (ihre Operatoren, etwa ins aus
  # clpz) vorher laden, ebenso double_quotes setzen; phrase/2,3 liegen in
  # Scryer in library(dcgs)
  { printf ':- use_module(library(lists)).\n:- use_module(library(dcgs)).\n'
    grep -E '^:- (use_module\(library\(|set_prolog_flag\(double_quotes)' "$HERE/$n.pl"
    # Pfade als Atome: ein Programm kann double_quotes umstellen
    printf ":- include('%s').\n:- include('%s').\n:- include('%s').\n" \
      "$HERE/runner.pl" "$HERE/$n.pl" "$HERE/$n.checks.pl"; } > "$TMP/scryer.pl"
  echo "$n: SWI $($SW -p library="$HERE/../../bench/swi" -q -g report -t halt "$TMP/swi.pl" 2>&1 | tail -1)," \
       "Scryer $($SC -g report -g halt "$TMP/scryer.pl" 2>&1 | tail -1)"
done
