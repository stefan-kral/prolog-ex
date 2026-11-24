#!/usr/bin/env bash
# Belastungsläufe für library(concurrent) und library(clpz_concurrent) auf
# vielen Kernen: die Zufalls-, Chaos- und Robustheitstests über eine Matrix
# aus Scheduler-Zahlen (+S N:N), JIT-Einstellungen und Seeds.
#
#   bench/stress/run.sh [-q | -f] [-s "2 8 16"] [-j "on off clause"]
#                       [-n SEEDS] [-r RUNDEN] [-p]
#
#   (ohne)  normal: Scheduler 2, Kerne, 2×Kerne; JIT on, off, clause; ein
#           neuer zufälliger Seed; je Lauf die langen Fassungen (slow)
#   -q      schnell: nur Kerne, JIT on, die kurzen Fassungen (~2 min)
#   -f      gründlich: Scheduler 1 2 4 8 Kerne 2×Kerne, alle fünf JIT-
#           Einstellungen, drei Seeds (Stunden)
#   -s "…"  Scheduler-Zahlen (max = Kerne)
#   -j "…"  JIT: on off eager clause clause_sync (PrologEx.TestEnv)
#   -n N    so viele zufällige Seeds (oder -n "7 8 9": genau diese)
#   -r N    die festen Tests (concurrent, clpz_concurrent, robust) je
#           Einstellung N-mal (--repeat-until-failure; Vorgabe 3)
#   -p      dazu die Skalierung: examples/parallel/run.sh -t (mittel)
#
# Ergebnis: bench/stress/out/ZEIT/summary.md (eine Zeile je Lauf) und je
# Lauf ein Log; Rückgabe 1, wenn etwas abwich oder scheiterte. Jede Zeile
# nennt die Umgebung, mit der sich der Lauf wiederholen lässt.
set -u
cd "$(dirname "$0")/../.." || exit 2

CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
MODE=normal
SCHED=""
JITS=""
SEEDS=""
REPEAT=3
SCALING=0

usage() { [ -n "${1:-}" ] && echo "run.sh: $1" >&2; sed -n '2,24p' "$0" >&2; exit 2; }

while getopts qfs:j:n:r:p opt; do
  case $opt in
    q) MODE=quick ;;
    f) MODE=full ;;
    s) SCHED=$OPTARG ;;
    j) JITS=$OPTARG ;;
    n) SEEDS=$OPTARG ;;
    r) REPEAT=$OPTARG ;;
    p) SCALING=1 ;;
    *) usage ;;
  esac
done

case $MODE in
  quick) : "${SCHED:=max}" "${JITS:=on}" "${SEEDS:=1}" ;;
  normal) : "${SCHED:=2 max $((CORES * 2))}" "${JITS:=on off clause}" "${SEEDS:=1}" ;;
  full) : "${SCHED:=1 2 4 8 max $((CORES * 2))}" "${JITS:=on off eager clause clause_sync}" "${SEEDS:=3}" ;;
esac

# Seeds: eine Zahl = so viele neue zufällige, sonst die Liste
case $SEEDS in
  *' '*) ;;
  *[!0-9]*) usage "-n erwartet eine Zahl oder eine Liste von Seeds" ;;
  *) n=$SEEDS; SEEDS=""
     for _ in $(seq "$n"); do SEEDS="$SEEDS $(( (RANDOM << 15 | RANDOM) % 1000000000 ))"; done ;;
esac

SCHED=$(for s in $SCHED; do [ "$s" = max ] && echo "$CORES" || echo "$s"; done | sort -n | uniq | tr '\n' ' ')
for j in $JITS; do
  case $j in on|off|eager|clause|clause_sync) ;; *) usage "unbekannte JIT-Einstellung: $j" ;; esac
done

OUT=bench/stress/out/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
SUMMARY=$OUT/summary.md
SLOW=--include\ slow
[ "$MODE" = quick ] && SLOW=""

export MIX_ENV=test
echo "Übersetzen (MIX_ENV=test) ..."
mix compile >"$OUT/compile.log" 2>&1 || { echo "mix compile scheiterte, siehe $OUT/compile.log"; exit 2; }

