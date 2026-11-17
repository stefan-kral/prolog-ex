#!/bin/sh
# run.sh – kleinere Sammlungen mit unabhängigem Orakel: holt die Quellen
# nach $OUT/src (Vorgabe tmp/small), erzeugt die Testdaten in
# test/fixtures/test_vectors neu (git diff zeigt Änderungen) und
# vergleicht char_type/2 an allen 1,1 Mio. Codepunkten mit Unicode 17.0.
#   Markus Kuhns UTF-8-test.txt (Spiegel: bittorrent/go-btfs, CC BY 4.0)
#   csv-spectrum (max-mapper/csv-spectrum, BSD-2-Clause)
#   UCD 17.0 (unicode-org/unicodetools, Unicode License v3)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:-$ROOT/tmp/small}
FIX=$ROOT/test/fixtures/test_vectors
mkdir -p "$OUT/src"
cd "$OUT/src" || exit 1
if [ ! -d btfs ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/bittorrent/go-btfs btfs
  (cd btfs && git sparse-checkout set test/sharness/t0051-object-data && git checkout -q)
fi
[ -d csv-spectrum ] || git clone -q --depth 1 https://github.com/max-mapper/csv-spectrum
if [ ! -d unicodetools ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/unicode-org/unicodetools
  (cd unicodetools && git sparse-checkout set --no-cone /unicodetools/data/ucd/17.0.0/UnicodeData.txt \
     /unicodetools/data/ucd/17.0.0/PropList.txt /unicodetools/data/ucd/17.0.0/SpecialCasing.txt && git checkout -q)
fi
UCD=$OUT/src/unicodetools/unicodetools/data/ucd/17.0.0
python3 -I "$HERE/kuhn.py" btfs/test/sharness/t0051-object-data/UTF-8-test.txt > "$FIX/utf8_kuhn.pl"
python3 -I "$HERE/csvspec.py" csv-spectrum > "$FIX/csv_spectrum.pl"
python3 -I "$HERE/ucd.py" "$UCD" > "$OUT/ucd17.txt"
python3 -I "$ROOT/priv/unicode/gen_char_classes.py" "$UCD/UnicodeData.txt" > "$ROOT/priv/unicode/char_classes.txt"
(cd "$ROOT" && git diff --stat -- test/fixtures/test_vectors priv/unicode)
(cd "$ROOT" && mix run "$HERE/ucd_check.exs" "$OUT/ucd17.txt" 2>&1 | grep -v '^Compiling\|^Generated')
