#!/bin/sh
# Demos zu library(concurrent) und library(clpz_concurrent).
#
#   examples/parallel/run.sh [-k Kerne] [-t "Kerne ..."] [klein|mittel|gross] [Demo ...]
#
# Demos: grundlagen eine alle optimieren (Vorgabe: alle vier). Jede Zeile:
# nacheinander, parallel, Faktor, Ergebnis – VERSCHIEDEN! hieße, die
# parallele Fassung gäbe etwas anderes.
#   -k N        die BEAM nutzt höchstens N Kerne (+S N:N); das Flag
#               cpu_count und damit die Zahl der Arbeiter folgen
#   -t "2 4 max"  je Demo eine Tabelle (Markdown): nacheinander und parallel
#               mit 2, 4, ... Kernen, max: ohne Grenze; jede Spalte ist ein
#               eigener Lauf, "nacheinander" die schnellste der Messungen
# Braucht einen Build (mix compile im Projekt).

DIR=$(cd "$(dirname "$0")" && pwd)
PX="$DIR/../../start_ex"
TABLE=

while getopts k:t: opt; do
  case $opt in
    k) export ERL_FLAGS="+S $OPTARG:$OPTARG${ERL_FLAGS:+ $ERL_FLAGS}" ;;
    t) TABLE=$OPTARG ;;
    *) sed -n '2,15p' "$0" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

SIZE=klein
case "$1" in klein|mittel|gross) SIZE=$1; shift ;; esac
DEMOS=${*:-grundlagen eine alle optimieren}

file() {
  case $1 in
    grundlagen) echo concurrent_grundlagen.pl ;;
    eine) echo clpz_eine.pl ;;
    alle) echo clpz_alle.pl ;;
    optimieren) echo clpz_optimieren.pl ;;
    *) echo "unbekannte Demo: $1" >&2; exit 2 ;;
  esac
}

# eine Tabelle aus den @@-Zeilen der Läufe ("Lauf;@@...")
table() {
  awk -F';' -v labels="$TABLE" '
    function sec(ms) { s = sprintf("%.2f", ms / 1000); sub(/\./, ",", s); return s " s" }
    function fak(a, b) { f = sprintf("%.1f", a / (b < 1 ? 1 : b)); sub(/\./, ",", f); return f "×" }
    $2 == "@@titel" { if (title == "") title = $3; cores[$1] = $4; if ($1 > runs) runs = $1 }
    $2 == "@@zeile" {
      name = $3
      if (!(name in seq)) { order[++n] = name; seq[name] = $4 }
      if ($4 < seq[name]) seq[name] = $4
      par[name, $1] = $5
      if ($6 != "gleich") bad[name] = 1
    }
    END {
      split(labels, lab, " ")
      printf "\n### %s\n\n| Aufgabe | nacheinander |", title
      for (r = 1; r <= runs; r++)
        printf " parallel, %s %s%s |", cores[r], (cores[r] == 1 ? "Kern" : "Kerne"), (lab[r] == "max" ? " (alle)" : "")
      printf "\n|---|---:|"
      for (r = 1; r <= runs; r++) printf "---:|"
      printf "\n"
      for (i = 1; i <= n; i++) {
        name = order[i]
        printf "| %s%s | %s |", name, (name in bad ? " (VERSCHIEDEN!)" : ""), sec(seq[name])
        for (r = 1; r <= runs; r++)
          if ((name, r) in par) printf " %s (%s) |", sec(par[name, r]), fak(seq[name], par[name, r])
          else printf " – |"
        printf "\n"
      }
    }'
}

cd "$DIR" || exit 1
for d in $DEMOS; do
  f=$(file "$d") || exit 2
  if [ -z "$TABLE" ]; then
    "$PX" -q "$f" -g "main($SIZE)" -g halt </dev/null
  else
    r=0
    for k in $TABLE; do
      r=$((r + 1))
      echo "  $d: Lauf $r ($k Kerne) ..." >&2
      if [ "$k" = max ]; then flags=$ERL_FLAGS; else flags="+S $k:$k${ERL_FLAGS:+ $ERL_FLAGS}"; fi
      ERL_FLAGS=$flags "$PX" -q "$f" -g csv -g "main($SIZE)" -g halt </dev/null |
        grep '^@@' | sed "s/^/$r;/"
    done | table
  fi
done