{
  echo "# Belastungslauf $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "Rechner: $CORES Kerne, $(uname -sm); Erlang/OTP $(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null)"
  echo "Modus: $MODE; Scheduler: $SCHED; JIT: $JITS; Seeds:$SEEDS; Wiederholungen: $REPEAT"
  echo
  echo "| Scheduler | JIT | Seed | Test | Ergebnis | Dauer |"
  echo "|---:|---|---:|---|---|---:|"
} >"$SUMMARY"

PROBLEMS=0

# ein Lauf: Name, Log, Befehl...; Ergebnis aus dem Log (ABWEICHUNG-Zeilen
# der Zufallstests, "N failures" von ExUnit)
run() {
  local s=$1 j=$2 seed=$3 name=$4 log=$5; shift 5
  local t0 t1 rc dev fails res
  printf '  %-22s ' "$name"
  t0=$(date +%s)
  "$@" >"$log" 2>&1
  rc=$?
  t1=$(date +%s)
  dev=$(grep -c '^ABWEICHUNG' "$log")
  fails=$(grep -Eo '[0-9]+ failures?' "$log" | tail -1)
  if [ "$rc" -eq 0 ] && [ "$dev" -eq 0 ]; then
    res=ok
  else
    PROBLEMS=$((PROBLEMS + 1))
    res="**PROBLEM** ($dev Abweichungen${fails:+, $fails}, rc=$rc) – $log"
  fi
  echo "$res ($((t1 - t0)) s)"
  echo "| $s | $j | $seed | $name | $res | $((t1 - t0)) s |" >>"$SUMMARY"
}

for s in $SCHED; do
  for j in $JITS; do
    export ERL_FLAGS="+S $s:$s" CONC_JIT=$j
    for seed in $SEEDS; do
      echo "== Scheduler $s, JIT $j, Seed $seed"
      tag="S$s-$j-$seed"
      CONC_RANDOM_SEED=$seed CONC_RANDOM_COLLECT=1 \
        run "$s" "$j" "$seed" concurrent_random "$OUT/$tag-concurrent_random.log" \
        mix test test/concurrent_random_test.exs $SLOW
      CLPZ_RANDOM_SEED=$seed CLPZ_RANDOM_COLLECT=1 \
        run "$s" "$j" "$seed" clpz_concurrent_random "$OUT/$tag-clpz_random.log" \
        mix test test/clpz_concurrent_random_test.exs $SLOW
    done
    echo "== Scheduler $s, JIT $j: Chaos und feste Tests"
    tag="S$s-$j"
    run "$s" "$j" - concurrent_chaos "$OUT/$tag-chaos.log" \
      mix test test/concurrent_chaos_test.exs $SLOW
    run "$s" "$j" - "feste Tests ×$REPEAT" "$OUT/$tag-fixed.log" \
      mix test test/concurrent_test.exs test/clpz_concurrent_test.exs \
      test/concurrent_robust_test.exs --repeat-until-failure "$REPEAT"
  done
done
unset ERL_FLAGS CONC_JIT

if [ "$SCALING" = 1 ]; then
  echo "== Skalierung (examples/parallel, mittel)"
  ks=$(for k in 1 2 4 8 16 32 64; do [ "$k" -lt "$CORES" ] && echo "$k"; done | tr '\n' ' ')
  MIX_ENV=dev mix compile >/dev/null 2>&1
  {
    echo
    echo "## Skalierung (examples/parallel/run.sh -t \"$ks max\" mittel)"
    echo
    MIX_ENV=dev examples/parallel/run.sh -t "$ks max" mittel 2>&1
  } >>"$SUMMARY"
fi

echo
echo "Zusammenfassung: $SUMMARY"
if [ "$PROBLEMS" -gt 0 ]; then
  echo "$PROBLEMS Läufe mit Problemen – Logs siehe Zusammenfassung."
  echo "Wiederholen: ERL_FLAGS=\"+S N:N\" CONC_JIT=… CONC_RANDOM_SEED=… CONC_RANDOM_COLLECT=1 MIX_ENV=test mix test test/concurrent_random_test.exs --include slow"
  exit 1
fi
echo "Alles in Ordnung."
