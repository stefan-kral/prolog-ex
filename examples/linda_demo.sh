#!/bin/sh
# Anwendungsfälle von library(linda) mit mehreren PrologEx-Sitzungen (eigene
# Prozesse): examples/linda.pl, je Rolle eine Sitzung.
#
#   examples/linda_demo.sh [Worker]      (Vorgabe: 4 Worker)
#
# Braucht einen Build (mix compile) und epmd (startet PrologEx selbst).

DIR=$(cd "$(dirname "$0")/.." && pwd)
PX="$DIR/start_ex"
PL="$DIR/examples/linda.pl"
W=${1:-4}
ADDR=$(mktemp "${TMPDIR:-/tmp}/linda_demo.XXXXXX")
rm -f "$ADDR"

run() { "$PX" -q "$PL" -g "$1" -g halt </dev/null; }
# im Hintergrund; die Prozessnummern merkt sich PIDS (warten: wait_all)
PIDS=""
bg() { "$PX" -q "$PL" -g "$1" -g halt </dev/null & PIDS="$PIDS $!"; }
wait_all() { for p in $PIDS; do wait "$p"; done; PIDS=""; }

# Server im Hintergrund; warten, bis seine Adresse da ist
"$PX" -q "$PL" -g "server('$ADDR')" -g halt </dev/null &
SERVER=$!
i=0
while [ ! -s "$ADDR" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
[ -s "$ADDR" ] || { echo "Server startet nicht" >&2; exit 1; }

echo "--- 1. Arbeitsliste: $W Worker, 40 Aufgaben fib(21)"
for _ in $(seq "$W"); do bg "worker('$ADDR')"; done
run "master('$ADDR', 40, 21)"
wait_all
run "farm_bericht('$ADDR')"

echo "--- 2. Zähler: 4 Sitzungen je 50 Schritte"
run "zaehler_start('$ADDR')"
for _ in 1 2 3 4; do bg "zaehler('$ADDR', 50)"; done
wait_all
run "zaehler_stand('$ADDR')"

echo "--- 3. Puffer: 3 Plätze, 100 Elemente"
run "puffer_start('$ADDR', 3)"
bg "erzeuger('$ADDR', 100)"
run "verbraucher('$ADDR', 3)"
wait_all

echo "--- 4. Barriere: 4 Teilnehmer, 5 Runden"
run "barriere_start('$ADDR', 5)"
for i in 1 2 3 4; do bg "teilnehmer('$ADDR', $i, 4, 5)"; done
wait_all
run "barriere_pruefen('$ADDR', 4, 5)"

echo "--- 5. Philosophen: 5 am Tisch, je 10 Mahlzeiten"
run "tisch('$ADDR', 5)"
for i in 1 2 3 4 5; do bg "philosoph('$ADDR', $i, 5, 10)"; done
wait_all
run "tisch_pruefen('$ADDR', 5, 10)"

run "beenden('$ADDR')"
wait "$SERVER"
rm -f "$ADDR"
