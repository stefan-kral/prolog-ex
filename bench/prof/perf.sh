#!/bin/sh
# perf.sh Fall… – Profil der echten Zeit mit perf (Linux): jeder Fall läuft
# SECS (6) Sekunden in einer Schleife (loop.exs) auf einem Scheduler, die
# BEAM mit +JPperf true (JIT-Symbole und Rahmenzeiger), perf zeichnet
# Stacks auf; stacks.py ordnet jede Stichprobe der nächsten Elixir-Funktion
# zu (samt BIFs, GC, Map-Zugriffen darunter) und Zeit in Enum und Co. dem
# ersten Aufrufer aus PrologEx.
#
#   bench/prof/perf.sh queens clpz_sudoku
#   EXTRA='srt=numlist(1,50000,L), msort(L,_)' bench/prof/perf.sh srt
#   bench/prof/who.py tmp/prof/perf.srt.data 'Enum|lists'   # wer ruft das?
#
# Umgebung: PERF (sonst das erste lauffähige perf im PATH oder unter
# /usr/lib/linux-tools*/),
# OUT (tmp/prof), SECS, TOP (Zeilen je Liste), PRELUDE und EXTRA wie in
# common.exs; MIX_ENV ist prod, wenn nicht gesetzt. perf aufzeichnen darf,
# wer root ist oder bei kernel.perf_event_paranoid <= 2 (eigene Prozesse).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
# (Ubuntus /usr/bin/perf ist nur ein Wrapper, der bei fremdem Kernel
# scheitert: das erste perf nehmen, das läuft)
if [ -z "$PERF" ]; then
  for p in $(command -v perf) /usr/lib/linux-tools*/perf; do
    "$p" --version > /dev/null 2>&1 && { PERF=$p; break; }
  done
fi
[ -n "$PERF" ] || { echo "perf nicht gefunden (PERF=…)" >&2; exit 1; }
export PERF
OUT=${OUT:-$ROOT/tmp/prof}; S=${SECS:-6}
export MIX_ENV=${MIX_ENV:-prod}
mkdir -p "$OUT"
cd "$ROOT" && mix compile >/dev/null || exit 1
for C in "$@"; do
  rm -f "$OUT/ready.$C"
  ELIXIR_ERL_OPTIONS="+JPperf true +S 1" SECS=$S READY="$OUT/ready.$C" \
    mix run "$HERE/loop.exs" "$C" > /dev/null 2> "$OUT/loop.$C.err" &
  M=$!
  until [ -f "$OUT/ready.$C" ]; do
    kill -0 $M 2>/dev/null || { echo "$C: Fehler, siehe $OUT/loop.$C.err" >&2; continue 2; }
    sleep 0.2
  done
  PID=$(pgrep -f "beam.smp.*loop.exs $C\$" | head -1)
  "$PERF" record -F 1999 --call-graph=fp -p "$PID" -o "$OUT/perf.$C.data" -- sleep $((S - 1)) > /dev/null 2>&1
  wait $M
  echo "=== $C"
  python3 "$HERE/stacks.py" "$OUT/perf.$C.data" "${TOP:-12}"
done
