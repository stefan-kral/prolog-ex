#!/bin/sh
# run.sh - die SICStus-Benchmarks (https://sicstus.sics.se/performance.html,
# bench.zip; die Quellen liegen nicht im Repo, nur dieser Harness) in
# PrologEx, SWI-Prolog und Scryer Prolog: je Programm zuerst ein
# Ergebnis-Check (data(D), benchmark(D, R) einmal; das Ergebnis jedes
# Systems mit dem der Mehrheit verglichen), dann die Laufzeit mit dem
# harness.pl der Suite (CPU-Zeit, bestes von RUNS). Jedes Programm in
# einem eigenen Prozess (die Programme definieren alle benchmark/2,
# data/1).
#
#   BENCH_DIR=~/bench bench/sicstus/run.sh
#
# Umgebung:
#   BENCH_DIR   Ordner mit main.pl, harness.pl und den Programmen (Pflicht)
#   SYSTEMS     Systeme (Vorgabe "prologex swi scryer"; fehlt eines, fällt
#               es weg)
#   PROLOGEX    PrologEx (Vorgabe: start_ex im Repo; MIX_ENV, MIX_BUILD_ROOT
#               wie dort)
#   SWIPL       SWI-Prolog (swipl), SWI_OPTS (Vorgabe --traditional: [] ist
#               ein Atom wie in SICStus; reducer.pl braucht das)
#   SCRYER      Scryer Prolog (scryer-prolog)
#   RUNS        Läufe je Messung (Vorgabe 3)
#   SCALE       Iterationen aus main.pl geteilt durch SCALE (Vorgabe 1)
#   ONLY        nur diese Programme, durch Komma getrennt (nreverse,tak)
#   REF         Bezugssystem der Verhältnisse (Vorgabe swi)
#   TMO         Zeitgrenze je Prozess in s (Vorgabe 3600)
#   OUT         Ordner für die Rohdaten (Vorgabe: neuer Ordner in /tmp);
#               ein vorhandener: gemessene Programme ersetzen ihre Zeile
#   TABLE_ONLY  nicht messen, nur die Tabelle aus OUT

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

: "${BENCH_DIR:?BENCH_DIR: Ordner der entpackten bench.zip (main.pl, harness.pl, ...)}"
B=$(cd "$BENCH_DIR" && pwd) || exit 1
[ -f "$B/main.pl" ] && [ -f "$B/harness.pl" ] || { echo "run.sh: $B ohne main.pl/harness.pl" >&2; exit 1; }

PX=${PROLOGEX-$ROOT/start_ex}
SW=${SWIPL-swipl}
SWO=${SWI_OPTS---traditional}
SC=${SCRYER-scryer-prolog}
RUNS=${RUNS:-3}
SCALE=${SCALE:-1}
REF=${REF:-swi}
TMO=${TMO:-3600}
OUT=${OUT:-$(mktemp -d /tmp/sicstus-bench.XXXXXX)}
mkdir -p "$OUT"

have() { command -v "$1" >/dev/null 2>&1; }
systems=""
for s in ${SYSTEMS:-prologex swi scryer}; do
  case $s in
    prologex) [ -x "$PX" ] || have "$PX" && systems="$systems $s" ;;
    swi) have "$SW" && systems="$systems $s" ;;
    scryer) have "$SC" && systems="$systems $s" ;;
  esac
done
[ -n "$systems" ] || { echo "run.sh: kein System gefunden" >&2; exit 1; }

# System Ziel: Driver und Prelude laden, Ziel ausführen (im Ordner der Suite)
run() {
  case $1 in
    prologex) (cd "$B" && timeout "$TMO" "$PX" -q "$HERE/prelude_prologex.pl" "$HERE/driver.pl" -g "$2" -g halt) ;;
    swi) (cd "$B" && timeout "$TMO" "$SW" $SWO -q -g "$2" -t halt "$HERE/prelude_swi.pl" "$HERE/driver.pl") ;;
    scryer) (cd "$B" && timeout "$TMO" "$SC" "$HERE/prelude_scryer.pl" "$HERE/driver.pl" -g "$2" -g halt) ;;
  esac </dev/null
}

