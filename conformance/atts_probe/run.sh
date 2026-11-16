#!/bin/sh
# run.sh Datei.pl – Sonde in Scryer und PrologEx, Ausgaben nebeneinander
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SCRYER=${SCRYER:-scryer-prolog}
F=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
B=${F%.pl}
(cd "$(dirname "$F")" && timeout 300 "$SCRYER" -g go -g halt "$F") > "$B.scr" 2>&1
(cd "$ROOT" && timeout 300 mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' \
   -- "$F" -g go -g halt -q 2>&1 | grep -v '^Compiling\|^Generated') > "$B.px"
diff "$B.scr" "$B.px" > "$B.diff" && echo "gleich" || echo "verschieden: $(grep -c '^[<>]' "$B.diff") Zeilen"
