#!/bin/sh
# run.sh [Max] – library(crypto) gegen die Testvektoren aus
# pyca/cryptography_vectors (pip download, nur zum Lesen entpackt) und
# gen.py: Max je Datei (Vorgabe alle, 2860 Vektoren, gut 15 Minuten).
# Ausgabe: die Zahl je Art, dann die Abweichungen (leer: alle bestanden).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
W=${TMPDIR:-/tmp}/crypto_vectors
mkdir -p "$W"
if [ ! -d "$W/cryptography_vectors" ]; then
  python3 -m pip download --no-deps --only-binary :all: -d "$W/dl" cryptography_vectors==50.0.2 >/dev/null
  python3 -m zipfile -e "$W"/dl/cryptography_vectors-50.0.2-*.whl "$W"
fi
python3 -I "$HERE/gen.py" "$W/cryptography_vectors" ${1:-} > "$W/vectors.pl"
cd "$ROOT" && mix run -e 'System.halt(PrologEx.Toplevel.main(System.argv()))' -- \
  "$HERE/check.pl" "$W/vectors.pl" \
  -g "counts(C), print(C), nl, findall(K-W, bad(K,_,W), L), print(L), nl" -g halt -q < /dev/null