# Programme und Iterationen aus main.pl: (:-[name],bench(N)).
progs=$(sed -n 's/^(:-\[\([a-z_]*\)\],bench(\([0-9]*\))).*/\1:\2/p' "$B/main.pl")
if [ -n "$ONLY" ]; then
  sel=""
  for p in $progs; do
    case ",$ONLY," in *",${p%%:*},"*) sel="$sel $p" ;; esac
  done
  progs=$sel
fi

[ -n "$TABLE_ONLY" ] && progs=""
[ -n "$progs" ] && echo "Systeme:$systems   Läufe: $RUNS   SCALE: $SCALE   Rohdaten: $OUT" >&2
touch "$OUT/progs"
for p in $progs; do
  name=${p%%:*}
  n=$(( ${p##*:} / SCALE )); [ "$n" -ge 1 ] || n=1
  for s in $systems; do
    run $s "sb_check('$name.pl')" > "$OUT/$s.$name.check" 2>&1
    r=$(grep '^RESULT ' "$OUT/$s.$name.check" | head -1)
    [ -n "$r" ] || r="RESULT none"
    echo "$r" > "$OUT/$s.$name.result"
    run $s "sb_time('$name.pl', $n, $RUNS)" > "$OUT/$s.$name.time" 2>&1
    ms=$(sed -n 's/.*iterations taking *\([0-9][0-9]*\) msec.*/\1/p' "$OUT/$s.$name.time" | sort -n | head -1)
    echo "${ms:--}" > "$OUT/$s.$name.ms"
    echo "$name $s: ${ms:--} ms, $(cut -c8-40 "$OUT/$s.$name.result")" >&2
  done
  { grep -v "^$name " "$OUT/progs"; echo "$name $n"; } | sort > "$OUT/progs.new"
  mv "$OUT/progs.new" "$OUT/progs"
done

# Tabelle: ms je System; Ergebnis gegen die Mehrheit (✗ abweichend,
# ✗F gescheitert/Fehler); Verhältnis zum Bezugssystem; geometrisches
# Mittel über die Programme, die überall stimmen
awk -v systems="$systems" -v ref="$REF" -v out="$OUT" '
function slurp(f,   l) { l = ""; if ((getline l < f) > 0) {} close(f); return l }
BEGIN {
  ns = split(systems, S, " ")
  for (i = 1; i <= ns; i++) if (S[i] == ref) r = i
  printf "%-20s %9s", "Programm", "Iter."
  for (i = 1; i <= ns; i++) printf " %14s", S[i] " ms"
  if (r) for (i = 1; i <= ns; i++) if (i != r) printf " %12s", S[i] "/" ref
  printf "\n"
}
{
  name = $1; iter = $2
  delete cnt; best = ""; bc = 0
  for (i = 1; i <= ns; i++) {
    res[i] = slurp(out "/" S[i] "." name ".result")
    ms[i] = slurp(out "/" S[i] "." name ".ms")
    if (res[i] ~ /^RESULT ok/) { cnt[res[i]]++; if (cnt[res[i]] > bc) { bc = cnt[res[i]]; best = res[i] } }
  }
  if (bc < 2 && ns > 1) best = ""   # keine Mehrheit
  printf "%-20s %9s", name, iter
  for (i = 1; i <= ns; i++) {
    mark = ""
    if (res[i] !~ /^RESULT ok/) mark = " ✗F"
    else if (best != "" && res[i] != best) mark = " ✗"
    else if (best == "" && ns > 1) mark = " ?"
    ok[i] = (mark == "")
    printf " %14s", ms[i] mark
  }
  if (r) for (i = 1; i <= ns; i++) if (i != r) {
    if (ok[i] && ok[r] && ms[i] > 0 && ms[r] > 0) {
      q = ms[i] / ms[r]; printf " %12.2f", q; lg[i] += log(q); nq[i]++
    } else printf " %12s", "-"
  }
  printf "\n"
}
END {
  if (r) {
    printf "%-20s %9s", "geom. Mittel", ""
    for (i = 1; i <= ns; i++) printf " %14s", ""
    for (i = 1; i <= ns; i++) if (i != r) printf " %12s", nq[i] ? sprintf("%.2f (%d)", exp(lg[i] / nq[i]), nq[i]) : "-"
    printf "\n"
  }
}' "$OUT/progs" | tee "$OUT/table.txt"
